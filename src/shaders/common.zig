pub const chunk_size = 16;

pub const VoxelHeapIndex = enum(u32) {
    null = 0xffff,
    _,
};

pub const uniforms = @extern(*addrspace(.constant) const @import("shaders.zig").ShaderUniforms, .{
    .name = "uniforms",
    .decoration = .{
        .descriptor = .{
            .binding = 0,
            .set = 0,
        },
    },
});

pub const voxel_chunk_positions_image = @extern(
    *addrspace(.constant) const UImage3D,
    .{
        .name = "voxel_chunk_positions_image",
        .decoration = .{
            .descriptor = .{
                .set = 0,
                .binding = 2,
            },
        },
    },
);

pub const voxel_chunk_positions_sampler = @extern(
    *addrspace(.constant) const USampler3D,
    .{
        .name = "voxel_chunk_positions_sampler",
        .decoration = .{
            .descriptor = .{
                .set = 0,
                .binding = 11,
            },
        },
    },
);

const USampler3D = @SpirvType(.{ .sampled_image = UImage3DSampled });

pub const UImage3DSampled = @SpirvType(.{ .image = .{
    .usage = .{ .sampled = u32 },
    .format = .unknown,
    .dim = .@"3d",
    .depth = .not_depth,
    .arrayed = false,
    .multisampled = false,
    .access = .unknown,
} });

pub const UImage3D = @SpirvType(.{ .image = .{
    .usage = .{ .storage = u32 },
    .format = .r32u,
    .dim = .@"3d",
    .depth = .not_depth,
    .arrayed = false,
    .multisampled = false,
    .access = .unknown,
} });
