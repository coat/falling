pub fn run(reg: *Registry) void {
    move(reg);
    resetBackgroundSprites(reg);
}

// pub fn reset(reg: *Registry) void {
//     var view = reg.view(.{ InitialPosition, Position }, .{});
//
//     var iter = view.entityIterator();
//     while (iter.next()) |entity| {
//         const initial_pos = view.getConst(InitialPosition, entity);
//         var pos = view.get(Position, entity);
//         pos.y = initial_pos.y;
//         pos.x = initial_pos.x;
//     }
// }

fn move(reg: *Registry) void {
    var view = reg.view(.{ Position, Velocity }, .{});

    var iter = view.entityIterator();
    while (iter.next()) |entity| {
        const vel = view.getConst(Velocity, entity);
        var pos = view.get(Position, entity);

        pos.x += vel.x;
        pos.y += vel.y;
    }
}

fn resetBackgroundSprites(reg: *Registry) void {
    var view = reg.view(.{ BackgroundSprite, Sprite, InitialPosition, Position }, .{});

    var iter = view.entityIterator();
    while (iter.next()) |entity| {
        const sprite = view.getConst(Sprite, entity);
        const initial_pos = view.getConst(InitialPosition, entity);
        var pos = view.get(Position, entity);
        if (@abs(initial_pos.y - @floor(pos.y)) >= sprite.h) {
            pos.y += sprite.h;
        }
    }
}

const components = @import("../components.zig");
const BackgroundSprite = components.BackgroundSprite;
const Sprite = components.Sprite;
const Position = components.Position;
const InitialPosition = components.InitialPosition;
const Velocity = components.Velocity;

const ecs = @import("entt");
const Registry = ecs.Registry;

test "move updates position based on velocity" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const entity = reg.create();
    reg.add(entity, Position{ .x = 10, .y = 20 });
    reg.add(entity, Velocity{ .x = 5, .y = -3 });

    move(&reg);

    const pos = reg.get(Position, entity);
    try std.testing.expectEqual(@as(f32, 15), pos.x);
    try std.testing.expectEqual(@as(f32, 17), pos.y);
}

test "resetBackgroundSprites wraps position when exceeding sprite height" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const entity = reg.create();
    reg.add(entity, BackgroundSprite{});
    reg.add(entity, Sprite{ .x = 0, .y = 0, .w = 100, .h = 50 });
    reg.add(entity, InitialPosition{ .x = 0, .y = 0 });
    reg.add(entity, Position{ .x = 0, .y = -50 }); // moved exactly sprite height

    resetBackgroundSprites(&reg);

    const pos = reg.get(Position, entity);
    try std.testing.expectEqual(@as(f32, 0), pos.y); // should wrap back
}

test "resetBackgroundSprites does not wrap when within bounds" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    const entity = reg.create();
    reg.add(entity, BackgroundSprite{});
    reg.add(entity, Sprite{ .x = 0, .y = 0, .w = 100, .h = 50 });
    reg.add(entity, InitialPosition{ .x = 0, .y = 0 });
    reg.add(entity, Position{ .x = 0, .y = -30 }); // less than sprite height

    resetBackgroundSprites(&reg);

    const pos = reg.get(Position, entity);
    try std.testing.expectEqual(@as(f32, -30), pos.y); // unchanged
}

const std = @import("std");
