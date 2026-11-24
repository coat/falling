pub const std_options: std.Options = if (builtin.abi.isAndroid())
    .{ .logFn = @import("android").logFn }
else
    .{};

pub const panic = if (builtin.abi.isAndroid())
    @import("android").panic
else
    std.debug.FullPanic(std.debug.defaultPanic);

pub fn main() !u8 {
    var empty_argv: [0:null]?[*:0]u8 = .{};
    const status: u8 = @truncate(@as(c_uint, @bitCast(c.SDL_RunApp(empty_argv.len, @ptrCast(&empty_argv), sdlMain, null))));
    return app_err.load() orelse status;
}

comptime {
    if (builtin.abi.isAndroid()) {
        @export(&sdlMain, .{ .name = "SDL_main", .linkage = .strong });
    }
}

export fn app_is_ready() c_int {
    return @intFromBool(live_app != null);
}

export fn app_set_canvas_size(w: c_int, h: c_int) void {
    if (live_app) |*app| app.setCanvasSize(w, h);
}

fn sdlMain(argc: c_int, argv: ?[*:null]?[*:0]u8) callconv(.c) c_int {
    return c.SDL_EnterAppMainCallbacks(argc, @ptrCast(argv), sdlAppInit, sdlAppIterate, sdlAppEvent, sdlAppQuit);
}

fn sdlAppInit(appstate: ?*?*anyopaque, argc: c_int, argv: ?[*:null]?[*:0]u8) callconv(.c) c.SDL_AppResult {
    _ = argc;
    _ = argv;
    live_app = .{};
    live_app.?.init() catch |err| return app_err.store(err);

    appstate.?.* = @ptrCast(@alignCast(&live_app.?));

    return c.SDL_APP_CONTINUE;
}

fn sdlAppIterate(appstate: ?*anyopaque) callconv(.c) c.SDL_AppResult {
    const app: *App = @ptrCast(@alignCast(appstate.?));
    return app.iterate() catch |err| app_err.store(err);
}

fn sdlAppEvent(appstate: ?*anyopaque, event: ?*c.SDL_Event) callconv(.c) c.SDL_AppResult {
    const app: *App = @ptrCast(@alignCast(appstate.?));
    return app.handleEvent(event.?) catch |err| app_err.store(err);
}

fn sdlAppQuit(appstate: ?*anyopaque, result: c.SDL_AppResult) callconv(.c) void {
    const app_result = app_err.load() orelse result;
    _ = app_result catch |err| if (err == error.SdlError) {
        sdl_log.err("{s}", .{c.SDL_GetError()});
    };
    if (appstate) |ptr| {
        const app: *App = @ptrCast(@alignCast(ptr));
        app.deinit();
    }
}

var live_app: ?App = null;

var app_err: ErrorStore = .{};

const ErrorStore = struct {
    const status_not_stored = 0;
    const status_storing = 1;
    const status_stored = 2;

    status: c.SDL_AtomicInt = .{ .value = status_not_stored },
    err: anyerror = undefined,
    trace_index: usize = undefined,
    trace_addrs: [32]usize = undefined,

    fn store(es: *ErrorStore, err: anyerror) c.SDL_AppResult {
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

    fn load(es: *ErrorStore) ?anyerror {
        if (c.SDL_GetAtomicInt(&es.status) != status_stored) return null;
        if (@errorReturnTrace()) |dst_trace| {
            dst_trace.index = es.trace_index;
            const len = @min(dst_trace.instruction_addresses.len, es.trace_addrs.len);
            @memcpy(dst_trace.instruction_addresses[0..len], es.trace_addrs[0..len]);
        }
        return es.err;
    }
};

const std = @import("std");
const builtin = @import("builtin");

const sdl = @import("sdl.zig");
const c = sdl.c;

const App = @import("App.zig");

const sdl_log = std.log.scoped(.sdl);
