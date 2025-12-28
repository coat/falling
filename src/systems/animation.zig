pub fn run(reg: *Registry) void {
    animateSprites(reg);
}

fn animateSprites(reg: *Registry) void {
    var view = reg.view(.{SpriteAnimation}, .{});

    var iter = view.entityIterator();
    while (iter.next()) |entity| {
        var sprite_animation = view.get(entity);
        if (sprite_animation.state == .play) {
            sprite_animation.elapsed += 1;
            if (@floor(sprite_animation.elapsed) > @as(f32, @floatFromInt(sprite_animation.delay))) {
                sprite_animation.frame += 1;

                sprite_animation.elapsed = 0;
                if (sprite_animation.frame > sprite_animation.frames.len - 1) {
                    sprite_animation.frame = 0;
                    if (!sprite_animation.loop) {
                        sprite_animation.state = .reset;
                    }
                }
            }
        }
    }
}

const std = @import("std");
const ecs = @import("entt");
const Registry = ecs.Registry;

const components = @import("../components.zig");
const Frame = components.Frame;
const Sprite = components.Sprite;
const SpriteAnimation = components.SpriteAnimation;

test "animateSprites advances frame after delay" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    var frames = [_]Frame{ .{}, .{}, .{} };
    const entity = reg.create();
    reg.add(entity, SpriteAnimation{
        .frames = &frames,
        .frame = 0,
        .elapsed = 16, // at delay threshold
        .delay = 16,
        .loop = true,
        .state = .play,
    });

    animateSprites(&reg);

    const anim = reg.get(SpriteAnimation, entity);
    try std.testing.expectEqual(@as(usize, 1), anim.frame);
    try std.testing.expectEqual(@as(f32, 0), anim.elapsed);
}

test "animateSprites loops back to frame 0" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    var frames = [_]Frame{ .{}, .{} };
    const entity = reg.create();
    reg.add(entity, SpriteAnimation{
        .frames = &frames,
        .frame = 1, // last frame
        .elapsed = 17,
        .delay = 16,
        .loop = true,
        .state = .play,
    });

    animateSprites(&reg);

    const anim = reg.get(SpriteAnimation, entity);
    try std.testing.expectEqual(@as(usize, 0), anim.frame);
    try std.testing.expectEqual(SpriteAnimation.State.play, anim.state);
}

test "animateSprites sets reset state when not looping" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    var frames = [_]Frame{ .{}, .{} };
    const entity = reg.create();
    reg.add(entity, SpriteAnimation{
        .frames = &frames,
        .frame = 1,
        .elapsed = 17,
        .delay = 16,
        .loop = false,
        .state = .play,
    });

    animateSprites(&reg);

    const anim = reg.get(SpriteAnimation, entity);
    try std.testing.expectEqual(SpriteAnimation.State.reset, anim.state);
}

test "animateSprites does nothing when paused" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();

    var frames = [_]Frame{ .{}, .{} };
    const entity = reg.create();
    reg.add(entity, SpriteAnimation{
        .frames = &frames,
        .frame = 0,
        .elapsed = 100,
        .delay = 16,
        .loop = true,
        .state = .pause,
    });

    animateSprites(&reg);

    const anim = reg.get(SpriteAnimation, entity);
    try std.testing.expectEqual(@as(usize, 0), anim.frame);
    try std.testing.expectEqual(@as(f32, 100), anim.elapsed); // unchanged
}
