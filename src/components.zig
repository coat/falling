pub const Position = struct {
    x: f32 = 0,
    y: f32 = 0,
};

pub const InitialPosition = struct {
    x: f32 = 0,
    y: f32 = 0,
};

pub const Velocity = struct {
    x: f32 = 0,
    y: f32 = 0,
};

pub const Size = struct {
    w: f32 = 0,
    h: f32 = 0,
};

pub const Sprite = struct {
    x: f32 = 0,
    y: f32 = 0,
    w: f32 = 0,
    h: f32 = 0,

    flip_x: bool = false,
};

pub const BackgroundSprite = struct {};

pub const SpriteAnimation = struct {
    frames: []Frame,
    frame: usize = 0,
    elapsed: f32 = 0,
    delay: usize = 16,
    loop: bool = true,
    state: State = .pause,

    pub const State = enum {
        reset,
        pause,
        play,
    };
};

pub const Frame = struct {
    sprite: Sprite = .{},
    offset: f32 = 0,
};
