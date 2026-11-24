//! The falling game as a library
pub const Game = @import("Game.zig");
pub const Player = @import("Player.zig");
pub const Platform = @import("Platform.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
// pub const c = @import("c");
// pub const options = @import("options");
//
// pub inline fn errify(value: anytype) error{SdlError}!switch (@typeInfo(@TypeOf(value))) {
//     .bool => void,
//     .pointer, .optional => @TypeOf(value.?),
//     .int => |info| switch (info.signedness) {
//         .signed => @TypeOf(@max(0, value)),
//         .unsigned => @TypeOf(value),
//     },
//     else => @compileError("unerrifiable type: " ++ @typeName(@TypeOf(value))),
// } {
//     return switch (@typeInfo(@TypeOf(value))) {
//         .bool => if (!value) error.SdlError,
//         .pointer, .optional => value orelse error.SdlError,
//         .int => |info| switch (info.signedness) {
//             .signed => if (value >= 0) @max(0, value) else error.SdlError,
//             .unsigned => if (value != 0) value else error.SdlError,
//         },
//         else => comptime unreachable,
//     };
// }
//
// const std = @import("std");
// const Io = std.Io;
