var in_position: @Vector(3, f32) addrspace(.input) = undefined;

var out: extern struct {
    position: @Vector(3, f32),
    eye: @Vector(3, f32),
} addrspace(.input) = undefined;

pub const ShaderUniforms = @import("shaders.zig").ShaderUniforms;

const uniforms = @extern(*addrspace(.uniform) const extern struct { view: [4][4]f32, projection: [4][4]f32 }, .{
    .name = "uniforms",
    .decoration = .{
        .descriptor = .{
            .binding = 0,
            .set = 0,
        },
    },
});

pub fn vertexMain() callconv(.spirv_vertex) void {
    gpu.position_out.* = .{ in_position[0], in_position[1], in_position[2], 0 };

    var mat: [4]@Vector(4, f32) = undefined;

    if (true) {
        const view: [4]@Vector(4, f32) = @bitCast(uniforms.view);
        const projection: [4]@Vector(4, f32) = @bitCast(uniforms.projection);

        mat = zmath.mul(projection, view);
    }

    gpu.position_out.* = zmath.mul(mat, gpu.position_out.*);
}

comptime {
    @export(
        &vertexMain,
        .{ .name = "main" },
    );
}

const std = @import("std");
const zmath = @import("zmath");
const gpu = std.gpu;
