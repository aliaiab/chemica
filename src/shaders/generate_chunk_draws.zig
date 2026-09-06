pub fn computeMain(
    vertices: [*]addrspace(het.address_space) [3]f32,
    indices: [*]addrspace(het.address_space) u32,
    simulation_state: *addrspace(het.address_space) common.SimulationState,
    simulation_rendering_state: *addrspace(het.address_space) common.SimulationRenderingState,
    sampler_heap: het.SamplerHeap,
    params: het.ComputeCommandParameters,
) void {
    _ = indices; // autofix
    const chunk_pos: @Vector(3, i32) = @bitCast(params.global_invocation_id);

    const heap_index: common.VoxelHeapIndex = @bitCast(sampler_heap.imageFetch(
        simulation_state.voxel_chunk_positions_sampler,
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

    const out_draws = simulation_rendering_state.draws.toPointerMulti();

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

    if (@reduce(.And, params.global_invocation_id == @Vector(3, u32){ 0, 0, 0 })) {
        out_draws[0] = .{
            .count = 0,
            .instance_count = 1,
            .first = 0,
            .base_instance = 0,
        };

        simulation_state.filled_bounds_min = @splat(0xffff);
        simulation_state.filled_bounds_max = @splat(0);
    }

    if (heap_index != .null) {
        const chunk_begin = chunk_pos * @as(@Vector(3, i32), @splat(common.chunk_size));
        const chunk_end = chunk_begin + @as(@Vector(3, i32), @splat(common.chunk_size));
        _ = chunk_end; // autofix

        while (out_draws[0].count != 0) {}

        for (neighbours, vertex_positions_for_face) |neighbour_offset, face_verts| {
            const neighbour_pos = chunk_pos + neighbour_offset;

            const neighbour_heap_index: common.VoxelHeapIndex = @bitCast(
                sampler_heap.imageFetch(
                    simulation_state.voxel_chunk_positions_sampler,
                    neighbour_pos,
                )[0],
            );

            if (neighbour_heap_index != .null) {
                var verts = face_verts;

                for (0..verts.len) |i| {
                    verts[i] += @floatFromInt(chunk_begin);
                }

                const vertex_index = spirv_ext.atomicAdd(
                    &out_draws[0].count,
                    6,
                    .device,
                    .{ .acquire_release = true },
                );

                const face_indices: [6]u32 = .{
                    2, 1, 0, 3, 1, 2,
                };

                for (face_indices, 0..) |index, offset| {
                    vertices[vertex_index + offset] = .{ verts[index][0], verts[index][1], verts[index][2] };
                }
            }
        }

        _ = spirv_ext.atomicMin(
            i32,
            &simulation_state.filled_bounds_min[0],
            chunk_pos[0],
            .device,
            .{ .acquire_release = true },
        );
        _ = spirv_ext.atomicMin(
            i32,
            &simulation_state.filled_bounds_min[1],
            chunk_pos[1],
            .device,
            .{ .acquire_release = true },
        );
        _ = spirv_ext.atomicMin(
            i32,
            &simulation_state.filled_bounds_min[2],
            chunk_pos[2],
            .device,
            .{ .acquire_release = true },
        );

        _ = spirv_ext.atomicMax(
            i32,
            &simulation_state.filled_bounds_max[0],
            chunk_pos[0],
            .device,
            .{ .acquire_release = true },
        );
        _ = spirv_ext.atomicMax(
            i32,
            &simulation_state.filled_bounds_max[1],
            chunk_pos[1],
            .device,
            .{ .acquire_release = true },
        );
        _ = spirv_ext.atomicMax(
            i32,
            &simulation_state.filled_bounds_max[2],
            chunk_pos[2],
            .device,
            .{ .acquire_release = true },
        );
    }
}

comptime {
    het.exportComputePipeline(.{
        .x = 8,
        .y = 8,
        .z = 8,
    });
}

const DrawArraysIndirectCommand = extern struct {
    count: u32,
    instance_count: u32,
    first: u32,
    base_instance: u32,
};

const het = @import("shader_start");
const common = @import("lib").shaders.common;
const spirv = @import("std").spirv;
const spirv_ext = @import("lib").shaders.spirv_ext;
const std = @import("std");
