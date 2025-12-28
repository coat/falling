pub const tile_size = 8;
pub const header = tile_size * 2;
pub const shaft_width = 26 * tile_size;
pub const shaft_height = 22 * tile_size;
pub const footer = tile_size * 2;
pub const width: u32 = shaft_width;
pub const touchpad_height: u32 = tile_size * 17;
pub const height: u32 = header + shaft_height + footer + if (builtin.os.tag == .emscripten) touchpad_height else 0;

pub const Game = struct {
    pub const name = "falling";
    const default_zoom = 2;

    reg: ecs.Registry,
    dispatcher: ecs.Dispatcher,

    timekeeper: Timekeeper,

    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    sprites: *c.SDL_Texture,

    state: enum {
        running,
        paused,
        menu,
    } = .menu,

    zoom: u8 = default_zoom,

    /// caller owns Game
    pub fn init(alloc: Allocator) !*Game {
        var window: *c.SDL_Window = undefined;
        var renderer: *c.SDL_Renderer = undefined;

        try errify(c.SDL_CreateWindowAndRenderer(
            name,
            width * default_zoom,
            height * default_zoom,
            if (builtin.os.tag == .emscripten) c.SDL_WINDOW_RESIZABLE else 0,
            @ptrCast(&window),
            @ptrCast(&renderer),
        ));
        errdefer c.SDL_DestroyRenderer(renderer);
        errdefer c.SDL_DestroyWindow(window);

        try errify(c.SDL_SetRenderLogicalPresentation(renderer, width, height, c.SDL_LOGICAL_PRESENTATION_INTEGER_SCALE));

        var sprites_texture: *c.SDL_Texture = undefined;
        {
            const compressed_sprites = @embedFile("sprites.bmp.ulz");

            const sprites = try ulz.decode(alloc, compressed_sprites);
            defer alloc.free(sprites);

            const stream: *c.SDL_IOStream = try errify(c.SDL_IOFromConstMem(sprites.ptr, sprites.len));
            const surface: *c.SDL_Surface = try errify(c.SDL_LoadBMP_IO(stream, true));
            defer c.SDL_DestroySurface(surface);

            sprites_texture = try errify(c.SDL_CreateTextureFromSurface(renderer, surface));

            try errify(c.SDL_SetTextureScaleMode(sprites_texture, c.SDL_SCALEMODE_NEAREST));

            errdefer comptime unreachable;
        }
        errdefer c.SDL_DestroyTexture(sprites_texture);

        var game = try alloc.create(Game);
        errdefer alloc.destroy(game);

        var reg = ecs.Registry.init(alloc);
        errdefer reg.deinit();

        game.* = .{
            .reg = reg,
            .dispatcher = ecs.Dispatcher.init(alloc),
            .timekeeper = .{ .tocks_per_s = c.SDL_GetPerformanceFrequency() },

            .window = window,
            .renderer = renderer,
            .sprites = sprites_texture,
        };

        const current_input: input.Input = .reset;
        game.reg.singletons().add(current_input);

        const prev_input: input.PrevInput = .reset;
        game.reg.singletons().add(prev_input);

        var sink = game.dispatcher.sink(.{falling.ZoomRequest});
        sink.connectBound(game, changeZoom);

        return game;
    }

    pub fn deinit(self: *Game) void {
        c.SDL_DestroyTexture(self.sprites);
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);

        self.dispatcher.deinit();
        self.reg.deinit();
    }

    pub fn iterate(self: *Game) c.SDL_AppResult {
        while (self.timekeeper.consume()) {
            if (!input.playerInput(&self.reg, &self.dispatcher)) return c.SDL_APP_SUCCESS;
        }
        self.render() catch return c.SDL_APP_FAILURE;

        self.timekeeper.produce(c.SDL_GetPerformanceCounter());

        return c.SDL_APP_CONTINUE;
    }

    pub fn processInput(self: *Game, event: *c.SDL_Event) !c.SDL_AppResult {
        switch (event.type) {
            c.SDL_EVENT_KEY_DOWN, c.SDL_EVENT_KEY_UP => {
                input.processKeyboard(&self.reg, event);
            },
            c.SDL_EVENT_QUIT => return c.SDL_APP_SUCCESS,

            else => {},
        }
        return c.SDL_APP_CONTINUE;
    }

    pub fn changeZoom(self: *Game, _: falling.ZoomRequest) void {
        self.zoom += 1;
        if (self.zoom > 3) self.zoom = 1;

        errify(c.SDL_SetWindowSize(self.window, @intCast(width * self.zoom), @intCast(height * self.zoom))) catch return;
    }

    fn render(self: *Game) !void {
        try errify(c.SDL_SetRenderDrawColor(self.renderer, 0x37, 0x2a, 0x39, 0xff));
        try errify(c.SDL_RenderClear(self.renderer));

        {
            try errify(c.SDL_SetRenderDrawColor(self.renderer, 0xf5, 0xe9, 0xbf, 0xff));
            var w: i32 = undefined;
            var h: i32 = undefined;
            try errify(c.SDL_GetWindowSize(self.window, &w, &h));
            var buf: [32]u8 = undefined;
            const text = try std.fmt.bufPrintZ(&buf, "{d}x{d}", .{ w, h });
            try errify(c.SDL_RenderDebugText(self.renderer, 0, 0, text.ptr));
        }

        try errify(c.SDL_RenderPresent(self.renderer));
    }
};

/// Facilitates updating the game logic at a fixed rate.
// Taken from
// https://github.com/castholm/zig-examples/blob/4a8dd3da5beb93c44132e2046245a2642971a9f0/breakout/main.zig
// Inspired by <https://github.com/TylerGlaiel/FrameTimingControl> and the linked article.
const Timekeeper = struct {
    const updates_per_s = 60;
    const max_accumulated_updates = 8;
    const snap_frame_rates = .{ updates_per_s, 30, 120, 144 };
    const ticks_per_tock = 720; // Least common multiple of 'snap_frame_rates'
    const snap_tolerance_us = 200;
    const us_per_s = 1_000_000;

    tocks_per_s: u64,
    accumulated_ticks: u64 = 0,
    previous_timestamp: ?u64 = null,

    fn consume(timekeeper_: *Timekeeper) bool {
        const ticks_per_s: u64 = timekeeper_.tocks_per_s * ticks_per_tock;
        const ticks_per_update: u64 = @divExact(ticks_per_s, updates_per_s);
        if (timekeeper_.accumulated_ticks >= ticks_per_update) {
            timekeeper_.accumulated_ticks -= ticks_per_update;
            return true;
        } else {
            return false;
        }
    }

    fn produce(timekeeper_: *Timekeeper, current_timestamp: u64) void {
        if (timekeeper_.previous_timestamp) |previous_timestamp| {
            const ticks_per_s: u64 = timekeeper_.tocks_per_s * ticks_per_tock;
            const elapsed_ticks: u64 = (current_timestamp -% previous_timestamp) *| ticks_per_tock;
            const snapped_elapsed_ticks: u64 = inline for (snap_frame_rates) |snap_frame_rate| {
                const target_ticks: u64 = @divExact(ticks_per_s, snap_frame_rate);
                const abs_diff = @max(elapsed_ticks, target_ticks) - @min(elapsed_ticks, target_ticks);
                if (abs_diff *| us_per_s <= snap_tolerance_us *| ticks_per_s) {
                    break target_ticks;
                }
            } else elapsed_ticks;
            const ticks_per_update: u64 = @divExact(ticks_per_s, updates_per_s);
            const max_accumulated_ticks: u64 = max_accumulated_updates * ticks_per_update;
            timekeeper_.accumulated_ticks = @min(timekeeper_.accumulated_ticks +| snapped_elapsed_ticks, max_accumulated_ticks);
        }
        timekeeper_.previous_timestamp = current_timestamp;
    }
};

const falling = @import("root.zig");
const c = falling.c;
const errify = falling.errify;

const input = @import("systems/input.zig");

const ecs = @import("entt");

const ulz = @import("ulz");

const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
