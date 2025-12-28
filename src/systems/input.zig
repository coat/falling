pub const VirtualController = struct {
    zoom: bool,
    escape: bool,
    pause: bool,

    pub fn fromPhysical(
        self: *VirtualController,
        phcon: PhysicalController,
    ) void {
        self.zoom = phcon.k_f1;
        self.escape = phcon.k_esc;
    }

    pub const reset: VirtualController = .{
        .zoom = false,
        .escape = false,
        .pause = false,
    };
};

pub const PhysicalController = struct {
    k_f1: bool,
    k_esc: bool,
    k_p: bool,

    pub const reset: PhysicalController = .{
        .k_f1 = false,
        .k_esc = false,
        .k_p = false,
    };
};

pub const Input = struct {
    v_con: VirtualController,
    ph_con: PhysicalController,

    pub const reset: Input = .{ .v_con = .reset, .ph_con = .reset };
};

pub const PrevInput = struct {
    v_con: VirtualController,
    ph_con: PhysicalController,

    pub const reset: PrevInput = .{ .v_con = .reset, .ph_con = .reset };
};

pub fn processKeyboard(reg: *Registry, event: *c.SDL_Event) void {
    const down = event.type == c.SDL_EVENT_KEY_DOWN;
    switch (event.key.scancode) {
        c.SDL_SCANCODE_F1 => reg.singletons().get(Input).ph_con.k_f1 = down,
        c.SDL_SCANCODE_ESCAPE => reg.singletons().get(Input).ph_con.k_esc = down,
        c.SDL_SCANCODE_P => reg.singletons().get(Input).ph_con.k_p = down,
        else => {},
    }
}

pub fn playerInput(reg: *Registry, dispatcher: *ecs.Dispatcher) bool {
    const ph_con = reg.singletons().getConst(Input).ph_con;
    const prev_vcon = reg.singletons().get(PrevInput).v_con;

    reg.singletons().get(Input).v_con.fromPhysical(ph_con);
    const v_con = reg.singletons().get(Input).v_con;

    if (v_con.escape and !prev_vcon.escape) {
        return false;
    }

    if (v_con.pause and !prev_vcon.pause) {
        dispatcher.trigger(.{falling.Command}, .{.pause});
    }

    if (builtin.os.tag != .emscripten) {
        if (v_con.zoom and !prev_vcon.zoom) {
            dispatcher.trigger(.{falling.Command}, .{.zoom});
        }
    }

    reg.singletons().get(PrevInput).v_con = v_con;

    return true;
}

const falling = @import("../root.zig");
const c = falling.c;

const ecs = @import("entt");
const Registry = ecs.Registry;

const builtin = @import("builtin");
