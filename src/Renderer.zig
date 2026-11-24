//! Owns SDL renderer and textures and draws from read-only View
pub const render_scale = 4;

sdl: *c.SDL_Renderer,
spritesheet: *c.SDL_Texture,
target: *c.SDL_Texture,

pub const View = struct {
    game: *const Game,
    screen: ui.Screen,
    menu: ?[]const ui.MenuItem,
    focus: usize,
    best: u32,
    layout: ui.Layout,
    touch: TouchStick,
    touch_ui: bool,
    fps: ?f64 = null,
};

pub fn init(window: *c.SDL_Window) !Renderer {
    try errify(c.SDL_SetHint(c.SDL_HINT_RENDER_VSYNC, "1"));
    const sdl = try errify(c.SDL_CreateRenderer(window, null));
    errdefer c.SDL_DestroyRenderer(sdl);

    const sprites_png = @embedFile("spritesheet.png");
    const stream: *c.SDL_IOStream = try errify(c.SDL_IOFromConstMem(sprites_png, sprites_png.len));
    const surface: *c.SDL_Surface = try errify(c.SDL_LoadPNG_IO(stream, true));
    defer c.SDL_DestroySurface(surface);

    const spritesheet = try errify(c.SDL_CreateTextureFromSurface(sdl, surface));
    errdefer c.SDL_DestroyTexture(spritesheet);
    try errify(c.SDL_SetTextureScaleMode(spritesheet, c.SDL_SCALEMODE_NEAREST));

    const target = try errify(c.SDL_CreateTexture(
        sdl,
        c.SDL_PIXELFORMAT_RGBA8888,
        c.SDL_TEXTUREACCESS_TARGET,
        ui.screen_width * render_scale,
        ui.screen_height * render_scale,
    ));
    errdefer c.SDL_DestroyTexture(target);
    try errify(c.SDL_SetTextureScaleMode(target, c.SDL_SCALEMODE_PIXELART));

    return .{ .sdl = sdl, .spritesheet = spritesheet, .target = target };
}

pub fn deinit(self: Renderer) void {
    c.SDL_DestroyTexture(self.target);
    c.SDL_DestroyTexture(self.spritesheet);
    c.SDL_DestroyRenderer(self.sdl);
}

fn snap(v: f32) f32 {
    return @round(v * render_scale) / render_scale;
}

fn toScreen(cam: f32, x: f32, y: f32) [2]f32 {
    return .{ ui.shaft_x + x, ui.header + y - cam };
}

pub const Frame = struct {
    rect: c.SDL_FRect,
    offset: f32,
    flip_x: bool,

    pub fn init(x: f32, y: f32, w: f32, h: f32) Frame {
        return .{
            .rect = .{ .x = x, .y = y, .w = w, .h = h },
            .offset = 0,
            .flip_x = false,
        };
    }

    pub fn initOffset(x: f32, y: f32, w: f32, h: f32, offset: f32) Frame {
        return .{
            .rect = .{ .x = x, .y = y, .w = w, .h = h },
            .offset = offset,
            .flip_x = false,
        };
    }

    pub fn initFlipped(x: f32, y: f32, w: f32, h: f32) Frame {
        return .{
            .rect = .{ .x = x, .y = y, .w = w, .h = h },
            .offset = 0,
            .flip_x = true,
        };
    }
};

pub const Animation = struct {
    frames: []const Frame,
    delay: u32 = 4,
    mode: Mode = .loop,

    pub const Mode = enum { loop, once };

    pub fn init(frames: []const Frame) Animation {
        return .{ .frames = frames };
    }

    pub fn duration(self: Animation) u32 {
        return @as(u32, @intCast(self.frames.len)) * self.delay;
    }

    pub fn frameAt(self: Animation, t: u32) Frame {
        const i: usize = t / self.delay;
        return self.frames[
            switch (self.mode) {
                .loop => i % self.frames.len,
                .once => @min(i, self.frames.len - 1),
            }
        ];
    }
};

pub fn draw(self: Renderer, view: View) !void {
    try errify(c.SDL_SetRenderTarget(self.sdl, self.target));
    try errify(c.SDL_SetRenderScale(self.sdl, render_scale, render_scale));
    try errify(c.SDL_SetRenderDrawColor(self.sdl, 55, 42, 57, 0xff));
    try errify(c.SDL_RenderClear(self.sdl));

    try self.renderBackground(view);

    try self.renderSprites(view);

    // header
    try self.renderHeader(view);

    // ceiling spikes
    try errify(c.SDL_RenderTextureTiled(
        self.sdl,
        self.spritesheet,
        &sprites.spike.rect,
        1,
        &.{ .x = ui.shaft_x, .y = ui.header, .w = ui.shaft_width, .h = sprites.spike.rect.h },
    ));

    try errify(c.SDL_SetRenderDrawColor(self.sdl, 245, 233, 191, 0xff));

    if (view.game.paused) {
        const paused_sprite = sprites.paused.rect;
        try errify(c.SDL_RenderTexture(
            self.sdl,
            self.spritesheet,
            &paused_sprite,
            &.{ .x = tile_size * 9 - (tile_size / 2), .y = tile_size * 10, .w = paused_sprite.w, .h = paused_sprite.h },
        ));
    }

    if (view.game.isOver()) {
        try errify(c.SDL_RenderDebugText(self.sdl, (ui.screen_width - 9 * 8) / 2, ui.header + tile_size * 10, "game over"));
    }

    if (view.screen == .title) {
        const title = "falling";
        try errify(c.SDL_RenderDebugText(self.sdl, (ui.screen_width - title.len * 8) / 2, ui.header + tile_size * 8, title));
    }
    if (view.menu) |menu| try self.renderMenu(view, menu);

    if (builtin.optimize == .debug) {
        try self.renderDebug(view);
    }

    try errify(c.SDL_SetRenderTarget(self.sdl, null));
    try errify(c.SDL_SetRenderDrawColor(self.sdl, 0, 0, 0, 0xff));
    try errify(c.SDL_RenderClear(self.sdl));
    try errify(c.SDL_RenderTexture(self.sdl, self.target, null, &view.layout.game));
    try self.renderTouch(view);

    try errify(c.SDL_RenderPresent(self.sdl));
}

fn renderBackground(self: Renderer, view: View) !void {
    const cam = snap(view.game.depth);
    const background_pos = -@mod(cam * 0.5, sprites.background.rect.h);
    const wall_pos = -@mod(cam, sprites.wall.rect.h);

    try renderTextureTiledRotated(
        self.sdl,
        self.spritesheet,
        &sprites.background.rect,
        &.{ .x = 0, .y = snap(background_pos + ui.header), .w = sprites.background.rect.w * 4, .h = sprites.background.rect.h * 3 },
        c.SDL_FLIP_NONE,
    );

    const wall_sprite = sprites.wall.rect;
    try renderTextureTiledRotated(
        self.sdl,
        self.spritesheet,
        &wall_sprite,
        &.{ .x = 0, .y = snap(wall_pos + ui.header), .w = wall_sprite.w, .h = ui.shaft_height + wall_sprite.h },
        c.SDL_FLIP_NONE,
    );

    try renderTextureTiledRotated(
        self.sdl,
        self.spritesheet,
        &wall_sprite,
        &.{ .x = ui.shaft_x + ui.shaft_width, .y = snap(wall_pos + ui.header), .w = wall_sprite.w, .h = ui.shaft_height + wall_sprite.h },
        c.SDL_FLIP_HORIZONTAL,
    );
}

fn renderHeader(self: Renderer, view: View) !void {
    try self.renderPanel(.{ .x = 0, .y = 0, .w = tile_size * 9, .h = ui.header });

    try errify(c.SDL_RenderFillRect(self.sdl, &.{
        .x = tile_size * 9,
        .y = 0,
        .w = tile_size * 8,
        .h = ui.header,
    }));

    const right_w: f32 = if (view.touch_ui) ui.pause_button.x - tile_size * 17 else tile_size * 9;
    try self.renderPanel(.{ .x = tile_size * 17, .y = 0, .w = right_w, .h = ui.header });

    if (view.touch_ui) {
        try errify(c.SDL_RenderTexture(self.sdl, self.spritesheet, &sprites.pause_icon.rect, &ui.pause_button));
    }

    // health bars
    const bar_x = [_]f32{ tile_size * 1.5, tile_size * 18.5 };
    const bar_w = [_]f32{ tile_size * 6, if (view.touch_ui) tile_size * 4 else tile_size * 6 };
    for (view.game.players, bar_x, bar_w) |slot, x, w| {
        if (slot) |p| try self.renderHealthBar(x, w, p.health);
    }

    const playing = view.screen == .playing;

    if (view.game.players[1] == null) {
        const saved = view.best;
        const best = if (playing) @max(saved, view.game.floor()) else saved;
        try self.renderNumber(bar_x[1] + bar_w[1], tile_size / 2, best);
    }
    if (playing) try self.renderFloor(view);
}

fn renderMenu(self: Renderer, view: View, items: []const ui.MenuItem) !void {
    try errify(c.SDL_SetRenderDrawColor(self.sdl, 245, 233, 191, 0xff));
    for (items, 0..) |item, i| {
        const r = ui.menuButton(i);
        try self.renderPanel(r);
        if (i == view.focus) try errify(c.SDL_RenderRect(self.sdl, &r));

        const text = item.label();
        const text_w: f32 = @floatFromInt(text.len * 8);
        try errify(c.SDL_RenderDebugText(self.sdl, r.x + (r.w - text_w) / 2, r.y + (r.h - 8) / 2, text.ptr));
    }
}

fn renderPanel(self: Renderer, dst: c.SDL_FRect) !void {
    try errify(c.SDL_RenderTexture9Grid(
        self.sdl,
        self.spritesheet,
        &sprites.panel_grid.rect,
        tile_size,
        tile_size,
        tile_size,
        tile_size,
        1,
        &dst,
    ));
}

fn renderHealthBar(self: Renderer, x: f32, bar_w: f32, health: u8) !void {
    const fill = bar_w * @as(f32, @floatFromInt(health)) / Player.max_health;
    const y = tile_size / 2;
    try errify(c.SDL_RenderTextureTiled(self.sdl, self.spritesheet, &sprites.empty_health_bar.rect, 1, &.{ .x = x, .y = y, .w = bar_w, .h = tile_size }));
    try errify(c.SDL_RenderTextureTiled(self.sdl, self.spritesheet, &sprites.health_bar.rect, 1, &.{ .x = x, .y = y, .w = fill, .h = tile_size }));
}

const digit_h = sprites.digits.rect.h;

fn digitSourceY(from: u32, to: u32, t: f32) f32 {
    const base = @as(f32, @floatFromInt((from + 1) % 10)) * digit_h;
    return if (from == to) base else base + snap(t * digit_h);
}

const roll_depth = Game.refPx(36);
const digit_gap = 2;
const floor_digits = 4;

fn renderFloor(self: Renderer, view: View) !void {
    const game = view.game;
    const floor = game.floor();
    const t = @min(1, @mod(game.depth, Game.floor_height) / roll_depth);
    var from = if (floor > 1 and t < 1) floor - 1 else floor;
    var to = floor;

    const digit_w = sprites.digits.rect.w;
    const advance = digit_w + digit_gap;
    const total_w = floor_digits * advance - digit_gap;
    const right = tile_size * 13 + total_w / 2;
    for (0..floor_digits) |i| {
        var src = sprites.digits.rect;
        src.y += digitSourceY(from % 10, to % 10, t);
        const x = right - @as(f32, @floatFromInt(i)) * advance - digit_w;
        try errify(c.SDL_RenderTexture(self.sdl, self.spritesheet, &src, &.{ .x = x, .y = 0, .w = digit_w, .h = digit_h }));
        from /= 10;
        to /= 10;
    }
}

fn renderNumber(self: Renderer, right: f32, y: f32, value: u32) !void {
    const glyph = sprites.font_digits.rect;
    var n = value;
    var x = right;
    while (true) {
        var src = glyph;
        src.x += @as(f32, @floatFromInt(n % 10)) * glyph.w;
        x -= glyph.w;
        try errify(c.SDL_RenderTexture(self.sdl, self.spritesheet, &src, &.{ .x = x, .y = y, .w = glyph.w, .h = glyph.h }));
        n /= 10;
        if (n == 0) break;
    }
}

fn platformFrame(platform: Platform, now: u32) Frame {
    const frames = sprites.platforms;
    return switch (platform.type) {
        .normal => frames.normal[0],
        .spikes => frames.spikes[0],
        .left_treadmill => Animation.init(&frames.left_treadmill).frameAt(now),
        .right_treadmill => Animation.init(&frames.right_treadmill).frameAt(now),
        .trapdoor => blk: {
            const e = platform.elapsed(now) orelse break :blk frames.trapdoor[0];
            if (e < Platform.trapdoor_open or e >= Platform.trapdoor_cycle) break :blk frames.trapdoor[0];
            const open: Animation = .{ .frames = &frames.trapdoor, .mode = .once, .delay = 8 };
            break :blk open.frameAt(e - Platform.trapdoor_open);
        },
        .trampoline => blk: {
            const bounce: Animation = .{ .frames = &frames.trampoline, .mode = .once };
            const e = platform.elapsed(now) orelse break :blk bounce.frames[0];
            if (e >= bounce.duration()) break :blk bounce.frames[0];
            break :blk bounce.frameAt(e);
        },
    };
}

fn playerFrame(p: Player) Frame {
    const anim: Animation = .init(switch (p.state) {
        .running_left => &sprites.left,
        .running_right => &sprites.right,
        else => &sprites.idle,
    });
    return anim.frameAt(p.state_ticks);
}

fn renderSprites(self: Renderer, view: View) !void {
    const game = view.game;
    const cam = snap(game.depth);
    for (game.platforms.items) |platform| {
        const x, const y = toScreen(cam, platform.x, platform.top(game.ticks));
        try self.renderFrame(x, y, platformFrame(platform, game.ticks));
    }
    for (game.players) |player| {
        if (player) |p| {
            if (!p.isAlive()) continue;
            if (p.pain > 0 and (p.pain / Game.refTicks(1)) % 2 == 1) continue;
            const x, const y = toScreen(cam, p.x, p.y);
            try self.renderFrame(x, y, playerFrame(p));
        }
    }
}

fn renderFrame(self: Renderer, x: f32, y: f32, frame: Frame) !void {
    const rect = frame.rect;
    const flags = if (frame.flip_x) c.SDL_FLIP_HORIZONTAL else c.SDL_FLIP_NONE;
    try errify(c.SDL_RenderTextureRotated(
        self.sdl,
        self.spritesheet,
        &.{ .x = snap(rect.x), .y = snap(rect.y), .w = rect.w, .h = rect.h },
        &.{ .x = snap(x), .y = snap(y + frame.offset), .w = rect.w, .h = rect.h },
        0,
        null,
        @intCast(flags),
    ));
}

fn renderTouch(self: Renderer, view: View) !void {
    const layout = view.layout;
    if (layout.pad) |pad| {
        try errify(c.SDL_SetRenderDrawColor(self.sdl, 55, 42, 57, 0xff));
        try errify(c.SDL_RenderFillRect(self.sdl, &pad));
    }

    const stick = view.touch;
    if (!stick.active()) return;

    const circle = sprites.touch_circle.rect;
    try errify(c.SDL_RenderTexture(
        self.sdl,
        self.spritesheet,
        &circle,
        &centered(stick.origin_x, stick.origin_y, circle.w * layout.scale),
    ));

    if (stick.dir == .none) return;
    const arrow = sprites.touch_arrow.rect;
    const flip = if (stick.dir == .right) c.SDL_FLIP_HORIZONTAL else c.SDL_FLIP_NONE;
    try errify(c.SDL_RenderTextureRotated(
        self.sdl,
        self.spritesheet,
        &arrow,
        &centered(stick.origin_x, stick.origin_y, arrow.w * layout.scale),
        0,
        null,
        @intCast(flip),
    ));
}

fn centered(x: f32, y: f32, size: f32) c.SDL_FRect {
    return .{ .x = x - size / 2, .y = y - size / 2, .w = size, .h = size };
}

fn renderDebug(self: Renderer, view: View) !void {
    var buf: [32]u8 = undefined;
    const text = try std.fmt.bufPrintSentinel(&buf, "{d: >5.1}", .{view.fps.?}, 0);
    try errify(c.SDL_RenderDebugText(self.sdl, 10, 24, text.ptr));
}

fn renderTextureTiledRotated(
    renderer: ?*c.SDL_Renderer,
    texture: [*c]c.SDL_Texture,
    src: *const c.SDL_FRect,
    dst: *const c.SDL_FRect,
    flip: c.SDL_FlipMode,
) !void {
    const tile_w = src.w;
    const tile_h = src.h;
    const tiles_x = @as(usize, @intFromFloat(dst.w / tile_w));
    const tiles_y = @as(usize, @intFromFloat(dst.h / tile_h));

    for (0..tiles_y + 1) |y| {
        for (0..tiles_x) |x| {
            var tile_dst: c.SDL_FRect = .{
                .x = dst.x + @as(f32, @floatFromInt(x)) * tile_w,
                .y = dst.y + @as(f32, @floatFromInt(y)) * tile_h,
                .w = tile_w,
                .h = tile_h,
            };
            try errify(c.SDL_RenderTextureRotated(
                renderer,
                texture,
                src,
                &tile_dst,
                0,
                null,
                flip,
            ));
        }
    }
}

const sprites = struct {
    const background: Frame = .init(0, tile_size * 20, tile_size * 8, tile_size * 8);
    const wall: Frame = .init(0, 0, tile_size, tile_size * 2);
    const panel_grid: Frame = .init(tile_size * 12, tile_size * 15, tile_size * 2, tile_size * 2);
    const spike: Frame = .init(tile_size, tile_size, tile_size, tile_size);
    const paused: Frame = .init(tile_size * 6, tile_size * 17, tile_size * 9, tile_size * 3);
    const empty_health_bar: Frame = .init(tile_size * 14, tile_size * 16, tile_size / 2, tile_size);
    const health_bar: Frame = .init(tile_size * 14 + (tile_size / 2), tile_size * 16, tile_size / 2, tile_size);
    const digits: Frame = .init(tile_size * 18, 0, tile_size, tile_size * 2);
    const font_digits: Frame = .init(0, tile_size * 28, tile_size, tile_size);
    const touch_circle: Frame = .init(0, tile_size * 16, tile_size * 4, tile_size * 4);
    const touch_arrow: Frame = .init(tile_size * 4, tile_size * 18, tile_size * 2, tile_size * 2);
    const pause_icon: Frame = .init(tile_size * 4, tile_size * 16, tile_size * 2, tile_size * 2); // placeholder

    // Platforms
    const platform_width = Platform.width;
    const platforms = struct {
        pub const normal = [_]Frame{
            .init(0, tile_size * 15, platform_width, tile_size),
        };
        pub const spikes = [_]Frame{
            .initOffset(tile_size * 6, tile_size * 15, platform_width, tile_size * 2, -tile_size),
        };
        pub const trapdoor = [_]Frame{
            .init(0, tile_size * 9, platform_width, tile_size * 2),
            .init(0, tile_size * 11, platform_width, tile_size * 2),
            .init(0, tile_size * 13, platform_width, tile_size * 2),
            .init(tile_size * 6, tile_size * 5, platform_width, tile_size * 2),
        };
        pub const right_treadmill = [_]Frame{
            .init(0, tile_size * 5, platform_width, tile_size * 2),
        };
        pub const left_treadmill = [_]Frame{
            .init(0, tile_size * 7, platform_width, tile_size * 2),
        };
        pub const trampoline = [_]Frame{
            .init(tile_size * 6, tile_size * 9, platform_width, tile_size * 2),
        };
        const pause_icon: Frame = .init(tile_size * 4, tile_size * 16, tile_size * 2, tile_size * 2);
    };

    // Player
    const player_size = Player.size;
    pub const idle = [_]Frame{
        .init(tile_size * 4, 0, player_size, player_size),
        .init(tile_size * 4, 0, player_size, player_size),
        .init(tile_size * 4, 0, player_size, player_size),
        .init(tile_size * 4, 0, player_size, player_size),
    };
    pub const left = [_]Frame{
        .init(0, tile_size * 2, player_size, player_size),
        .init(tile_size * 2, tile_size * 2, player_size, player_size),
        .init(tile_size * 4, tile_size * 2, player_size, player_size),
        .init(tile_size * 2, tile_size * 2, player_size, player_size),
    };
    pub const right = [_]Frame{
        .initFlipped(0, tile_size * 2, player_size, player_size),
        .initFlipped(tile_size * 2, tile_size * 2, player_size, player_size),
        .initFlipped(tile_size * 4, tile_size * 2, player_size, player_size),
        .initFlipped(tile_size * 2, tile_size * 2, player_size, player_size),
    };
};

test "digit roll uses the leading 9 to wrap into 0" {
    try std.testing.expectEqual(0 * digit_h, digitSourceY(9, 9, 0)); // resting 9 = top copy
    try std.testing.expectEqual(1 * digit_h, digitSourceY(9, 0, 1)); // 9 -> 0 ends on 0
    try std.testing.expectEqual(10 * digit_h, digitSourceY(8, 9, 1)); // 8 -> 9 ends on bottom 9
    try std.testing.expectEqual(4 * digit_h, digitSourceY(3, 3, 0.5)); // unchanged digits don't move
}

const Renderer = @This();

const ui = @import("ui.zig");
const tile_size = ui.tile_size;

const c = @import("sdl.zig").c;
const errify = @import("sdl.zig").errify;

const TouchStick = @import("TouchStick.zig");

const falling = @import("falling");
const Game = falling.Game;
const Player = falling.Player;
const Platform = falling.Platform;

const std = @import("std");
const expectEqual = std.testing.expectEqual;
const expect = std.testing.expect;

const builtin = @import("builtin");
