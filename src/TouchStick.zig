finger: ?c.SDL_FingerID = null,
origin_x: f32 = 0,
origin_y: f32 = 0,
dir: Dir = .none,

pub const Dir = enum { none, left, right };

// in unscaled screen pixels
pub const dead_zone = 12;
pub const radius = 16;

pub fn active(self: TouchStick) bool {
    return self.finger != null;
}

pub fn down(self: *TouchStick, id: c.SDL_FingerID, x: f32, y: f32) void {
    if (self.active()) return;
    self.* = .{ .finger = id, .origin_x = x, .origin_y = y };
}

pub fn motion(self: *TouchStick, id: c.SDL_FingerID, x: f32, scale: f32) void {
    const owner = self.finger orelse return;
    if (owner != id) return;

    const dx = x - self.origin_x;
    const dead = dead_zone * scale;
    self.dir = if (dx < -dead) .left else if (dx > dead) .right else .none;

    const r = radius * scale;
    if (dx > r) self.origin_x = x - r else if (dx < -r) self.origin_x = x + r;
}

pub fn up(self: *TouchStick, id: c.SDL_FingerID) void {
    const owner = self.finger orelse return;
    if (owner == id) self.* = .{};
}
test "dead zone, then direction" {
    var s: TouchStick = .{};
    s.down(1, 100, 100);
    s.motion(1, 110, 1);
    try expectEqual(.none, s.dir);
    s.motion(1, 113, 1);
    try expectEqual(.right, s.dir);
    s.motion(1, 87, 1);
    try expectEqual(.left, s.dir);
}

test "dead zone scales with the layout" {
    var s: TouchStick = .{};
    s.down(1, 100, 100);
    s.motion(1, 140, 4); // 40 px < 12 * 4
    try expectEqual(.none, s.dir);
}

test "origin drags along so reversing is a short swipe" {
    var s: TouchStick = .{};
    s.down(1, 100, 100);
    s.motion(1, 200, 1);
    try expectEqual(200 - radius, s.origin_x);
    s.motion(1, 170, 1); // only 30 px back, but past the dragged origin
    try expectEqual(.left, s.dir);
}

test "a second finger doesn't steal or release the stick" {
    var s: TouchStick = .{};
    s.down(1, 100, 100);
    s.down(2, 300, 300);
    try expectEqual(100, s.origin_x);

    s.motion(2, 500, 1);
    try expectEqual(.none, s.dir);

    s.up(2);
    try expect(s.active());
    s.up(1);
    try expect(!s.active());
}

const TouchStick = @This();

const c = @import("sdl.zig").c;

const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
