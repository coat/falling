pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const opts: Options = .{
        .target = target,
        .optimize = optimize,
        .strip = b.option(
            bool,
            "strip",
            "Strip the final executable. Defaults on for the release optimize modes",
        ),
        .link_sdl = b.option(
            bool,
            "link_sdl",
            "Use the SDL3 the platform provides instead of building it: the system library natively, " ++
                "emscripten's '--use-port=sdl3' on the web. Default true for Linux targets",
        ) orelse (target.result.os.tag == .linux and !target.result.abi.isAndroid()),
        .em_sysroot = b.option(
            []const u8,
            "em_sysroot",
            "Emscripten's cache sysroot, holding the wasm libc (and SDL3 port) headers. " ++
                "Defaults to $EM_CACHE/sysroot",
        ),
        .android = b.option(bool, "android", "Assemble " ++ name ++ ".apk in zig-out/bin") orelse false,
        .portmaster = b.option(bool, "portmaster", "Assemble a PortMaster package in zig-out/portmaster.") orelse false,
    };

    const game = addGameModule(b, opts);
    // const mod = addModule(b, opts);

    b.modules.putNoClobber(b.graph.arena, name, game) catch @panic("OOM");

    if (opts.emscripten()) {
        addWeb(b, opts, game);
        return;
    }

    if (opts.android) {
        addAndroid(b, opts);
        return;
    }

    if (opts.portmaster) {
        addPortmaster(b, opts);
        return;
    }

    const exe = addExe(b, opts, game);
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    run_cmd.addPassthruArgs();

    const mod_tests = b.addTest(.{ .root_module = game });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}

const std = @import("std");
const Translator = @import("translate_c").Translator;

const name = "falling";

const c_header =
    \\#define SDL_DISABLE_OLD_NAMES
    \\#include <SDL3/SDL.h>
    \\#include <SDL3/SDL_revision.h>
    \\#define SDL_MAIN_HANDLED
    \\#include <SDL3/SDL_main.h>
;

const SdlSource = enum {
    vendored,
    system,
    emscripten,
};

const Options = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    strip: ?bool = null,
    link_sdl: bool = false,
    em_sysroot: ?[]const u8 = null,
    android: bool = false,
    portmaster: bool = false,

    fn lto(self: Options) ?std.zig.LtoMode {
        return if (self.emscripten() and self.optimize != .debug) .full else null;
    }

    fn stripBinary(self: Options) bool {
        return self.strip orelse switch (self.optimize) {
            .debug, .safe => false,
            .fast, .small => true,
        };
    }

    fn emscripten(self: Options) bool {
        return self.target.result.os.tag == .emscripten;
    }

    fn sdlSource(self: Options) SdlSource {
        if (!self.link_sdl) return .vendored;
        return if (self.emscripten()) .emscripten else .system;
    }

    fn sysrootInclude(self: Options, b: *std.Build) ?std.Build.LazyPath {
        if (!self.emscripten()) return null;
        return .{ .cwd_relative = b.pathJoin(&.{ self.sysroot(b), "include" }) };
    }

    fn sysroot(self: Options, b: *std.Build) []const u8 {
        if (self.em_sysroot) |dir| return dir;
        if (b.graph.environ_map.get("EM_CACHE")) |cache| return b.pathJoin(&.{ cache, "sysroot" });
        std.log.err("Emscripten builds need a sysroot. Set EM_CACHE " ++
            "or pass -Dem_sysroot=/path/to/emscripten/cache/sysroot", .{});
        std.process.exit(1);
    }
};

fn addGameModule(b: *std.Build, opts: Options) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("src/game/root.zig"),
        .target = opts.target,
        .optimize = opts.optimize,
        .strip = opts.strip,
    });
}

fn addAppModule(b: *std.Build, opts: Options, game: *std.Build.Module) *std.Build.Module {
    const sdl_source = opts.sdlSource();

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = opts.target,
        .optimize = opts.optimize,
        .strip = opts.strip,
        .link_libc = opts.target.result.abi.isAndroid() or opts.emscripten() or opts.link_sdl,
        .imports = &.{.{ .name = name, .module = game }},
    });

    const sdl_system_lib: []const Translator.LinkSystemLib = &.{.{ .name = "SDL3" }};

    const translate_c = b.dependency("translate_c", .{});
    const translator: Translator = .init(translate_c, .{
        .c_source_file = b.addWriteFiles().add("c.h", c_header),
        .target = opts.target,
        .optimize = opts.optimize,
        .link_system_libs = if (sdl_source == .system) sdl_system_lib else &.{},
    });

    if (opts.sysrootInclude(b)) |include| {
        mod.addSystemIncludePath(include);
        translator.addSystemIncludePath(include);
    }

    switch (sdl_source) {
        .system => mod.linkSystemLibrary("SDL3", .{}),
        .emscripten => {},
        .vendored => if (sdlDependency(b, opts)) |dep| {
            const sdl_lib = dep.artifact("SDL3");
            mod.linkLibrary(sdl_lib);
            translator.linkLibrary(sdl_lib);
        },
    }

    if (opts.target.result.abi.isAndroid()) {
        translator.defineCMacro("_Nullable", "");
        translator.defineCMacro("_Nonnull", "");
        translator.defineCMacro("_FORTIFY_SOURCE", "0");
        translator.defineCMacro("__ANDROID_API__", b.fmt("{d}", .{opts.target.result.os.version_range.linux.android}));
    }

    mod.addImport("c", translator.mod);

    const options = b.addOptions();
    options.addOption([:0]const u8, "name", name);
    options.addOption(
        [:0]const u8,
        "version",
        @import("./build.zig.zon").version,
    );
    mod.addImport("options", options.createModule());

    mod.addAnonymousImport("icon.png", .{ .root_source_file = b.path("assets/icon.png") });

    return mod;
}

fn addExe(b: *std.Build, opts: Options, game: *std.Build.Module) *std.Build.Step.Compile {
    const exe = b.addExecutable(.{
        .name = name,
        .root_module = addAppModule(b, opts, game),
    });
    if (opts.target.result.ofmt == .coff) addWindowsResources(b, opts, exe.root_module);
    return exe;
}

fn addWindowsResources(b: *std.Build, opts: Options, mod: *std.Build.Module) void {
    const rc = b.lazyImport(@This(), "rc") orelse return;
    const rc_dep = b.lazyDependency("rc", .{}) orelse return;

    var compiler: rc.Compiler = .init(rc_dep, .{
        .rc_files = &.{b.path("assets/falling.rc")},
        .target = opts.target,
        .optimize = opts.optimize,
    });
    mod.addObjectFile(compiler.getObjectFile());
}

fn addWeb(b: *std.Build, opts: Options, game: *std.Build.Module) void {
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = name,
        .root_module = addAppModule(b, opts, game),
    });
    lib.lto = opts.lto();

    const emcc = b.addSystemCommand(&.{"emcc"});

    for (lib.getCompileDependencies(false)) |dep| {
        if (dep.isStaticLibrary()) emcc.addArtifactArg(dep);
    }

    if (opts.sdlSource() == .emscripten) {
        emcc.addArgs(&.{ "--use-port=sdl3", "-Wno-experimental" });
    } else {
        emcc.addArg("-lidbfs.js");
    }

    if (opts.target.result.cpu.arch == .wasm64) emcc.addArg("-sMEMORY64");
    emcc.addArgs(&.{
        "-sALLOW_MEMORY_GROWTH=1",
        // "-sSTACK_SIZE=1MB",

        "-sMODULARIZE",
        "-sEXPORTED_FUNCTIONS=_emscripten_builtin_realloc,_realloc,_main,_app_set_canvas_size,_app_is_ready",
    });

    emcc.addArgs(switch (opts.optimize) {
        .debug => &.{
            "-O0",
            // Preserve DWARF debug information.
            "-g",
            // Use UBSan (full runtime).
            "-fsanitize=undefined",
        },
        .safe => &.{
            "-O3",
            // Use UBSan (minimal runtime).
            "-fsanitize=undefined",
            "-fsanitize-minimal-runtime",
        },
        .fast => &.{"-O3"},
        .small => &.{"-Oz"},
    });

    if (opts.optimize != .debug) {
        emcc.addArg("-flto");
        // Minify the generated js glue.
        emcc.addArgs(&.{ "--closure", "1" });
    }

    emcc.addArg("-o");
    const html = emcc.addOutputFileArg(name ++ ".html");
    emcc.addArg("--shell-file");
    emcc.addFileArg(b.path("src/www/shell.html"));

    b.getInstallStep().dependOn(&b.addInstallDirectory(.{
        .source_dir = html.dirname(),
        .install_dir = .{ .custom = "www" },
        .install_subdir = "",
    }).step);

    b.getInstallStep().dependOn(&b.addInstallDirectory(.{
        .source_dir = b.path("src/www"),
        .install_dir = .{ .custom = "www" },
        .install_subdir = "",
        .exclude_extensions = &.{"shell.html"},
    }).step);

    b.getInstallStep().dependOn(&b.addInstallFile(b.path("assets/icon.png"), "www/icon.png").step);

    const emrun = b.addSystemCommand(&.{"emrun"});
    emrun.addFileArg(.{ .relative = .{ .base = .install_prefix, .sub_path = "www/index.html" } });
    emrun.addPassthruArgs();
    emrun.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Serve the web build with emrun");
    run_step.dependOn(&emrun.step);
}

fn addAndroid(b: *std.Build, opts: Options) void {
    if (b.graph.environ_map.get("ANDROID_HOME") == null) {
        b.getInstallStep().dependOn(&b.addFail("ANDROID_HOME is not set.").step);
        return;
    }

    const android = b.lazyImport(@This(), "android") orelse return;
    const sdk = android.Sdk.create(b, .{ .cmdline_version = "20.0" });
    const apk = sdk.createApk(.{
        .name = name,
        .api_level = .android15,
        .build_tools_version = "36.1.0",
        .ndk_version = "29.0.14206865",
    });

    // A throwaway debug key: enough for `adb install`, not for distribution.
    apk.setKeyStore(sdk.createKeyStore(.example));
    apk.setAndroidManifest(b.path("android/AndroidManifest.xml"));
    apk.addResourceDirectory(b.path("android/res"));

    const every_abi = b.option(
        bool,
        "android_abis",
        "Put every Android ABI in the APK (x86_64, armeabi-v7a, x86) instead of arm64-v8a alone",
    ) orelse false;

    const targets = android.resolveTargets(b, .{
        .default_target = opts.target,
        .all_targets = true,
        .api_level = .android9,
    });
    var java_added = false;
    for (targets) |target| {
        if (!every_abi and target.result.cpu.arch != .aarch64) continue;

        const android_opts: Options = .{
            .target = target,
            .optimize = .small,
            .strip = opts.strip,
        };

        if (!java_added) if (sdlDependency(b, android_opts)) |dep| {
            for (dep.namedWriteFiles("java").copies.items) |copy| {
                apk.addJavaSourceFile(.{ .file = copy.src_file });
            }
            java_added = true;
        };

        const lib = b.addLibrary(.{
            .name = "main",
            .linkage = .dynamic,
            .root_module = addAppModule(b, android_opts, addGameModule(b, android_opts)),
        });

        const android_dep = b.dependency("android", .{
            .target = target,
            .optimize = android_opts.optimize,
        });
        lib.root_module.addImport("android", android_dep.module("android"));
        apk.addArtifact(lib);
    }

    const installed = apk.addInstallApk();
    b.getInstallStep().dependOn(&installed.step);

    const adb_start = sdk.addAdbStart("com.sadbeast." ++ name ++ "/org.libsdl.app.SDLActivity");
    adb_start.step.dependOn(&sdk.addAdbInstall(installed.source).step);
    const run_step = b.step("run", "Install the APK on a connected device and start it");
    run_step.dependOn(&adb_start.step);
}

fn addPortmaster(b: *std.Build, opts: Options) void {
    const pm_opts: Options = .{
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .aarch64,
            .os_tag = .linux,
            .abi = .gnu,
            .glibc_version = .{ .major = 2, .minor = 30, .patch = 0 },
        }),
        .optimize = opts.optimize,
        .strip = opts.strip,
    };
    const exe = addExe(b, pm_opts, addGameModule(b, pm_opts));

    b.getInstallStep().dependOn(&b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = .{ .custom = "portmaster/" ++ name } },
        .dest_sub_path = name ++ ".aarch64",
    }).step);
    b.getInstallStep().dependOn(&b.addInstallDirectory(.{
        .source_dir = b.path("portmaster"),
        .install_dir = .{ .custom = "portmaster" },
        .install_subdir = "",
    }).step);
}

fn sdlDependency(b: *std.Build, opts: Options) ?*std.Build.Dependency {
    if (opts.sysrootInclude(b)) |include| return b.lazyDependency("sdl", .{
        .target = opts.target,
        .optimize = opts.optimize,
        .strip = opts.stripBinary(),
        .lto = opts.lto(),
        .system_include_path = include,
        .build_config_h_overrides = @as([]const []const u8, &.{
            "-DSDL_EMSCRIPTEN_PERSISTENT_PATH_STRING=/storage",
        }),
    });
    return b.lazyDependency("sdl", .{
        .target = opts.target,
        .optimize = opts.optimize,
        .strip = opts.stripBinary(),
        .lto = opts.lto(),
    });
}
