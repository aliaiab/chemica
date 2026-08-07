pub const zmath = @import("zmath");
pub const math = @import("math.zig");

test {
    _ = std.testing.refAllDecls(@This());
}

const std = @import("std");
