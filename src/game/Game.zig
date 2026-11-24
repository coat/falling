//! Core game logic: players, platforms, scrolling scoring - no presentation
//! layer (like SDL)

/// World grid unit that sizes and platform positions are derived from
pub const cell = 8;
/// Shaft interior wall to wall. Walls are presentation-only
pub const width = 24 * cell;
pub const height = 22 * cell;

pub const tick_rate = 60;

pub const Difficulty = enum(u8) { easy = 1, normal = 2, hard = 3 };

pub const floor_height = cell * 16;

ticks: u32 = 0,
depth: f32 = 0,
difficulty: Difficulty = .normal,
paused: bool = false,
players: [2]?Player = .{ .init, null },
platform_buffer: [8]Platform = undefined,
platforms: std.ArrayListUnmanaged(Platform) = .empty,
prng: std.Random.DefaultPrng = undefined,

pub fn init(game: *Game, seed: u64) void {
    game.prng = .init(seed);
    game.platforms = std.ArrayListUnmanaged(Platform).initBuffer(&game.platform_buffer);
    game.reset();
}

pub fn reset(self: *Game) void {
    self.platforms.clearRetainingCapacity();
    for (0..7) |i| {
        const y: f32 = @floatFromInt(i * platform_spacing + cell);
        self.platforms.appendBounded(.init(self.prng.random(), y, self.platformLevel())) catch unreachable;
    }

    const start: Platform = .{ .x = cell * 9, .y = 7 * platform_spacing + cell };
    self.platforms.appendBounded(start) catch unreachable;

    const center = start.x + (Platform.width - Player.size) / 2;
    const offsets: [2]f32 = if (self.players[1] != null) .{ 12, -12 } else .{ 0, 0 };
    for (&self.players, offsets) |*slot, dx| {
        if (slot.* != null) slot.* = .at(center + dx, start.y - Player.size);
    }
}

pub fn isOver(self: Game) bool {
    var has_players = false;
    for (self.players) |slot| {
        const p = slot orelse continue;
        if (p.isAlive()) return false;
        has_players = true;
    }
    return has_players;
}

pub fn tick(self: *Game) void {
    if (self.paused or self.isOver()) return;
    self.ticks +%= 1;

    self.depth += self.scrollSpeed();
    self.recyclePlatforms();
    for (&self.players) |*slot| {
        const player: *Player = if (slot.*) |*p| p else continue;
        if (!player.isAlive()) continue;

        player.move();
        self.collidePlayer(player);
        player.clampToShaft();
        self.checkBounds(player);
        player.updateState();
    }
}

pub fn refSpeed(px_per_tick: f32) f32 {
    return px_per_tick * ref_scale * ref_dt;
}

pub fn refPx(comptime px: comptime_float) f32 {
    return px * ref_scale;
}

pub fn refAccel(comptime px_per_tick2: comptime_float) f32 {
    return px_per_tick2 * ref_scale * ref_dt * ref_dt;
}

pub fn refTicks(comptime ticks: comptime_int) u32 {
    return @round(@as(comptime_float, ticks) / ref_dt);
}

pub fn pause(self: *Game) void {
    self.paused = !self.paused;
}

pub fn autoPause(self: *Game) void {
    if (!self.isOver()) self.paused = true;
}

pub fn floor(self: Game) u32 {
    return 1 + @as(u32, @intFromFloat(self.depth / floor_height));
}

pub fn scrollSpeed(self: Game) f32 {
    const d: f32 = @floatFromInt(@intFromEnum(self.difficulty));
    const f: f32 = @floatFromInt(self.floor());
    return refSpeed(d + 2 + f / 80);
}

fn platformLevel(self: Game) u32 {
    return @min(4, @intFromEnum(self.difficulty) + self.floor() / 40 - 1);
}

const platform_spacing = cell * 3;

// converts https://github.com/cdfmr/NS-SHAFT-NS-TOWER 40ms timer to our timing
const ref_rate = 25.0;
const ref_scale = 0.5;
const ref_dt = ref_rate / @as(comptime_float, tick_rate);

fn collidePlayer(self: *Game, player: *Player) void {
    const was_grounded = player.grounded;
    player.grounded = false;
    if (player.vel < 0) return;

    for (self.platforms.items) |*platform| {
        if (!platform.isSolid(self.ticks)) continue;

        const top = platform.top(self.ticks);
        if (player.feetBefore() > @max(top, platform.y) + 0.01) continue; // already below
        if (player.feet() < @min(top, platform.y)) continue;
        if (player.x + Player.size - Player.foot_inset <= platform.x) continue;
        if (player.x + Player.foot_inset >= platform.x + Platform.width) continue;

        player.y = top - Player.size;
        player.vel = 0;
        player.grounded = true;

        if (!was_grounded) {
            platform.trigger(self.ticks);
            if (platform.type == .spikes) player.hurt() else player.heal();
        }

        switch (platform.type) {
            .trampoline => if (platform.elapsed(self.ticks).? >= Platform.trampoline_launch) {
                player.vel = Player.bounce_vel;
                player.grounded = false;
            },
            .left_treadmill => player.x -= Player.conveyer_speed,
            .right_treadmill => player.x += Player.conveyer_speed,
            else => {},
        }
        return;
    }
}

const ceiling = refPx(4);

fn checkBounds(self: *Game, player: *Player) void {
    const top = self.depth + ceiling;
    if (player.y < top) {
        player.hurt();
        player.y = top + 1;
        player.vel = self.scrollSpeed();
        player.grounded = false;
    }
    if (player.y >= self.depth + height) player.health = 0;
}

fn recyclePlatforms(self: *Game) void {
    const items = self.platforms.items;
    if (items[0].y + cell * 2 >= self.depth) return;

    const next_y = items[items.len - 1].y + platform_spacing;
    _ = self.platforms.orderedRemove(0);
    self.platforms.appendBounded(.init(self.prng.random(), next_y, self.platformLevel())) catch unreachable;
}

test "a single player starts centered on a normal platform" {
    var g: Game = .{ .players = .{ .init, null } };
    g.init(3);

    const start = g.platforms.items[g.platforms.items.len - 1];
    try expectEqual(Platform.Type.normal, start.type);

    const p = g.players[0].?;
    try expectEqual(start.x + (Platform.width - Player.size) / 2, p.x);
    try expectEqual(start.y - Player.size, p.y);
}

test "two players start side by side" {
    var g: Game = .{ .players = .{ .init, .init } };
    g.init(3);
    try expectEqual(24, g.players[0].?.x - g.players[1].?.x);
}

test "same seeds produces same platforms" {
    var a: Game = .{};
    a.init(42);

    var b: Game = .{};
    b.init(42);

    for (0..500) |_| {
        a.tick();
        b.tick();
    }
    try std.testing.expectEqualSlices(Platform, a.platforms.items, b.platforms.items);
}

fn setupTest(g: *Game, platform: Platform, player_y: f32) void {
    g.init(1);
    g.platforms.clearRetainingCapacity();
    g.platforms.appendBounded(platform) catch unreachable;
    g.players[0].?.x = platform.x + 8;
    g.players[0].?.y = player_y;
}

test "player lands and stays on a platform" {
    var g: Game = .{};
    setupTest(&g, .{ .x = 40, .y = 120 }, 20);
    for (0..60) |_| g.tick();

    const p = g.players[0].?;
    try expect(p.grounded);
    try expectEqual(g.platforms.items[0].y - Player.size, p.y);
}

test "fast fall does not tunnel through" {
    var g: Game = .{};
    setupTest(&g, .{ .x = 40, .y = 120 }, 20);
    g.players[0].?.vel = 4;
    for (0..60) |_| g.tick();
    try expect(g.players[0].?.grounded);
}

fn tickUntilGrounded(g: *Game) !void {
    for (0..120) |_| {
        g.tick();
        if (g.players[0].?.grounded) return;
    }
    return error.NeverLanded;
}

test "open trapdoor drops the player" {
    var g: Game = .{};
    setupTest(&g, .{ .type = .trapdoor, .x = 40, .y = 150 }, 150 - Player.size - 2);
    try tickUntilGrounded(&g);

    for (0..Platform.trapdoor_open) |_| g.tick();
    try expect(!g.players[0].?.grounded);
}

test "players land independently" {
    var g: Game = .{};
    setupTest(&g, .{ .x = 40, .y = 120 }, 20);

    g.players[1] = .init;
    g.players[1].?.x = 150; // not above the platform
    g.players[1].?.y = 20;

    for (0..60) |_| g.tick();
    try expect(g.players[0].?.grounded);
    try expect(!g.players[1].?.grounded);
}

test "recycled platforms keep exact spacing" {
    var g: Game = .{};
    g.init(7);
    for (0..2000) |_| g.tick();

    const items = g.platforms.items;
    for (items[0 .. items.len - 1], items[1..]) |a, b| {
        try expectEqual(@as(f32, platform_spacing), b.y - a.y);
    }
}

test "spikes hurt once per landing" {
    var g: Game = .{};
    setupTest(&g, .{ .type = .spikes, .x = 40, .y = 150 }, 120);
    try tickUntilGrounded(&g);
    for (0..30) |_| g.tick();
    try expectEqual(Player.max_health - Player.hurt_amount, g.players[0].?.health);
}

test "landing heals once" {
    var g: Game = .{};
    setupTest(&g, .{ .x = 40, .y = 150 }, 120);
    g.players[0].?.health = 5;
    try tickUntilGrounded(&g);
    for (0..30) |_| g.tick();
    try expectEqual(6, g.players[0].?.health);
}

test "ceiling hurts and drops the player through" {
    var g: Game = .{};
    setupTest(&g, .{ .x = 40, .y = 30 }, 30 - Player.size);
    try tickUntilGrounded(&g);
    for (0..40) |_| g.tick();

    const p = g.players[0].?;
    try expectEqual(Player.max_health - Player.hurt_amount, p.health);
    try expect(p.y > g.platforms.items[0].y);
}

test "falling off the bottom ends a single-player game" {
    var g: Game = .{};
    setupTest(&g, .{ .x = 150, .y = 170 }, 20);
    g.players[0].?.x = 10; // not above the platform
    for (0..120) |_| g.tick();
    try expect(g.isOver());
}

test "co-op continues while anyone is alive" {
    var g: Game = .{};
    g.init(1);
    g.players[1] = .init;
    g.players[0].?.health = 0;
    try expect(!g.isOver());
    g.players[1].?.health = 0;
    try expect(g.isOver());
}

test "a game with no players is not over" {
    var g: Game = .{ .players = .{ null, null } };
    g.init(1);
    try expect(!g.isOver());
}

test "a game with no players keeps scrolling" {
    var g: Game = .{ .players = .{ null, null } };
    g.init(1);
    const first_y = g.platforms.items[0].y;
    for (0..600) |_| g.tick();
    try expect(g.depth > 0);
    try expect(g.platforms.items[0].y > first_y); // top platforms were recycled
}

test "autoPause keeps a paused game paused" {
    var g: Game = .{};
    g.init(1);
    g.autoPause();
    g.autoPause();
    try expect(g.paused);
}

test "autoPause leaves a finished game alone" {
    var g: Game = .{ .players = .{ .init, null } };
    g.init(1);
    g.players[0].?.health = 0;
    g.autoPause();
    try expect(!g.paused);
}

const Game = @This();

const Platform = @import("Platform.zig");
const Player = @import("Player.zig");

const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
