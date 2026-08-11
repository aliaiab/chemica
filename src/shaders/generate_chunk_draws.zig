pub extern const global_invocation_id: @Vector(3, i32) addrspace(.input);

export fn main() callconv(.{ .spirv_kernel = .{
    .x = 8,
    .y = 8,
    .z = 8,
} }) void {
    const chunk_pos: @Vector(3, i32) = .{ @intCast(global_invocation_id[0]), @intCast(global_invocation_id[1]), @intCast(global_invocation_id[2]) };

    const heap_index: common.VoxelHeapIndex = @bitCast(spirv_ext.imageFetch(
        common.voxel_chunk_positions_image,
        i32,
        chunk_pos,
    )[0]);

    const neighbours: [6]@Vector(3, i32) = .{
        .{ 0, 1, 0 },
        .{ 0, -1, 0 },
        .{ 0, 0, 1 },
        .{ 0, 0, -1 },
        .{ 1, 0, 0 },
        .{ -1, 0, 0 },
    };

    const vertex_positions_for_face: [6][4]@Vector(3, f32) = .{
        .{
            .{ 0, 16, 0 },
            .{ 16, 16, 0 },
            .{ 0, 16, 16 },
            .{ 16, 16, 16 },
        },
        .{
            .{ 16, 0, 0 },
            .{ 0, 0, 0 },
            .{ 16, 0, 16 },
            .{ 0, 0, 16 },
        },
        .{
            .{ 16, 0, 16 },
            .{ 0, 0, 16 },
            .{ 16, 16, 16 },
            .{ 0, 16, 16 },
        },
        .{
            .{ 0, 0, 0 },
            .{ 16, 0, 0 },
            .{ 0, 16, 0 },
            .{ 16, 16, 0 },
        },
        .{
            .{ 16, 0, 0 },
            .{ 16, 0, 16 },
            .{ 16, 16, 0 },
            .{ 16, 16, 16 },
        },
        .{
            .{ 0, 0, 16 },
            .{ 0, 0, 0 },
            .{ 0, 16, 16 },
            .{ 0, 16, 0 },
        },
    };

    if (@reduce(.And, spirv.global_invocation_id == @Vector(3, u32){ 0, 0, 0 })) {
        out_draws.data[0] = .{
            .count = 0,
            .instance_count = 1,
            .first = 0,
            .base_instance = 0,
        };

        out_bounds.sim_bounds_min = @splat(0xffff);
        out_bounds.sim_bounds_max = @splat(0);
    }

    if (heap_index != .null) {
        const chunk_begin = chunk_pos * @as(@Vector(3, i32), @splat(common.chunk_size));
        const chunk_end = chunk_begin + @as(@Vector(3, i32), @splat(common.chunk_size));
        _ = chunk_end; // autofix

        while (out_draws.data[0].count != 0) {}

        for (neighbours, vertex_positions_for_face) |neighbour_offset, face_verts| {
            const neighbour_pos = chunk_pos + neighbour_offset;

            const neighbour_heap_index: common.VoxelHeapIndex = @bitCast(
                spirv_ext.imageFetch(
                    common.voxel_chunk_positions_image,
                    i32,
                    neighbour_pos,
                )[0],
            );

            if (neighbour_heap_index != .null) {
                var verts = face_verts;

                for (0..verts.len) |i| {
                    verts[i] += @floatFromInt(chunk_begin);
                }

                const vertex_index = atomicAdd(
                    &out_draws.data[0].count,
                    6,
                    .device,
                    .{ .acquire_release = true },
                );

                const face_indices: [6]u32 = .{
                    2, 1, 0, 3, 1, 2,
                };

                for (face_indices, 0..) |index, offset| {
                    out_vertices.data[vertex_index + offset] = .{ verts[index][0], verts[index][1], verts[index][2], 0 };
                }
            }
        }

        _ = atomicMin(
            i32,
            &out_bounds.sim_bounds_min[0],
            chunk_pos[0],
            .device,
            .{ .acquire_release = true },
        );
        _ = atomicMin(
            i32,
            &out_bounds.sim_bounds_min[1],
            chunk_pos[1],
            .device,
            .{ .acquire_release = true },
        );
        _ = atomicMin(
            i32,
            &out_bounds.sim_bounds_min[2],
            chunk_pos[2],
            .device,
            .{ .acquire_release = true },
        );

        _ = atomicMax(
            i32,
            &out_bounds.sim_bounds_max[0],
            chunk_pos[0],
            .device,
            .{ .acquire_release = true },
        );
        _ = atomicMax(
            i32,
            &out_bounds.sim_bounds_max[1],
            chunk_pos[1],
            .device,
            .{ .acquire_release = true },
        );
        _ = atomicMax(
            i32,
            &out_bounds.sim_bounds_max[2],
            chunk_pos[2],
            .device,
            .{ .acquire_release = true },
        );
    }
}

/// Get the type that specifies a coordinate for a SPIR-V image or sampled image.
fn ImageCoordinate(Image: type, Element: type) type {
    const image_info = switch (@typeInfo(Image)) {
        .spirv => |spv| switch (spv) {
            .sampled_image => |sampled_image| @typeInfo(sampled_image).spirv.image,
            .image => |image| image,
            else => @compileError("Expected SPIR-V image or sampled image type, found '" ++ @typeName(Image) ++ "'"),
        },
        else => @compileError("Expected SPIR-V image or sampled image type, found '" ++ @typeName(Image) ++ "'"),
    };
    const dim = switch (image_info.dim) {
        .@"1d" => 1 + @as(u8, @intFromBool(image_info.arrayed)),
        .@"2d" => 2 + @as(u8, @intFromBool(image_info.arrayed)),
        .@"3d", .cube => 3 + @as(u8, @intFromBool(image_info.arrayed)),
    };
    if (dim == 1) return Element else return @Vector(dim, Element);
}

/// Query the dimensions of `image`, with no level of detail.
pub inline fn imageQuerySize(
    image: anytype,
) ImageCoordinate(std.meta.Child(@TypeOf(image)), u32) {
    const Image = switch (@typeInfo(@TypeOf(image))) {
        .pointer => |pointer| pointer.child,
        else => @compileError("Expected a pointer to SPIR-V image type, found '" ++ @typeName(@TypeOf(image)) ++ "'"),
    };

    const image_info = switch (@typeInfo(Image)) {
        .spirv => |spv| switch (spv) {
            .image => |info| info,
            else => @compileError("Expected SPIR-V image type, found '" ++ @typeName(Image) ++ "'"),
        },
        else => @compileError("Expected SPIR-V image type, found '" ++ @typeName(Image) ++ "'"),
    };

    // TODO: Remove this check if dimension is not 1d, 2d, 3d, or cube (in case buffer is added).
    if (!image_info.multisampled and image_info.usage != .unknown and image_info.usage != .storage)
        @compileError("SPIR-V image must be either be multisampled or have an unknown or storage usage");

    const Result = ImageCoordinate(std.meta.Child(@TypeOf(image)), u32);

    return asm volatile (
        \\%loaded_image = OpLoad %Image %image
        \\%ret          = OpImageQuerySize %Result %loaded_image
        : [ret] "" (-> Result),
        : [Image] "t" (Image),
          [image] "" (image),
          [Result] "t" (Result),
    );
}

inline fn atomicAdd(
    ptr: *addrspace(.storage_buffer) u32,
    operand: u32,
    scope: spirv.Scope,
    semantics: spirv.MemorySemantics,
) u32 {
    return asm volatile (
        \\%res = OpAtomicIAdd %Type %pointer %scope %sem %operand
        : [res] "" (-> u32),
        : [Type] "t" (u32),
          [pointer] "" (ptr),
          [scope] "" (@as(u32, @backingInt(scope))),
          [sem] "" (@as(u32, @bitCast(semantics))),
          [operand] "" (operand),
    );
}

inline fn atomicMin(
    comptime T: type,
    ptr: *addrspace(.storage_buffer) T,
    operand: T,
    scope: spirv.Scope,
    semantics: spirv.MemorySemantics,
) T {
    return asm volatile (
        \\%res = OpAtomicSMin %Type %pointer %scope %sem %operand
        : [res] "" (-> T),
        : [Type] "t" (T),
          [pointer] "" (ptr),
          [scope] "" (@as(u32, @backingInt(scope))),
          [sem] "" (@as(u32, @bitCast(semantics))),
          [operand] "" (operand),
    );
}

inline fn atomicMax(
    comptime T: type,
    ptr: *addrspace(.storage_buffer) T,
    operand: T,
    scope: spirv.Scope,
    semantics: spirv.MemorySemantics,
) T {
    return asm volatile (
        \\%res = OpAtomicSMax %Type %pointer %scope %sem %operand
        : [res] "" (-> T),
        : [Type] "t" (T),
          [pointer] "" (ptr),
          [scope] "" (@as(u32, @backingInt(scope))),
          [sem] "" (@as(u32, @bitCast(semantics))),
          [operand] "" (operand),
    );
}

const common = @import("lib").shaders.common;

pub const out_indices = @extern(*addrspace(.storage_buffer) extern struct {
    data: @SpirvType(
        .{ .runtime_array = u16 },
    ),
}, .{
    .name = "out_indices",
    .decoration = .{
        .descriptor = .{
            .binding = 40,
            .set = 0,
        },
    },
});

pub const out_vertices = @extern(*addrspace(.storage_buffer) extern struct {
    data: @SpirvType(
        .{ .runtime_array = @Vector(4, f32) },
    ),
}, .{
    .name = "out_vertices",
    .decoration = .{
        .descriptor = .{
            .binding = 41,
            .set = 0,
        },
    },
});

pub const out_draws = @extern(*addrspace(.storage_buffer) extern struct {
    data: @SpirvType(
        .{ .runtime_array = DrawArraysIndirectCommand },
    ),
}, .{
    .name = "out_draws",
    .decoration = .{
        .descriptor = .{
            .binding = 42,
            .set = 0,
        },
    },
});

pub const out_bounds = @extern(*addrspace(.storage_buffer) extern struct {
    sim_bounds_min: [3]i32,
    pad0: i32,
    sim_bounds_max: [3]i32,
    pad1: i32,
}, .{
    .name = "out_bounds",
    .decoration = .{
        .descriptor = .{
            .binding = 43,
            .set = 0,
        },
    },
});

const DrawArraysIndirectCommand = extern struct {
    count: u32,
    instance_count: u32,
    first: u32,
    base_instance: u32,
};

const spirv = @import("std").spirv;
const spirv_ext = @import("spirv_ext.zig");
const std = @import("std");
