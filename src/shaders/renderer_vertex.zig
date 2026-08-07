extern var in_vertex: @Vector(4, f32) addrspace(.input);

const out = @extern(
    *addrspace(.output) extern struct {
        position: @Vector(3, f32),
        eye: @Vector(3, f32),
    },
    .{
        .name = "out",
        .decoration = .{
            .location = 0,
        },
    },
);

pub const ShaderUniforms = @import("shaders.zig").ShaderUniforms;

const uniforms = @extern(*addrspace(.storage_buffer) const ShaderUniforms, .{
    .name = "uniforms",
    .decoration = .{
        .descriptor = .{
            .binding = 0,
            .set = 0,
        },
    },
});

pub const Image = @SpirvType(.{ .image = .{
    .usage = .{ .sampled = f32 },
    .dim = .@"2d",
    .format = .unknown,
    .depth = .not_depth,
    .arrayed = false,
    .multisampled = false,
    .access = .unknown,
} });
pub const SampledImage = @SpirvType(.{ .sampled_image = Image });

pub export fn main() callconv(.spirv_vertex) void {
    const proj: [4]@Vector(4, f32) = @bitCast(uniforms.projection);
    const view: [4]@Vector(4, f32) = @bitCast(uniforms.view);

    const matrix = zmath.mul(proj, view);

    const transform: Mat4 = .{
        .c0 = matrix[0],
        .c1 = matrix[1],
        .c2 = matrix[2],
        .c3 = matrix[3],
    };

    const out_pos: @Vector(4, f32) = in_vertex;

    gpu.position_out.* = transform.mulVec(out_pos);
}

pub fn Mat4x4(comptime T: type) type {
    return [4]@Vector(4, T);
}

// pub fn mulMat(
//     lhs: Mat4x4(f32),
//     rhs: Mat4x4(f32),
// ) [4]@Vector(4, f32) {
//     const mat = asm volatile (
//         \\%MatrixType = OpTypeMatrix %ColumnType 4
//         \\%lhs_val = OpLoad %MatrixType %lhs
//         \\%rhs_val = OpLoad %MatrixType %rhs
//         \\%val        = OpMatrixTimesMatrix %MatrixType %lhs %rhs
//         \\%ret = OpAccessChain
//         : [ret] "" (-> (*Mat4x4(f32))),
//         : [Image] "t" (Image),
//           [ColumnType] "t" (@Vector(4, f32)),
//           [lhs] "" (&lhs),
//           [rhs] "" (&rhs),
//           [Result] "t" (Mat4x4(f32)),
//     );

//     return mat.*;
// }

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
const shaders = @import("shader_lib");
const gpu = std.spirv;
