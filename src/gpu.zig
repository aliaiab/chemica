pub const Simulation = switch (@import("builtin").os.tag) {
    .macos => @import("gpu/metal.zig").Simulation,
    else => @import("gpu/opengl.zig").Simulation,
};

pub const Texture = opaque {};
