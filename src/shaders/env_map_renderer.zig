pub fn vertexMain(
    draw_parameters: kernel.RasterDrawCommandParameters,
) struct { @Vector(4, f32), PipelinePacket } {
    const vertex_positions = [36]@Vector(3, f32){
        .{ 0.0, 0.0, 0.0 },
        .{ 1.0, 1.0, 0.0 },
        .{ 1.0, 0.0, 0.0 },
        .{ 1.0, 1.0, 0.0 },
        .{ 0.0, 0.0, 0.0 },
        .{ 0.0, 1.0, 0.0 },
        .{ 0.0, 0.0, 1.0 },
        .{ 1.0, 0.0, 1.0 },
        .{ 1.0, 1.0, 1.0 },
        .{ 1.0, 1.0, 1.0 },
        .{ 0.0, 1.0, 1.0 },
        .{ 0.0, 0.0, 1.0 },
        .{ 0.0, 1.0, 1.0 },
        .{ 0.0, 1.0, 0.0 },
        .{ 0.0, 0.0, 0.0 },
        .{ 0.0, 0.0, 0.0 },
        .{ 0.0, 0.0, 1.0 },
        .{ 0.0, 1.0, 1.0 },
        .{ 1.0, 1.0, 1.0 },
        .{ 1.0, 0.0, 0.0 },
        .{ 1.0, 1.0, 0.0 },
        .{ 1.0, 0.0, 0.0 },
        .{ 1.0, 1.0, 1.0 },
        .{ 1.0, 0.0, 1.0 },
        .{ 0.0, 0.0, 0.0 },
        .{ 1.0, 0.0, 0.0 },
        .{ 1.0, 0.0, 1.0 },
        .{ 1.0, 0.0, 1.0 },
        .{ 0.0, 0.0, 1.0 },
        .{ 0.0, 0.0, 0.0 },
        .{ 0.0, 1.0, 0.0 },
        .{ 1.0, 1.0, 1.0 },
        .{ 1.0, 1.0, 0.0 },
        .{ 1.0, 1.0, 1.0 },
        .{ 0.0, 1.0, 0.0 },
        .{ 0.0, 1.0, 1.0 },
    };

    var vertex_pos = vertex_positions[draw_parameters.vertex_index];

    vertex_pos -= @splat(0.5);

    const output_vertex: @Vector(4, f32) = .{ vertex_pos[0], vertex_pos[1], vertex_pos[2], 1 };

    return .{ output_vertex, undefined };
}

pub fn fragmentMain(
    sampler_index: kernel.SamplerHeap.Index,
    input: PipelinePacket,
    sampler_heap: kernel.SamplerHeap,
) @Vector(4, f32) {
    _ = sampler_index; // autofix
    _ = sampler_heap; // autofix
    const uv = sampleSphericalMap(input.local_pos);
    _ = uv; // autofix

    return @splat(1);
}

fn sampleSphericalMap(v: @Vector(3, f32)) @Vector(2, f32) {
    if (true) return @splat(0);

    var uv: @Vector(2, f32) = .{
        std.math.atan2(v[2], v[0]),
        std.math.asin(v[1]),
    };
    uv *= @Vector(2, f32){ 0.1591, 0.3183 };
    uv += @splat(0.5);

    return uv;
}

const PipelinePacket = extern struct {
    local_pos: @Vector(3, f32),
};

comptime {
    kernel.exportPipeline(@import("shader_options").shader_module_type);
}

const kernel = @import("shader_start");
const common = @import("lib").shaders.common;
const math = @import("lib").math;
const std = @import("std");
