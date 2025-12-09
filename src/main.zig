fn sdlAppInit(appstate: *?*Game, _: [][:0]const u8) !c.SDL_AppResult {
    try errify(c.SDL_SetAppMetadata(Game.name, "0.1.0", "com.sadbeast"));

    try errify(c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO | c.SDL_INIT_GAMEPAD));

    errify(c.SDL_SetHint(c.SDL_HINT_RENDER_VSYNC, "1")) catch {};

    var game = try Game.init(alloc);
    errdefer game.deinit();

    appstate.* = game;

    errdefer comptime unreachable;

    return c.SDL_APP_CONTINUE;
}

fn sdlAppIterate(appstate: ?*Game) !c.SDL_AppResult {
    if (appstate) |s| {
        return s.iterate();
    }

    return c.SDL_APP_CONTINUE;
}

fn sdlAppEvent(game: ?*Game, event: *c.SDL_Event) !c.SDL_AppResult {
    if (game) |g| {
        return g.processInput(event);
    }

    return c.SDL_APP_CONTINUE;
}

fn sdlAppQuit(appstate: ?*Game, result: anyerror!c.SDL_AppResult) void {
    _ = result catch |err| if (err == error.SdlError) {
        sdl_log.err("{s}", .{c.SDL_GetError()});
    };

    if (appstate) |s| {
        s.deinit();
        alloc.destroy(s);

        if (is_debug_allocator) {
            _ = debug_allocator.deinit();
        }
    }
}

pub const ErrorStore = struct {
    const status_not_stored = 0;
    const status_storing = 1;
    const status_stored = 2;

    status: c.SDL_AtomicInt = .{},
    err: anyerror = undefined,
    trace_index: usize = undefined,
    trace_addrs: [32]usize = undefined,

    pub fn reset(es: *ErrorStore) void {
        _ = c.SDL_SetAtomicInt(&es.status, status_not_stored);
    }

    pub fn store(es: *ErrorStore, err: anyerror) c.SDL_AppResult {
        if (c.SDL_CompareAndSwapAtomicInt(&es.status, status_not_stored, status_storing)) {
            es.err = err;
            if (@errorReturnTrace()) |src_trace| {
                es.trace_index = src_trace.index;
                const len = @min(es.trace_addrs.len, src_trace.instruction_addresses.len);
                @memcpy(es.trace_addrs[0..len], src_trace.instruction_addresses[0..len]);
            }
            _ = c.SDL_SetAtomicInt(&es.status, status_stored);
        }
        return c.SDL_APP_FAILURE;
    }

    pub fn load(es: *ErrorStore) ?anyerror {
        if (c.SDL_GetAtomicInt(&es.status) != status_stored) return null;
        if (@errorReturnTrace()) |dst_trace| {
            dst_trace.index = es.trace_index;
            const len = @min(dst_trace.instruction_addresses.len, es.trace_addrs.len);
            @memcpy(dst_trace.instruction_addresses[0..len], es.trace_addrs[0..len]);
        }
        return es.err;
    }
};

//#region SDL main callbacks boilerplate

pub fn main() !u8 {
    alloc, is_debug_allocator = gpa: {
        if (builtin.os.tag == .emscripten) break :gpa .{ std.heap.c_allocator, false };
        if (builtin.os.tag == .wasi) break :gpa .{ std.heap.wasm_allocator, false };
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };

    app_err.reset();

    var empty_argv: [0:null]?[*:0]u8 = .{};

    const status: u8 = @truncate(@as(c_uint, @bitCast(c.SDL_RunApp(empty_argv.len, @ptrCast(&empty_argv), sdlMainC, null))));
    return app_err.load() orelse status;
}

fn sdlMainC(argc: c_int, argv: ?[*:null]?[*:0]u8) callconv(.c) c_int {
    return c.SDL_EnterAppMainCallbacks(argc, @ptrCast(argv), sdlAppInitC, sdlAppIterateC, sdlAppEventC, sdlAppQuitC);
}

fn sdlAppInitC(appstate: ?*?*anyopaque, argc: c_int, argv: ?[*:null]?[*:0]u8) callconv(.c) c.SDL_AppResult {
    return sdlAppInit(@ptrCast(appstate.?), @ptrCast(argv.?[0..@intCast(argc)])) catch |err| app_err.store(err);
}

fn sdlAppIterateC(appstate: ?*anyopaque) callconv(.c) c.SDL_AppResult {
    return sdlAppIterate(@ptrCast(@alignCast(appstate))) catch |err| app_err.store(err);
}

fn sdlAppEventC(appstate: ?*anyopaque, event: ?*c.SDL_Event) callconv(.c) c.SDL_AppResult {
    return sdlAppEvent(@ptrCast(@alignCast(appstate)), event.?) catch |err| app_err.store(err);
}

fn sdlAppQuitC(appstate: ?*anyopaque, result: c.SDL_AppResult) callconv(.c) void {
    sdlAppQuit(@ptrCast(@alignCast(appstate)), app_err.load() orelse result);
}

//#endregion SDL main callbacks boilerplate

var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
var is_debug_allocator: bool = true;

var alloc: std.mem.Allocator = undefined;

var app_err: ErrorStore = .{};

const falling = @import("falling");
const Game = falling.Game;
const c = falling.c;
const errify = falling.errify;
const sdl_log = falling.sdl_log;

const std = @import("std");
const builtin = @import("builtin");
