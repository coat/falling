const std = @import("std");

pub fn build(b: *std.Build) void {
    const name = "falling";

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const coverage = b.option(bool, "coverage", "Generate a coverage report with kcov") orelse false;

    const strip = b.option(
        bool,
        "strip",
        "Strip the final executable. Default true for fast and small releases",
    ) orelse switch (optimize) {
        .Debug, .ReleaseSafe => false,
        .ReleaseFast, .ReleaseSmall => true,
    };
    const system_sdl = b.option(bool, "system_sdl", "Use system provided SDL") orelse true;

    var system_include_path: ?std.Build.LazyPath = null;
    var lto: ?std.zig.LtoMode = null;
    switch (target.result.os.tag) {
        .emscripten => {
            if (b.sysroot) |sysroot| {
                system_include_path = .{ .cwd_relative = b.pathJoin(&.{ sysroot, "include" }) };
            } else {
                std.log.err("'--sysroot' is required when building for Emscripten", .{});
                std.process.exit(1);
            }
            if (optimize != .Debug) {
                lto = .full;
            }
        },
        else => {},
    }

    const entt_mod = b.dependency("entt", .{
        .target = target,
        .optimize = optimize,
    }).module("zig-ecs");

    const ulzig_mod = b.dependency("ulzig", .{
        .target = target,
        .optimize = optimize,
    }).module("ulzig");

    const mod = b.addModule(name, .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = target.result.os.tag == .emscripten,
        .imports = &.{
            .{ .name = "entt", .module = entt_mod },
            .{ .name = "ulz", .module = ulzig_mod },
        },
    });

    const ulzig_dep = b.dependency("ulzig", .{
        .target = b.graph.host,
    });

    const ulz = b.addExecutable(.{
        .name = "ulz",
        .root_module = ulzig_dep.module("exe"),
    });

    const compress_sprites = b.addRunArtifact(ulz);
    compress_sprites.addArg("-o");
    const compressed_sprites = compress_sprites.addOutputFileArg("sprites.bmp.ulz");
    compress_sprites.addFileArg(b.path("assets/sprites.bmp"));

    mod.addAnonymousImport("sprites.bmp.ulz", .{ .root_source_file = compressed_sprites });

    if (target.result.os.tag == .windows and target.result.abi == .msvc) {
        // Work around a problematic definition in wchar.h in Windows SDK version 10.0.26100.0
        mod.addCMacro("_Avx2WmemEnabledWeakValue", "_Avx2WmemEnabled");
    }
    if (system_include_path) |path| {
        mod.addSystemIncludePath(path);
    }

    if (system_sdl and target.result.os.tag != .emscripten) {
        mod.linkSystemLibrary("SDL3", .{});
        mod.link_libc = true;
    } else {
        const sdl_dep = b.dependency("sdl", .{
            .target = target,
            .optimize = optimize,
            .lto = lto,
        });
        mod.linkLibrary(sdl_dep.artifact("SDL3"));
    }

    const run_step = b.step("run", "Run the app");
    const test_step = b.step("test", "Run tests");

    if (target.result.os.tag == .emscripten) {
        const app_lib = b.addLibrary(.{
            .linkage = .static,
            .name = name,
            .root_module = b.addModule("em_mod", .{
                .root_source_file = b.path("src/main.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = name, .module = mod },
                },
            }),
        });
        app_lib.want_lto = optimize != .Debug;

        const run_emcc = b.addSystemCommand(&.{"emcc"});

        for (app_lib.getCompileDependencies(false)) |lib| {
            if (lib.isStaticLibrary()) {
                run_emcc.addArtifactArg(lib);
            }
        }

        if (target.result.cpu.arch == .wasm64) {
            run_emcc.addArg("-sMEMORY64");
        }
        run_emcc.addArg("-sALLOW_MEMORY_GROWTH=1");
        run_emcc.addArg("-sMODULARIZE");
        run_emcc.addArg("-sEXPORTED_FUNCTIONS=_emscripten_builtin_realloc,_realloc,_main");
        run_emcc.addArg("-sEXPORTED_RUNTIME_METHODS=requestFullscreen");

        run_emcc.addArgs(switch (optimize) {
            .Debug => &.{
                "-O0",
                // Preserve DWARF debug information.
                "-g",
                // Use UBSan (full runtime).
                "-fsanitize=undefined",
            },
            .ReleaseSafe => &.{
                "-O3",
                // Use UBSan (minimal runtime).
                "-fsanitize=undefined",
                "-fsanitize-minimal-runtime",
            },
            .ReleaseFast => &.{
                "-sUSE_OFFSET_CONVERTER=1", // Required by Zig's '@returnAddress'
                "-O3",
            },
            .ReleaseSmall => &.{
                "-Oz",
            },
        });

        if (optimize != .Debug) {
            // Perform link time optimization.
            run_emcc.addArg("-flto");
            // Minify JavaScript code.
            run_emcc.addArgs(&.{ "--closure", "1" });
        }

        run_emcc.addArg("-o");
        const app_html = run_emcc.addOutputFileArg("index.html");

        run_emcc.addArg("--shell-file");
        run_emcc.addFileArg(b.path("src/shell.html"));

        b.getInstallStep().dependOn(&b.addInstallDirectory(.{
            .source_dir = app_html.dirname(),
            .install_dir = .{ .custom = "www" },
            .install_subdir = "",
        }).step);

        const run_emrun = b.addSystemCommand(&.{"emrun"});
        run_emrun.addArg(b.pathJoin(&.{ b.install_path, "www", "index.html" }));
        if (b.args) |args| run_emrun.addArgs(args);
        run_emrun.step.dependOn(b.getInstallStep());

        run_step.dependOn(&run_emrun.step);
    } else {
        const exe = b.addExecutable(.{
            .name = name,
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = name, .module = mod },
                },
            }),
        });

        const install_step = b.addInstallArtifact(exe, .{});
        b.getInstallStep().dependOn(&install_step.step);

        if (strip and target.result.os.tag == .linux) {
            const sstrip = std.Build.Step.Run.create(b, "run sstrip");
            sstrip.addArgs(&.{"sstrip"});
            sstrip.addArtifactArg(exe);
            install_step.step.dependOn(&sstrip.step);
        }

        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);
        run_step.dependOn(&run_cmd.step);

        run_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const exe_tests = b.addTest(.{
            .root_module = exe.root_module,
        });

        const run_exe_tests = b.addRunArtifact(exe_tests);
        test_step.dependOn(&run_exe_tests.step);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
        .use_llvm = coverage,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);
    test_step.dependOn(&run_mod_tests.step);

    if (coverage) {
        const kcov_bin = b.findProgram(&.{"kcov"}, &.{}) catch "kcov";

        const merge_step = std.Build.Step.Run.create(b, "merge coverage");
        merge_step.addArgs(&.{ kcov_bin, "--merge" });
        merge_step.rename_step_with_output_arg = false;
        const merged_coverage_output = merge_step.addOutputFileArg(".");

        // prepend the kcov exec args
        const argv = run_mod_tests.argv.toOwnedSlice(b.allocator) catch @panic("OOM");
        run_mod_tests.addArgs(&.{ kcov_bin, "--collect-only" });
        run_mod_tests.addPrefixedDirectoryArg("--include-pattern=", b.path("src"));
        merge_step.addDirectoryArg(run_mod_tests.addOutputFileArg(run_mod_tests.producer.?.name));
        run_mod_tests.argv.appendSlice(b.allocator, argv) catch @panic("OOM");

        const install_coverage = b.addInstallDirectory(.{
            .source_dir = merged_coverage_output,
            .install_dir = .{ .custom = "coverage" },
            .install_subdir = "",
        });
        test_step.dependOn(&install_coverage.step);
    }
}
