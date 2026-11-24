x: f32,
y: f32,
vel: f32,
health: u8,
pain: u8,
state: State,
state_ticks: u32,
grounded: bool,
input: Input,
prev_y: f32,

pub const size = cell * 2;

pub const run_speed = Game.refSpeed(8);
pub const conveyer_speed = Game.refSpeed(4);
pub const gravity = Game.refAccel(2);
pub const bounce_vel = -Game.refSpeed(13);
pub const foot_inset = Game.refPx(4);

pub const max_health = 12;
pub const hurt_amount = 5;
pub const pain_ticks = Game.refTicks(16);

pub const init: Player = .{
    .x = cell * 7,
    .y = cell * 10,
    .vel = 0,
    .health = max_health,
    .pain = 0,
    .state = .idle,
    .state_ticks = 0,
    .grounded = false,
    .input = .{},
    .prev_y = cell * 10,
};

pub const Input = struct {
    left: bool = false,
    right: bool = false,
};

pub const State = enum { idle, running_left, running_right, falling, falling_left, falling_right };

pub fn at(x: f32, y: f32) Player {
    var p: Player = init;
    p.x = x;
    p.y = y;
    p.prev_y = y;
    return p;
}

pub fn isAlive(self: Player) bool {
    return self.health > 0;
}

pub fn hurt(self: *Player) void {
    self.health -|= hurt_amount;
    self.pain = pain_ticks;
}

pub fn heal(self: *Player) void {
    if (self.health < max_health) self.health += 1;
}

pub fn move(self: *Player) void {
    self.pain -|= 1;
    self.prev_y = self.y;

    if (self.input.left) self.x -= run_speed;
    if (self.input.right) self.x += run_speed;

    self.vel += gravity;
    self.y += self.vel;
}

pub fn feetBefore(self: Player) f32 {
    return self.prev_y + size;
}

pub fn clampToShaft(self: *Player) void {
    self.x = std.math.clamp(self.x, 0, Game.width - size);
}

pub fn updateState(self: *Player) void {
    const left = self.input.left and !self.input.right;
    const right = self.input.right and !self.input.left;

    self.setState(if (self.grounded)
        (if (left) .running_left else if (right) .running_right else .idle)
    else
        (if (left) .falling_left else if (right) .falling_right else .falling));
}

pub fn setState(self: *Player, new: State) void {
    if (self.state == new) {
        self.state_ticks +%= 1;
    } else {
        self.state = new;
        self.state_ticks = 0;
    }
}

pub fn feet(self: Player) f32 {
    return self.y + size;
}

const Player = @This();

const Game = @import("Game.zig");
const cell = Game.cell;

const std = @import("std");
