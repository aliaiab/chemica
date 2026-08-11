pub const zmath = @import("zmath");
pub const math = @import("math.zig");
pub const shaders = @import("shaders/shaders.zig");

test {
    _ = std.testing.refAllDecls(@This());
}

const std = @import("std");
