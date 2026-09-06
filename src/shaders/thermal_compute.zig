pub fn computeMain(
    data: *addrspace(.physical_storage_buffer) Data,
    simulation_state: *addrspace(.physical_storage_buffer) common.SimulationState,
    params: start.ComputeCommandParameters,
) void {
    const position: [3]i32 = @bitCast(params.global_invocation_id);
    const neighbours = [_][3]i32{
        .{ -1, 0, 0 },
        .{ 1, 0, 0 },
        .{ 0, -1, 0 },
        .{ 0, 1, 0 },
        .{ 0, 0, -1 },
        .{ 0, 0, 1 },
        .{ 1, 1, 0 },
        .{ 0, 1, 1 },
        .{ 1, 0, 1 },
        .{ -1, -1, 0 },
        .{ 0, -1, -1 },
        .{ -1, 0, -1 },
    };

    var temperature_solid_count: u32 = 0;

    const current_temperature = simulation_state.loadVoxelTemperature(position);
    const voxel_material_id = simulation_state.loadVoxelMaterialId(position);
    const voxel_material = simulation_state.loadVoxelMaterial(voxel_material_id);
    const specific_heat_capacity = voxel_material.heat_capacity;
    const voxel_mass = common.ChunkAllocation.voxel_molarity * voxel_material.molar_mass;

    var accumulated_temperature: f32 = 0;
    var heat_diffential: f32 = 0;

    const dt: f32 = 0.016;

    for (neighbours) |neighbour_offset| {
        const neighbour_pos: [3]i32 = .{
            position[0] + neighbour_offset[0],
            position[1] + neighbour_offset[1],
            position[2] + neighbour_offset[2],
        };

        const neighbour_temp = simulation_state.loadVoxelTemperature(neighbour_pos);
        const difference = neighbour_temp - current_temperature;

        const neighbour_id = simulation_state.loadVoxelMaterialId(neighbour_pos);

        if (neighbour_id == .air) {
            continue;
        }

        const neighbour_material = simulation_state.loadVoxelMaterial(neighbour_id);

        const conductivity = neighbour_material.heat_conductivity;

        temperature_solid_count += 1;
        accumulated_temperature += neighbour_temp;
        heat_diffential += conductivity * (common.ChunkAllocation.voxel_face_area / common.ChunkAllocation.voxel_side_length) * difference * dt;
    }

    const stefan_boltzmann = 5.67e-8;
    const radiation_rate = stefan_boltzmann * current_temperature * current_temperature * current_temperature * current_temperature * dt;
    const radiation_factor = voxel_material.thermal_emissivity * @as(f32, @floatFromInt(neighbours.len - temperature_solid_count)) * common.ChunkAllocation.voxel_face_area;

    if (simulation_state.enable_radiative_cooling) {
        heat_diffential += -radiation_rate * radiation_factor;
    }

    const temperature_differential = (heat_diffential / specific_heat_capacity) / voxel_mass * 0.1;
    const result_temperature = @max(0, current_temperature + temperature_differential);
    _ = result_temperature; // autofix

    data.total_energy = @intCast(@backingInt(simulation_state.loadVoxelMaterialId(position)));
}

pub const Data = extern struct {
    total_energy: i32,
};

comptime {
    start.exportComputePipeline(.{
        .x = 8,
        .y = 8,
        .z = 8,
    });
}

const common = @import("lib").shaders.common;
const start = @import("shader_start");
const std = @import("std");
