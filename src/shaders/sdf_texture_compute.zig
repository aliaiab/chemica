export fn main() callconv(.{ .spirv_kernel = .{
    .x = 8,
    .y = 8,
    .z = 1,
} }) void {
    const tex_pos = spirv.global_invocation_id;

    const sample_pos_3d: @Vector(3, f32) = @floatFromInt(tex_pos);
    var sample_pos_2d: @Vector(2, f32) = .{ sample_pos_3d[0], sample_pos_3d[1] };
    const image_size: @Vector(2, f32) = @floatFromInt(spirv_ext.imageQuerySize(out_image));
    sample_pos_2d /= image_size;
    sample_pos_2d -= @splat(0.5);
    sample_pos_2d *= @splat(100);

    if (true) {
        const field = sdf.evaluate(
            .storage_buffer,
            &sdf.elements_buffer.data,
            &sdf.elemnents_transform_buffer.data,
            &sdf.elmements_bounds_buffer.data,
            &sdf.elements_params_buffer.data,
            @enumFromInt(common.uniforms.sdf_texture_root),
            @splat(-100),
            @splat(100),
            .{ sample_pos_2d[0], sample_pos_2d[1], 0 },
        );

        if (field.sdf_grad.distance < 0) {
            spirv_ext.imageWrite(out_image, u32, .{ tex_pos[0], tex_pos[1] }, .{
                field.sdf_grad.gradient[0],
                field.sdf_grad.gradient[1],
                field.sdf_grad.gradient[2],
                1,
            });
            spirv_ext.imageWrite(out_image, u32, .{ tex_pos[0], tex_pos[1] }, .{ 1, 0, 0, 1 });
        } else {
            spirv_ext.imageWrite(out_image, u32, .{ tex_pos[0], tex_pos[1] }, .{ 0, 0, 0, 1 });
        }
    }
}

const common = @import("lib").shaders.common;

pub const out_image = @extern(
    *addrspace(.constant) const Image2D,
    .{
        .name = "out_image",
        .decoration = .{
            .descriptor = .{
                .set = 0,
                .binding = 5,
            },
        },
    },
);

pub const Image2D = @SpirvType(.{ .image = .{
    .usage = .{ .storage = f32 },
    .format = .rgba8unorm,
    .dim = .@"2d",
    .depth = .not_depth,
    .arrayed = false,
    .multisampled = false,
    .access = .unknown,
} });

const sdf = @import("sdf.zig");
const spirv = std.spirv;
const spirv_ext = @import("spirv_ext.zig");
const std = @import("std");
