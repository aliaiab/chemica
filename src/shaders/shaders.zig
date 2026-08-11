pub const ShaderUniforms = common.ShaderUniforms;
pub const AffineTransform3D = common.AffineTransform3D;
pub const RendererViewType = common.RendererViewType;

pub const common = @import("common.zig");

test {
    _ = std.testing.refAllDecls(@This());
}

const zmath = @import("lib").zmath;
const math = @import("lib").math;
const std = @import("std");
