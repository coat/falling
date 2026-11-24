//! Screen geometry, menus and hit-testing shared by App and Renderer

/// Spritesheet and screen grid unit. Happens to match Game.cell now, but
/// they're independent.
pub const tile_size = 8;
pub const header = tile_size * 2;
pub const shaft_width = Game.width;
pub const shaft_height = Game.height;

/// The wall art is one tile wide on each side. The shaft (world x = 0) starts
/// just right of the left wall.
const wall_width = tile_size;
pub const shaft_x = wall_width;

pub const screen_width = wall_width + shaft_width + wall_width;
pub const screen_height = header + shaft_height;

pub const pause_button: c.SDL_FRect = .{ .x = tile_size * 24, .y = 0, .w = tile_size * 2, .h = header };

pub fn contains(r: c.SDL_FRect, x: f32, y: f32) bool {
    return x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h;
}

pub const Screen = enum { title, playing };

pub const MenuItem = enum {
    new_game,
    unpause,
    restart,
    retry,
    main_menu,
    quit,

    pub fn label(self: MenuItem) [:0]const u8 {
        return switch (self) {
            .new_game => "new game",
            .unpause => "resume",
            .restart => "restart",
            .retry => "retry",
            .main_menu => "main menu",
            .quit => "quit",
        };
    }
};

pub const title_menu: []const MenuItem = if (builtin.os.tag == .emscripten)
    &.{.new_game}
else
    &.{ .new_game, .quit };

pub const pause_menu: []const MenuItem = &.{ .unpause, .restart, .main_menu };
pub const over_menu: []const MenuItem = &.{ .retry, .main_menu };

const menu_w = tile_size * 12;
const menu_h = tile_size * 2;
const menu_gap = 4;
const menu_y = tile_size * 14;

pub fn menuButton(i: usize) c.SDL_FRect {
    return .{
        .x = (screen_width - menu_w) / 2,
        .y = menu_y + @as(f32, @floatFromInt(i)) * (menu_h + menu_gap),
        .w = menu_w,
        .h = menu_h,
    };
}

pub fn moveFocus(focus: usize, len: usize, up: bool) usize {
    return if (up) (focus + len - 1) % len else (focus + 1) % len;
}

test "menu focus wraps around both ends" {
    try expectEqual(2, moveFocus(0, 3, true));
    try expectEqual(0, moveFocus(2, 3, false));
    try expectEqual(1, moveFocus(0, 3, false));
    try expectEqual(0, moveFocus(0, 1, true)); // single-item menu (web title)
}

pub const Layout = struct {
    scale: f32,
    game: c.SDL_FRect,
    pad: ?c.SDL_FRect,

    pub fn init(out_w: f32, out_h: f32, safe: c.SDL_FRect) Layout {
        const fit_w = out_w / screen_width;
        const game_h = screen_height * fit_w;

        if (game_h > safe.h) {
            const scale = out_h / screen_height;
            const w = screen_width * scale;
            return .{
                .scale = scale,
                .game = .{ .x = (out_w - w) / 2, .y = 0, .w = w, .h = out_h },
                .pad = null,
            };
        }

        const pad_y = safe.y + game_h;
        return .{
            .scale = fit_w,
            .game = .{ .x = 0, .y = safe.y, .w = out_w, .h = game_h },
            .pad = if (safe.y + safe.h - pad_y >= tile_size * 4 * fit_w)
                .{ .x = 0, .y = pad_y, .w = out_w, .h = out_h - pad_y }
            else
                null,
        };
    }

    pub fn headerRect(self: Layout) c.SDL_FRect {
        return .{ .x = self.game.x, .y = self.game.y, .w = self.game.w, .h = header * self.scale };
    }

    pub fn inHeader(self: Layout, x: f32, y: f32) bool {
        return contains(self.headerRect(), x, y);
    }

    pub fn toGame(self: Layout, x: f32, y: f32) [2]f32 {
        return .{ (x - self.game.x) / self.scale, (y - self.game.y) / self.scale };
    }
};

test "portrait puts the game on top with a pad below" {
    const l: Layout = .init(screen_width * 2, 800, .{ .x = 0, .y = 0, .w = screen_width * 2, .h = 800 });
    try std.testing.expectEqual(2, l.scale);
    try std.testing.expectEqual(screen_height * 2, l.game.h);
    try std.testing.expectEqual(screen_height * 2, l.pad.?.y);
    try std.testing.expectEqual(800 - screen_height * 2, l.pad.?.h);
}

test "landscape letterboxes the game with no pad" {
    const l: Layout = .init(800, screen_height * 2, .{ .x = 0, .y = 0, .w = 800, .h = screen_height * 2 });
    try std.testing.expectEqual(2, l.scale);
    try std.testing.expectEqual((800 - screen_width * 2) / 2, l.game.x);
    try std.testing.expectEqual(null, l.pad);
}

test "a thin leftover strip is not a pad" {
    const l: Layout = .init(screen_width * 2, screen_height * 2, .{ .x = 0, .y = 0, .w = screen_width * 2, .h = screen_height * 2 });
    try std.testing.expectEqual(null, l.pad);
}

test "portrait: full width, header below the notch" {
    const w = screen_width * 2;
    const l: Layout = .init(w, 900, .{ .x = 20, .y = 40, .w = w - 40, .h = 820 });
    try expectEqual(0, l.pad.?.x);
    try expectEqual(w, l.pad.?.w);
    try expectEqual(40 + screen_height * 2, l.pad.?.y);
    try expectEqual(900 - (40 + screen_height * 2), l.pad.?.h);
}

test "landscape: a top gesture inset doesn't push the game down" {
    const h = screen_height * 2;
    const l: Layout = .init(800, h, .{ .x = 0, .y = 30, .w = 800, .h = h - 30 });
    try expectEqual(0, l.game.y);
    try expectEqual(h, l.game.h);
    try expectEqual(null, l.pad);
}

test "header hit test covers the header only, not the side bars" {
    const h = screen_height * 2;
    const l: Layout = .init(800, h, .{ .x = 0, .y = 0, .w = 800, .h = h });
    try expect(l.inHeader(400, 10));
    try expect(!l.inHeader(10, 10)); // left letterbox bar, same height as header
    try expect(!l.inHeader(400, header * 2 + 1)); // just below the header
}

test "toGame undoes the layout's offset and scale" {
    const h = screen_height * 2;
    const l: Layout = .init(800, h, .{ .x = 0, .y = 0, .w = 800, .h = h });
    const gx, const gy = l.toGame(l.game.x + 20, 30);
    try expectEqual(10, gx);
    try expectEqual(15, gy);
}

test "a tap on the pause button's on-screen centre reaches it" {
    const l: Layout = .init(screen_width * 3, 1000, .{ .x = 0, .y = 50, .w = screen_width * 3, .h = 950 });
    const sx = l.game.x + (pause_button.x + pause_button.w / 2) * l.scale;
    const sy = l.game.y + (pause_button.y + pause_button.h / 2) * l.scale;
    try expect(l.inHeader(sx, sy));
    const gx, const gy = l.toGame(sx, sy);
    try expect(contains(pause_button, gx, gy));
}

test "menu buttons sit in the shaft, below PAUSED, without overlapping" {
    for ([_][]const MenuItem{ title_menu, pause_menu, over_menu }) |menu| {
        for (0..menu.len) |i| {
            const r = menuButton(i);
            try expect(r.y >= tile_size * 13);
            try expect(r.y + r.h <= screen_height);
            if (i > 0) {
                const prev = menuButton(i - 1);
                try expect(r.y >= prev.y + prev.h);
            }
        }
    }
}

test "menu labels fit inside the button border" {
    for (std.enums.values(MenuItem)) |item| {
        try expect(item.label().len * 8 <= menu_w - 2 * tile_size);
    }
}

const Game = @import("falling").Game;

const c = @import("sdl.zig").c;

const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const builtin = @import("builtin");
