pub const width: f32 = cell * 6;

pub const Type = enum {
    normal,
    spikes,
    left_treadmill,
    right_treadmill,
    trampoline,
    trapdoor,
};

type: Type = .normal,
x: f32,
y: f32,
triggered_at: ?u32 = null,

pub fn init(rng: std.Random, y: f32, level: u32) Platform {
    const slots = (Game.width - width) / cell;
    const x: f32 = @floatFromInt(rng.intRangeAtMost(u32, 0, slots) * cell);

    const roll = rng.uintLessThan(u32, 30 - level * 6);

    return .{ .type = switch (roll) {
        0 => .right_treadmill,
        1 => .left_treadmill,
        2...5 => .spikes,
        6, 7 => .trampoline,
        8, 9 => .trapdoor,
        else => .normal,
    }, .x = x, .y = y };
}

pub const trapdoor_open = Game.refTicks(3);
pub const trapdoor_cycle = Game.refTicks(18);

pub const trampoline_press = Game.refTicks(1);
pub const trampoline_launch = Game.refTicks(2);
pub const trampoline_settle = Game.refTicks(7);

pub fn trigger(self: *Platform, now: u32) void {
    switch (self.type) {
        .trapdoor => if (self.elapsed(now) orelse trapdoor_cycle >= trapdoor_cycle) {
            self.triggered_at = now;
        },
        .trampoline => if (self.elapsed(now) orelse trampoline_launch >= trampoline_launch) {
            self.triggered_at = now;
        },
        else => {},
    }
}

pub fn elapsed(self: Platform, now: u32) ?u32 {
    const t = self.triggered_at orelse return null;
    return now -% t;
}

pub fn isSolid(self: Platform, now: u32) bool {
    return switch (self.type) {
        .trapdoor => if (self.elapsed(now)) |e| e < trapdoor_open or e >= trapdoor_cycle else true,
        else => true,
    };
}

pub fn compression(self: Platform, now: u32) f32 {
    if (self.type != .trampoline) return 0;
    const e = self.elapsed(now) orelse return 0;
    if (e < trampoline_press or e >= trampoline_settle) return 0;
    if (e <= trampoline_launch) return Game.refPx(4);
    // overshoots up 8, then eases back to rest
    const left: f32 = @floatFromInt(trampoline_settle - e);
    const span: f32 = @floatFromInt(trampoline_settle - trampoline_launch);
    return -Game.refPx(8) * left / span;
}

pub fn top(self: Platform, now: u32) f32 {
    return self.y + self.compression(now);
}

test "trapdoor stays solid until the delay passes" {
    var p: Platform = .{ .type = .trapdoor, .x = 0, .y = 0 };
    try expect(p.isSolid(100));

    p.trigger(100);
    try expect(p.isSolid(100 + trapdoor_open - 1));
    try expect(!p.isSolid(100 + trapdoor_open));
}

test "trapdoor keeps its first trigger time" {
    var p: Platform = .{ .type = .trapdoor, .x = 0, .y = 0 };
    p.trigger(100);
    p.trigger(120);
    try expectEqual(@as(?u32, 100), p.triggered_at);
}

test "trapdoor closes and can retrigger after its cycle" {
    var p: Platform = .{ .type = .trapdoor, .x = 0, .y = 0 };
    p.trigger(100);
    try expect(p.isSolid(100 + trapdoor_cycle));
    p.trigger(100 + trapdoor_cycle);
    try expectEqual(@as(?u32, 100 + trapdoor_cycle), p.triggered_at);
}

test "trampoline retriggers on every bounce" {
    var p: Platform = .{ .type = .trampoline, .x = 0, .y = 0 };
    p.trigger(100);
    p.trigger(120);
    try expectEqual(@as(?u32, 120), p.triggered_at);
}

test "trampoline presses, then rebounds, then rests" {
    var p: Platform = .{ .type = .trampoline, .x = 0, .y = 0 };
    p.trigger(100);
    try expectEqual(0, p.compression(100));
    try expectEqual(Game.refPx(4), p.compression(100 + trampoline_press));
    try expect(p.compression(100 + trampoline_launch + 1) < 0);
    try expectEqual(0, p.compression(100 + trampoline_settle));
}

const Platform = @This();

const Game = @import("Game.zig");
const cell = Game.cell;

const std = @import("std");
const testing = std.testing;
const expect = testing.expect;
const expectEqual = testing.expectEqual;
