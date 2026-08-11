const Vertex = extern struct {
    pos: [3]f32,
    colour: u32,
};
pub extern const vertex_id: u32 addrspace(.input);

pub const draw_id = @extern(*addrspace(.input) u32, .{ .name = "draw_index" });

const out = @extern(
    *addrspace(.output) extern struct {
        position: @Vector(4, f32),
        colour: @Vector(4, f32),
    },
    .{
        .name = "out",
        .decoration = .{
            .location = 0,
        },
    },
);

pub fn vertexMain(
    descriptors: @import("lib").shaders.common.AsymDescriptors,
) @Vector(4, f32) {
    const matrix = descriptors.uniforms.view_projection;

    var triangle_vertices: [3]@Vector(4, f32) = .{
        .{ -0.5, -0.5, 0, 1 },
        .{ 0.5, -0.5, 0, 1 },
        .{ 0, 0.5, 0, 1 },
    };
    const untranslated_vertices = triangle_vertices;

    for (&triangle_vertices) |*vert| {
        vert.* *= @splat(2);
        vert.* += @splat(0);
        vert[2] = 0;
        vert[3] = 1;
    }

    const transform: Mat4 = .{
        .c0 = matrix[0],
        .c1 = matrix[1],
        .c2 = matrix[2],
        .c3 = matrix[3],
    };

    const draw_index = draw_id.*;
    const draw: shaders.common.DrawCommand = descriptors.draws.data[draw_index];
    const transform_index = draw.transforms_begin + gpu.instance_index;
    _ = transform_index; // autofix

    const affine_transform = descriptors.transforms.data[0];
    _ = affine_transform; // autofix
    //triangle_vertices[vertex_id][0] += affine_transform.position[0];

    switch (draw.primitive_type) {
        .circle => {
            out.position = triangle_vertices[vertex_id];
            return triangle_vertices[vertex_id] * @as(@Vector(4, f32), @splat(1));
        },
        .triangle_list_3d => {
            const in_pos = descriptors.vertices.data[vertex_id];

            const out_pos: @Vector(4, f32) = .{ in_pos[0], in_pos[1], in_pos[2], 1 };

            const pos = transform.mulVec(out_pos);

            out.position = untranslated_vertices[vertex_id];
            _ = pos; // autofix

            return triangle_vertices[vertex_id] * @as(@Vector(4, f32), @splat(1));
        },
        else => {
            out.position = untranslated_vertices[vertex_id];
            return triangle_vertices[vertex_id] * @as(@Vector(4, f32), @splat(1));
        },
    }

    return @splat(1);
}

pub export fn main() callconv(.spirv_vertex) void {
    const descriptors = comptime spirv_ext.externBindings(@import("lib").shaders.common.AsymDescriptors);
    gpu.position_out.* = @call(.always_inline, vertexMain, .{descriptors});
}

pub fn Mat4x4(comptime T: type) type {
    return [4]@Vector(4, T);
}

const Mat4 = extern struct {
    c0: @Vector(4, f32),
    c1: @Vector(4, f32),
    c2: @Vector(4, f32),
    c3: @Vector(4, f32),

    pub fn mulVec(a: Mat4, b: @Vector(4, f32)) @Vector(4, f32) {
        const ar0 = a.row(0);
        const ar1 = a.row(1);
        const ar2 = a.row(2);
        const ar3 = a.row(3);
        return .{ @reduce(.Add, ar0 * b), @reduce(.Add, ar1 * b), @reduce(.Add, ar2 * b), @reduce(.Add, ar3 * b) };
    }

    pub fn row(mat: Mat4, ind: comptime_int) @Vector(4, f32) {
        return switch (ind) {
            0 => .{ mat.c0[0], mat.c1[0], mat.c2[0], mat.c3[0] },
            1 => .{ mat.c0[1], mat.c1[1], mat.c2[1], mat.c3[1] },
            2 => .{ mat.c0[2], mat.c1[2], mat.c2[2], mat.c3[2] },
            3 => .{ mat.c0[3], mat.c1[3], mat.c2[3], mat.c3[3] },
            else => @compileError("Invalid row number"),
        };
    }
};

const std = @import("std");
const zmath = shaders.zmath;
const shaders = @import("lib").shaders;
const spirv_ext = @import("spirv_ext.zig");
const gpu = std.spirv;
