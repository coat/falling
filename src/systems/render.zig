pub fn render(
    reg: *Registry,
    renderer: *c.SDL_Renderer,
    spritesheet: *c.SDL_Texture,
    // window: *c.SDL_Window,
) !void {
    try errify(c.SDL_SetRenderDrawColor(renderer, 0x37, 0x2a, 0x39, 0xff));
    try errify(c.SDL_RenderClear(renderer));

    // header
    try errify(c.SDL_RenderTexture9Grid(
        renderer,
        spritesheet,
        &sprites.panel_grid,
        tile_size,
        tile_size,
        tile_size,
        tile_size,
        1,
        &.{
            .x = 0,
            .y = 0,
            .w = game.width,
            .h = game.header,
        },
    ));

    // footer
    try errify(c.SDL_RenderTexture9Grid(
        renderer,
        spritesheet,
        &sprites.panel_grid,
        tile_size,
        tile_size,
        tile_size,
        tile_size,
        1,
        &.{
            .x = 0,
            .y = game.header + game.shaft_height,
            .w = game.width,
            .h = game.footer,
        },
    ));

    if (builtin.os.tag == .emscripten) {
        try errify(c.SDL_RenderTexture9Grid(
            renderer,
            spritesheet,
            &sprites.touchpad_grid,
            tile_size,
            tile_size,
            tile_size,
            tile_size,
            1,
            &.{
                .x = 0,
                .y = game.height - game.touchpad_height,
                .w = game.width,
                .h = game.touchpad_height,
            },
        ));
    }

    const shaft_rect = c.SDL_FRect{
        .x = 0,
        .y = game.header,
        .w = @floatFromInt(game.shaft_width),
        .h = @floatFromInt(game.shaft_height),
    };
    try errify(c.SDL_SetRenderClipRect(
        renderer,
        &.{
            .x = @intFromFloat(@floor(shaft_rect.x)),
            .y = @intFromFloat(@floor(shaft_rect.y)),
            .w = game.shaft_width,
            .h = game.shaft_height,
        },
    ));

    try renderBackgroundSprites(reg, renderer, spritesheet);
    try errify(c.SDL_SetRenderClipRect(renderer, null));

    // if (builtin.mode == .Debug) {
    //     try errify(c.SDL_SetRenderDrawColor(renderer, 0xf5, 0xe9, 0xbf, 0xff));
    //     try errify(c.SDL_RenderRect(renderer, &.{
    //         .x = 0,
    //         .y = 0,
    //         .w = game.width,
    //         .h = game.height,
    //     }));
    //     var w: i32 = undefined;
    //     var h: i32 = undefined;
    //     try errify(c.SDL_GetWindowSize(window, &w, &h));
    //     var buf: [32]u8 = undefined;
    //     const text = try std.fmt.bufPrintZ(&buf, "{d}x{d}", .{ w, h });
    //     try errify(c.SDL_RenderDebugText(renderer, 2, 2, text.ptr));
    // }

    // ceiling spikes
    try errify(c.SDL_RenderTextureTiled(
        renderer,
        spritesheet,
        &sprites.spikes,
        1,
        &.{ .x = tile_size, .y = game.header, .w = tile_size * 24, .h = tile_size },
    ));

    try errify(c.SDL_RenderPresent(renderer));
}

fn renderBackgroundSprites(
    reg: *Registry,
    renderer: *c.SDL_Renderer,
    spritesheet: *c.SDL_Texture,
) !void {
    var view = reg.view(.{ Sprite, BackgroundSprite, Position, Size }, .{});

    var iter = view.entityIterator();
    while (iter.next()) |entity| {
        const pos = view.get(Position, entity);
        const size = view.get(Size, entity);
        const sprite = view.getConst(Sprite, entity);

        const flags = if (sprite.flip_x) c.SDL_FLIP_HORIZONTAL else c.SDL_FLIP_NONE;

        try renderTextureTiledRotated(
            renderer,
            spritesheet,
            &.{ .x = @floor(sprite.x), .y = @floor(sprite.y), .w = sprite.w, .h = sprite.h },
            &.{ .x = @floor(pos.x), .y = @floor(pos.y), .w = size.w, .h = size.h },
            @intCast(flags),
        );
    }
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
    const touchpad_grid: c.SDL_FRect = .{
        .x = tile_size * 18,
        .y = tile_size * 18,
        .h = tile_size * 2,
        .w = tile_size * 2,
    };
    const panel_grid: c.SDL_FRect = .{
        .x = tile_size * 18,
        .y = tile_size * 20,
        .h = tile_size * 2,
        .w = tile_size * 2,
    };
    const spikes: c.SDL_FRect = .{
        .x = tile_size,
        .y = tile_size,
        .w = tile_size,
        .h = tile_size,
    };
};

const game = @import("../game.zig");
const tile_size = game.tile_size;

const falling = @import("../root.zig");
const c = falling.c;
const errify = falling.errify;

const components = @import("../components.zig");
const Position = components.Position;
const InitialPosition = components.InitialPosition;
const Size = components.Size;
const Velocity = components.Velocity;
const Sprite = components.Sprite;
const BackgroundSprite = components.BackgroundSprite;

const ecs = @import("entt");
const Registry = ecs.Registry;

const std = @import("std");
const builtin = @import("builtin");
