pub const Simulation = switch (@import("builtin").os.tag) {
    .macos => @import("gpu/metal.zig").Simulation,
    else => if (!use_vulkan) @import("gpu/opengl.zig").Simulation else @import("gpu/vulkan.zig").Simulation,
};

pub const Texture = opaque {};

pub const Context = switch (@import("builtin").os.tag) {
    .macos => @import("gpu/metal.zig").Context,
    else => if (!use_vulkan) @import("gpu/opengl.zig").Context else @import("gpu/vulkan.zig").Context,
};

pub const use_vulkan = true;
