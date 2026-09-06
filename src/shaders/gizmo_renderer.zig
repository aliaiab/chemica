pub fn vertexMain(
    draw_parameters: start.RasterDrawCommandParameters,
) struct { @Vector(4, f32), PipelinePacket } {
    _ = draw_parameters; // autofix
    return .{ @splat(0), undefined };
}

pub fn fragmentMain(
    input: PipelinePacket,
) @Vector(4, f32) {
    _ = input; // autofix

    return @splat(0);
}

const PipelinePacket = extern struct {};

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
