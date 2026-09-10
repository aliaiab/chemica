pipeline: *gpu.Pipeline,

pub fn init(
    sampler_heap: []gpu.TextureDescriptor,
    sampler_allocator: gpu.mem.Allocator,
) RendererImGui {
    _ = sampler_allocator; // autofix
    _ = sampler_heap; // autofix
    const self: RendererImGui = .{
        .pipeline = gpu.createRasterVertexPipeline(
            @embedFile("renderer_imgui_vertex.spv"),
            @embedFile("renderer_imgui_fragment.spv"),
            .{
                .color_targets = &.{.{
                    .format = .bgra8_srgb32,
                    .write_mask = 0xff,
                }},
                .depth_format = .depth_stencil_u24_u8,
                .stencil_format = .depth_stencil_u24_u8,
            },
        ),
    };

    return self;
}

pub fn render(
    self: RendererImGui,
    command_buffer: *gpu.CommandBuffer,
    draw_data: *const imgui.DrawData,
    transient_arena: gpu.mem.Allocator,
) void {
    _ = transient_arena; // autofix
    _ = draw_data; // autofix
    gpu.launchRasterDraw(command_buffer, self.pipeline, &.{}, &.{
        .{
            .count = 3,
        },
    }, .{});
}

pub fn vertexMain(
    draw_parameters: gpu_start.RasterDrawCommandParameters,
) struct { @Vector(4, f32), PipelinePacket } {
    const triangle_verts: [3]@Vector(4, f32) = .{
        .{ -0.5, -0.5, 0, 1 },
        .{ 0.5, -0.5, 0, 1 },
        .{ 0, 0.5, 0, 1 },
    };
    return .{ triangle_verts[draw_parameters.vertex_index], undefined };
}

pub fn fragmentMain(
    input: PipelinePacket,
) @Vector(4, f32) {
    _ = input; // autofix

    return @splat(1);
}

const PipelinePacket = extern struct {
    pad: u32 = 0,
};

comptime {
    if (@import("builtin").os.tag == .vulkan) {
        gpu_start.exportPipeline(@import("shader_options").shader_module_type);
    }
}

const gpu_start = @import("shader_start");
const common = @import("lib").shaders.common;
const GpuPointer = spirv_ext.GpuPointer;
const GpuSlice = spirv_ext.GpuSlice;
const math = @import("lib").math;
const spirv = std.spirv;
const spirv_ext = @import("lib").shaders.spirv_ext;

const std = @import("std");
const gpu = @import("gpu.zig");
const imgui = @import("imgui.zig");
const RendererImGui = @This();
