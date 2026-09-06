pub fn vertexMain(
    vertex_positions: [*]addrspace(.physical_storage_buffer) const [4]f32,
    simulation_state: *addrspace(.physical_storage_buffer) const common.SimulationState,
    simulation_rendering_state: *addrspace(.physical_storage_buffer) const common.SimulationRenderingState,
    draw_parameters: start.RasterDrawCommandParameters,
) struct { @Vector(4, f32), PipelinePacket } {
    _ = simulation_rendering_state; // autofix
    _ = simulation_state; // autofix
    return .{ vertex_positions[draw_parameters.vertex_index], undefined };
}

pub fn fragmentMain(
    _: *addrspace(.physical_storage_buffer) const [4]f32,
    simulation_state: *addrspace(.physical_storage_buffer) const common.SimulationState,
    simulation_rendering_state: *addrspace(.physical_storage_buffer) const common.SimulationRenderingState,
    input: PipelinePacket,
) @Vector(4, f32) {
    _ = simulation_rendering_state; // autofix
    _ = simulation_state; // autofix
    _ = input; // autofix
    const vos: math.Vec3(f32) = undefined;
    const dir: math.Vec3(f32) = undefined;
    const eye: math.Vec3(f32) = undefined;
    const end_pos: math.Vec3(f32) = undefined;
    _ = end_pos; // autofix
    _ = eye; // autofix
    _ = dir; // autofix
    _ = vos; // autofix

    return @splat(0);
}

const PipelinePacket = extern struct {
    position: @Vector(3, f32),
    eye: @Vector(3, f32),
};

comptime {
    start.exportPipeline(@import("shader_options").shader_module_type);
}

const start = @import("shader_start");
const common = @import("lib").shaders.common;
const GpuPointer = spirv_ext.GpuPointer;
const GpuSlice = spirv_ext.GpuSlice;
const math = @import("lib").math;
const std = @import("std");
const spirv = std.spirv;
const spirv_ext = @import("lib").shaders.spirv_ext;
