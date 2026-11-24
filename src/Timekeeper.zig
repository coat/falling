//! Facilitates updating the game logic at a fixed rate. Inspired
//! <https://github.com/TylerGlaiel/FrameTimingControl> and the linked article.
//! Taken from
//! <https://github.com/castholm/zig-examples/blob/master/breakout/main.zig>
const Timekeeper = @This();
const updates_per_s = @import("falling").Game.tick_rate;
const max_accumulated_updates = 8;
const snap_frame_rates = .{ updates_per_s, 30, 120, 144 };
const ticks_per_tock = 720; // Least common multiple of 'snap_frame_rates'
const snap_tolerance_us = 200;
const us_per_s = 1_000_000;

tocks_per_s: u64,
accumulated_ticks: u64 = 0,
previous_timestamp: ?u64 = null,

pub fn consume(timekeeper_: *Timekeeper) bool {
    const ticks_per_s: u64 = timekeeper_.tocks_per_s * ticks_per_tock;
    const ticks_per_update: u64 = @divExact(ticks_per_s, updates_per_s);
    if (timekeeper_.accumulated_ticks >= ticks_per_update) {
        timekeeper_.accumulated_ticks -= ticks_per_update;
        return true;
    } else {
        return false;
    }
}

pub fn produce(timekeeper_: *Timekeeper, current_timestamp: u64) void {
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
