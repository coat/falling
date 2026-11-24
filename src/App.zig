//! Ties SDL to the Game - window, player input, high score
window: *c.SDL_Window = undefined,
renderer: Renderer = undefined,
timekeeper: Timekeeper = undefined,
layout: ui.Layout = undefined,
stick: TouchStick.Dir = .none,
stick_y: StickY = .none,
touch: TouchStick = .{},
touch_ui: bool = false,

fps: ?Fps = null,

gamepad: ?*c.SDL_Gamepad = null,
game: Game = undefined,
high_score: HighScore = .{},
screen: ui.Screen = .title,
focus: usize = 0,
last_menu: ?[]const ui.MenuItem = null,

pub fn init(app: *App) !void {
    try errify(c.SDL_SetAppMetadata(options.name, options.version, "com.sadbeast." ++ options.name));

    errify(c.SDL_Init(c.SDL_INIT_GAMEPAD)) catch {
        sdl_log.warn("gamepad unavailable: {s}", .{c.SDL_GetError()});
    };
    errify(c.SDL_InitSubSystem(c.SDL_INIT_AUDIO)) catch {
        sdl_log.warn("audio unavailable: {s}", .{c.SDL_GetError()});
    };

    try errify(c.SDL_InitSubSystem(c.SDL_INIT_VIDEO));

    sdl_log.debug("SDL video drivers: {f}", .{fmtSdlDrivers(
        c.SDL_GetCurrentVideoDriver().?,
        c.SDL_GetNumVideoDrivers(),
        c.SDL_GetVideoDriver,
    )});

    const render_driver: ?[*:0]const u8 = c.SDL_GetRenderDriver(0);
    sdl_log.debug("Render driver: {s}", .{render_driver.?});

    const driver: ?[*:0]const u8 = c.SDL_GetCurrentVideoDriver();
    const is_kmsdrm = driver != null and std.mem.eql(u8, std.mem.span(driver.?), "kmsdrm");

    var flags: c.SDL_WindowFlags = if (is_kmsdrm)
        c.SDL_WINDOW_FULLSCREEN
    else if (is_android)
        c.SDL_WINDOW_FULLSCREEN | c.SDL_WINDOW_RESIZABLE
    else if (wantSize() != null)
        0
    else
        c.SDL_WINDOW_RESIZABLE;

    if (!is_kmsdrm) flags |= c.SDL_WINDOW_OPENGL;

    const size = wantSize() orelse [2]u32{ ui.screen_width * 2, ui.screen_height * 2 };

    app.window = try errify(c.SDL_CreateWindow(options.name, @intCast(size[0]), @intCast(size[1]), flags));
    errdefer c.SDL_DestroyWindow(app.window);

    setWindowIcon(app.window) catch {
        sdl_log.warn("window icon unavailable: {s}", .{c.SDL_GetError()});
    };

    app.renderer = try .init(app.window);
    errdefer app.renderer.deinit();

    var touch_count: c_int = 0;
    c.SDL_free(c.SDL_GetTouchDevices(&touch_count));
    app.touch_ui = touch_count > 0;

    app.timekeeper = .{ .tocks_per_s = c.SDL_GetPerformanceFrequency() };
    if (builtin.optimize == .debug) app.fps = .init();

    try app.updateLayout();

    app.high_score.load();
    app.showTitle();
}

pub fn deinit(self: *App) void {
    if (self.gamepad) |pad| c.SDL_CloseGamepad(pad);
    self.renderer.deinit();
    c.SDL_DestroyWindow(self.window);
}

pub fn showTitle(app: *App) void {
    app.recordRun();
    app.game = .{ .players = .{ null, null } };
    app.game.init(c.SDL_GetPerformanceCounter());
    app.screen = .title;
}

fn menuId(menu: ?[]const ui.MenuItem) ?[*]const ui.MenuItem {
    return if (menu) |m| m.ptr else null;
}

fn syncFocus(self: *App) void {
    const menu = self.activeMenu();
    if (menuId(menu) != menuId(self.last_menu)) self.focus = 0;
    self.last_menu = menu;
}

pub fn restart(app: *App) void {
    app.recordRun();
    app.game = .{};
    app.game.init(c.SDL_GetPerformanceCounter());
    app.screen = .playing;
}

fn setWindowIcon(window: *c.SDL_Window) !void {
    const icon_png = @embedFile("icon.png");
    const stream: *c.SDL_IOStream = try errify(c.SDL_IOFromConstMem(icon_png, icon_png.len));
    const surface: *c.SDL_Surface = try errify(c.SDL_LoadPNG_IO(stream, true));
    defer c.SDL_DestroySurface(surface);
    try errify(c.SDL_SetWindowIcon(window, surface));
}

fn recordRun(self: *App) void {
    if (self.screen != .playing or self.game.players[1] != null) return;
    self.high_score.record(self.game.difficulty, self.game.floor());
}

fn updateLayout(self: *App) !void {
    const out_w, const out_h = try self.outputSize();
    var safe: c.SDL_FRect = .{ .x = 0, .y = 0, .w = out_w, .h = out_h };
    var rect: c.SDL_Rect = undefined;
    if (c.SDL_GetWindowSafeArea(self.window, &rect)) {
        const density = c.SDL_GetWindowPixelDensity(self.window);
        safe = .{
            .x = @as(f32, @floatFromInt(rect.x)) * density,
            .y = @as(f32, @floatFromInt(rect.y)) * density,
            .w = @as(f32, @floatFromInt(rect.w)) * density,
            .h = @as(f32, @floatFromInt(rect.h)) * density,
        };
    }
    self.layout = .init(out_w, out_h, safe);
}

fn outputSize(self: App) ![2]f32 {
    var w: c_int = 0;
    var h: c_int = 0;
    try errify(c.SDL_GetRenderOutputSize(self.renderer.sdl, &w, &h));
    return .{ @floatFromInt(w), @floatFromInt(h) };
}

fn windowToOutput(self: App, wx: f32, wy: f32) ![2]f32 {
    var x: f32 = 0;
    var y: f32 = 0;
    try errify(c.SDL_RenderCoordinatesFromWindow(self.renderer.sdl, wx, wy, &x, &y));
    return .{ x, y };
}

pub fn setCanvasSize(self: *App, w: c_int, h: c_int) void {
    _ = c.SDL_SetWindowSize(self.window, w, h);
}

pub fn handleEvent(self: *App, event: *c.SDL_Event) !c.SDL_AppResult {
    self.syncFocus();
    switch (event.type) {
        c.SDL_EVENT_QUIT => return c.SDL_APP_SUCCESS,
        c.SDL_EVENT_WILL_ENTER_BACKGROUND,
        c.SDL_EVENT_WINDOW_FOCUS_LOST,
        c.SDL_EVENT_WINDOW_HIDDEN,
        c.SDL_EVENT_WINDOW_MINIMIZED,
        => {
            if (self.screen == .playing) self.game.autoPause();
            self.touch = .{};
            self.applyTouch();
        },
        c.SDL_EVENT_GAMEPAD_ADDED => {
            if (self.gamepad == null) {
                self.gamepad = c.SDL_OpenGamepad(event.gdevice.which);
                if (self.gamepad) |pad| {
                    const name: [*c]const u8 = c.SDL_GetGamepadName(pad) orelse "(unnamed)";
                    sdl_log.info("gamepad: {s}", .{name});
                } else {
                    sdl_log.err("failed to open gamepad: {s}", .{c.SDL_GetError()});
                }
            }
        },
        c.SDL_EVENT_GAMEPAD_REMOVED => {
            if (self.gamepad) |pad| {
                if (c.SDL_GetGamepadID(pad) == event.gdevice.which) {
                    c.SDL_CloseGamepad(pad);
                    self.gamepad = null;
                }
            }
        },
        c.SDL_EVENT_KEY_DOWN, c.SDL_EVENT_KEY_UP => {
            if (event.key.repeat) return c.SDL_APP_CONTINUE;

            const down = event.type == c.SDL_EVENT_KEY_DOWN;
            switch (event.key.scancode) {
                c.SDL_SCANCODE_P => if (down and self.screen == .playing and !self.game.isOver()) self.game.pause(),
                c.SDL_SCANCODE_LEFT => if (self.game.players[0]) |*p| {
                    p.input.left = down;
                },
                c.SDL_SCANCODE_RIGHT => if (self.game.players[0]) |*p| {
                    p.input.right = down;
                },
                c.SDL_SCANCODE_ESCAPE, c.SDL_SCANCODE_AC_BACK => if (down) return self.back(),
                c.SDL_SCANCODE_UP => if (down) self.menuMove(true),
                c.SDL_SCANCODE_DOWN => if (down) self.menuMove(false),
                c.SDL_SCANCODE_RETURN, c.SDL_SCANCODE_KP_ENTER, c.SDL_SCANCODE_SPACE => if (down) return self.menuConfirm(),
                else => {},
            }
        },
        c.SDL_EVENT_FINGER_DOWN => {
            self.touch_ui = true;
            const out_w, const out_h = try self.outputSize();
            const x = event.tfinger.x * out_w;
            const y = event.tfinger.y * out_h;
            if (self.screen == .playing and !self.game.isOver() and self.layout.inHeader(x, y)) {
                self.tapHeader(x, y);
            } else if (self.activeMenu()) |menu| {
                if (self.hitMenu(x, y)) |i| return self.activate(menu[i]);
            } else {
                self.touch.down(event.tfinger.fingerID, x, y);
            }
        },
        c.SDL_EVENT_FINGER_MOTION => {
            const out_w, _ = try self.outputSize();
            self.touch.motion(event.tfinger.fingerID, event.tfinger.x * out_w, self.layout.scale);
            if (self.touch.active()) self.applyTouch();
        },
        c.SDL_EVENT_FINGER_UP, c.SDL_EVENT_FINGER_CANCELED => {
            if (self.touch.active()) {
                self.touch.up(event.tfinger.fingerID);
                if (!self.touch.active()) self.applyTouch();
            }
        },
        c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
            if (event.button.which == c.SDL_TOUCH_MOUSEID) return c.SDL_APP_CONTINUE;
            if (event.button.button != c.SDL_BUTTON_LEFT) return c.SDL_APP_CONTINUE;

            const menu = self.activeMenu() orelse return c.SDL_APP_CONTINUE;
            const x, const y = try self.windowToOutput(event.button.x, event.button.y);
            if (self.hitMenu(x, y)) |i| return self.activate(menu[i]);
        },
        c.SDL_EVENT_MOUSE_MOTION => {
            if (event.motion.which == c.SDL_TOUCH_MOUSEID) return c.SDL_APP_CONTINUE;
            const x, const y = try self.windowToOutput(event.motion.x, event.motion.y);
            if (self.hitMenu(x, y)) |i| self.focus = i;
        },
        c.SDL_EVENT_GAMEPAD_BUTTON_DOWN, c.SDL_EVENT_GAMEPAD_BUTTON_UP => {
            const down = event.type == c.SDL_EVENT_GAMEPAD_BUTTON_DOWN;

            switch (event.gbutton.button) {
                c.SDL_GAMEPAD_BUTTON_SOUTH => if (down) return self.menuConfirm(),
                c.SDL_GAMEPAD_BUTTON_EAST => if (down and self.game.paused) self.game.pause(),
                c.SDL_GAMEPAD_BUTTON_BACK => if (down) return self.back(),
                c.SDL_GAMEPAD_BUTTON_START => if (down) {
                    if (self.screen == .playing and !self.game.isOver()) self.game.pause() else return self.menuConfirm();
                },
                c.SDL_GAMEPAD_BUTTON_DPAD_UP => if (down) self.menuMove(true),
                c.SDL_GAMEPAD_BUTTON_DPAD_DOWN => if (down) self.menuMove(false),
                c.SDL_GAMEPAD_BUTTON_DPAD_LEFT => if (self.game.players[0]) |*p| {
                    p.input.left = down;
                },
                c.SDL_GAMEPAD_BUTTON_DPAD_RIGHT => if (self.game.players[0]) |*p| {
                    p.input.right = down;
                },
                else => {},
            }
        },
        c.SDL_EVENT_GAMEPAD_AXIS_MOTION => {
            if (event.gaxis.axis == c.SDL_GAMEPAD_AXIS_LEFTY) {
                self.stickMenu(event.gaxis.value);
                return c.SDL_APP_CONTINUE;
            }
            if (event.gaxis.axis != c.SDL_GAMEPAD_AXIS_LEFTX) return c.SDL_APP_CONTINUE;

            const v = event.gaxis.value;
            const dir: TouchStick.Dir = if (v < -stick_dead_zone) .left else if (v > stick_dead_zone) .right else .none;
            if (dir == self.stick) return c.SDL_APP_CONTINUE;
            self.stick = dir;

            if (self.game.players[0]) |*p| {
                p.input.left = dir == .left;
                p.input.right = dir == .right;
            }
        },
        else => {},
    }
    return c.SDL_APP_CONTINUE;
}

fn applyTouch(self: *App) void {
    if (self.game.players[0]) |*p| {
        p.input.left = self.touch.dir == .left;
        p.input.right = self.touch.dir == .right;
    }
}

fn tapHeader(self: *App, x: f32, y: f32) void {
    const gx, const gy = self.layout.toGame(x, y);
    if (ui.contains(ui.pause_button, gx, gy)) self.game.pause();
}

pub fn activeMenu(self: App) ?[]const ui.MenuItem {
    return switch (self.screen) {
        .title => ui.title_menu,
        .playing => if (self.game.isOver())
            ui.over_menu
        else if (self.game.paused)
            ui.pause_menu
        else
            null,
    };
}

fn view(self: *const App) Renderer.View {
    var new_view: Renderer.View = .{
        .game = &self.game,
        .screen = self.screen,
        .menu = self.activeMenu(),
        .focus = self.focus,
        .best = self.high_score.best.get(self.game.difficulty),
        .layout = self.layout,
        .touch = self.touch,
        .touch_ui = self.touch_ui,
    };
    if (builtin.optimize == .debug) new_view.fps = self.fps.?.fps;

    return new_view;
}

fn activate(self: *App, item: ui.MenuItem) c.SDL_AppResult {
    switch (item) {
        .new_game, .restart, .retry => self.restart(),
        .unpause => self.game.pause(),
        .main_menu => self.showTitle(),
        .quit => return c.SDL_APP_SUCCESS,
    }
    return c.SDL_APP_CONTINUE;
}

fn menuMove(self: *App, up: bool) void {
    const menu = self.activeMenu() orelse return;
    self.focus = ui.moveFocus(self.focus, menu.len, up);
}

fn stickMenu(self: *App, v: i16) void {
    const dir: StickY = if (v < -menu_push)
        .up
    else if (v > menu_push)
        .down
    else if (@abs(v) < stick_dead_zone)
        .none
    else
        return;

    if (dir == self.stick_y) return;
    self.stick_y = dir;
    if (dir != .none) self.menuMove(dir == .up);
}

fn menuConfirm(self: *App) c.SDL_AppResult {
    const menu = self.activeMenu() orelse return c.SDL_APP_CONTINUE;
    return self.activate(menu[self.focus]);
}

fn back(self: *App) c.SDL_AppResult {
    switch (self.screen) {
        .title => if (builtin.os.tag != .emscripten) return c.SDL_APP_SUCCESS,
        .playing => if (!self.game.isOver()) self.game.pause(),
    }
    return c.SDL_APP_CONTINUE;
}

fn hitMenu(self: App, x: f32, y: f32) ?usize {
    const menu = self.activeMenu() orelse return null;
    const gx, const gy = self.layout.toGame(x, y);
    for (0..menu.len) |i| {
        if (ui.contains(ui.menuButton(i), gx, gy)) return i;
    }
    return null;
}

pub fn iterate(self: *App) !c.SDL_AppResult {
    if (builtin.optimize == .debug) self.fps.?.tick();

    while (self.timekeeper.consume()) {
        self.game.tick();
    }

    if (self.game.isOver()) self.recordRun();

    try self.updateLayout();
    self.syncFocus();
    try self.renderer.draw(self.view());

    self.timekeeper.produce(c.SDL_GetPerformanceCounter());

    return c.SDL_APP_CONTINUE;
}

fn wantSize() ?[2]u32 {
    const set = c.SDL_getenv("FALLING_SIZE") orelse return null;
    const text = std.mem.span(set);
    const x = std.mem.indexOfScalar(u8, text, 'x') orelse return null;
    return .{
        std.fmt.parseInt(u32, text[0..x], 10) catch return null,
        std.fmt.parseInt(u32, text[x + 1 ..], 10) catch return null,
    };
}

const Fps = struct {
    fps_accum: u64,
    frames: u32,
    fps: f64,
    last_ns: u64,
    frame_peak_ms: f64,
    peak_ns: u64,

    fn tick(self: *Fps) void {
        const now = c.SDL_GetTicksNS();
        const elapsed = now - self.last_ns;
        self.last_ns = now;

        self.fps_accum += elapsed;
        self.frames += 1;
        self.peak_ns = @max(self.peak_ns, elapsed);

        if (self.fps_accum >= 250_000_000) {
            const seconds: f64 = @as(f64, @floatFromInt(self.fps_accum)) / 1e9;
            self.fps = @as(f64, @floatFromInt(self.frames)) / seconds;
            self.frame_peak_ms = @as(f64, @floatFromInt(self.peak_ns)) / 1e6;

            self.fps_accum = 0;
            self.frames = 0;
            self.peak_ns = 0;
        }
    }

    pub fn init() Fps {
        return .{
            .fps_accum = 0,
            .frames = 0,
            .fps = 0.0,
            .last_ns = c.SDL_GetTicksNS(),
            .frame_peak_ms = 0,
            .peak_ns = 0,
        };
    }
};

fn fmtSdlDrivers(
    current_driver: [*:0]const u8,
    num_drivers: c_int,
    getDriver: *const fn (c_int) callconv(.c) ?[*:0]const u8,
) FormatSdlDrivers {
    return .{
        .current_driver = current_driver,
        .num_drivers = num_drivers,
        .getDriver = getDriver,
    };
}

const FormatSdlDrivers = struct {
    current_driver: [*:0]const u8,
    num_drivers: c_int,
    getDriver: *const fn (c_int) callconv(.c) ?[*:0]const u8,

    pub fn format(context: FormatSdlDrivers, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        var i: c_int = 0;
        while (i < context.num_drivers) : (i += 1) {
            if (i != 0) {
                try writer.writeAll(", ");
            }
            const driver = context.getDriver(i).?;
            try writer.writeAll(std.mem.span(driver));
            if (std.mem.orderZ(u8, context.current_driver, driver) == .eq) {
                try writer.writeAll(" (current)");
            }
        }
    }
};

test {
    _ = Renderer;
}

const App = @This();

const stick_dead_zone = 8000;
const menu_push = 16000;
const StickY = enum { none, up, down };

const Timekeeper = @import("Timekeeper.zig");
const TouchStick = @import("TouchStick.zig");
const HighScore = @import("HighScore.zig");

const sdl = @import("sdl.zig");
const c = sdl.c;
const errify = sdl.errify;
const options = @import("options");

const Game = @import("falling").Game;

const Renderer = @import("Renderer.zig");

const ui = @import("ui.zig");

const std = @import("std");
const sdl_log = std.log.scoped(.sdl);

const builtin = @import("builtin");
const is_android = builtin.abi.isAndroid();
