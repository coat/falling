//! Persists best floor via SDL Storage

best: std.EnumArray(Difficulty, u32) = .initFill(0),

pub fn load(self: *HighScore) void {
    const storage = openStorage() catch {
        log.warn("could not open storage: {s}", .{c.SDL_GetError()});
        return;
    };
    defer _ = c.SDL_CloseStorage(storage);

    for (std.enums.values(Difficulty)) |d| {
        var le: u32 = undefined;
        errify(c.SDL_ReadStorageFile(storage, fileName(d), &le, @sizeOf(u32))) catch {
            log.debug("no saved best for {t}", .{d});
            continue;
        };
        self.best.set(d, std.mem.littleToNative(u32, le));
    }
}

pub fn improve(self: *HighScore, d: Difficulty, floor: u32) bool {
    if (floor <= self.best.get(d)) return false;
    self.best.set(d, floor);
    return true;
}

pub fn record(self: *HighScore, d: Difficulty, floor: u32) void {
    if (!self.improve(d, floor)) return;
    save(d, floor) catch {
        log.warn("could not save best for {t}: {s}", .{ d, c.SDL_GetError() });
    };
}

fn save(d: Difficulty, floor: u32) !void {
    const storage = try openStorage();
    defer _ = c.SDL_CloseStorage(storage);

    const le = std.mem.nativeToLittle(u32, floor);
    try errify(c.SDL_WriteStorageFile(storage, fileName(d), &le, @sizeOf(u32)));
}

fn openStorage() !*c.SDL_Storage {
    const storage = try errify(c.SDL_OpenUserStorage("sadbeast", options.name, 0));
    errdefer _ = c.SDL_CloseStorage(storage);

    if (!c.SDL_StorageReady(storage)) return error.SdlError;
    return storage;
}

fn fileName(d: Difficulty) [:0]const u8 {
    return switch (d) {
        inline else => |tag| "best_" ++ @tagName(tag),
    };
}

test "improve only raises the best" {
    var hs: HighScore = .{};
    try expect(hs.improve(.normal, 5));
    try expect(!hs.improve(.normal, 5));
    try expect(!hs.improve(.normal, 3));
    try expectEqual(5, hs.best.get(.normal));
}

test "difficulties are tracked separately" {
    var hs: HighScore = .{};
    _ = hs.improve(.hard, 9);
    try expectEqual(0, hs.best.get(.normal));
    try expectEqual(9, hs.best.get(.hard));
}

const HighScore = @This();

const Game = @import("falling").Game;
const Difficulty = Game.Difficulty;

const sdl = @import("sdl.zig");
const c = sdl.c;
const errify = sdl.errify;
const options = @import("options");

const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const log = std.log.scoped(.high_score);
