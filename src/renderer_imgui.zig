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
) !void {
    var vertex_count: usize = 0;
    var index_count: usize = 0;

    for (0..@intCast(draw_data.CmdListsCount)) |command_index| {
        const command_list: *imgui.cimgui.ImDrawList = draw_data.CmdLists.Data[command_index];

        const vertices: []Vertex = @ptrCast(command_list.VtxBuffer.Data[0..@as(usize, @intCast(command_list.VtxBuffer.Size))]);
        const indices: []u16 = command_list.IdxBuffer.Data[0..@as(usize, @intCast(command_list.IdxBuffer.Size))];
        vertex_count += vertices.len;
        index_count += indices.len;
    }

    const gpu_vertices = try transient_arena.alloc(Vertex, vertex_count, .gpu_cpu_writable);
    const gpu_indices = try transient_arena.alloc(u16, index_count, .gpu_cpu_writable);

    const gpu_projection = try transient_arena.create([4][4]f32, .gpu_cpu_writable);
    const gpu_projection_cpu = gpu.mem.toAccessiblePointer(gpu_projection, .cpu);

    gpu_projection_cpu.* = [4][4]f32{
        .{ 2.0, 0.0, 0.0, 0.0 },
        .{ 0.0, -2.0, 0.0, 0.0 },
        .{ 0.0, 0.0, -1.0, 0.0 },
        .{ -1.0, 1.0, 0.0, 1.0 },
    };
    gpu_projection_cpu[0][0] /= @as(f32, @floatFromInt(640));
    gpu_projection_cpu[1][1] /= @as(f32, @floatFromInt(480));

    var vertex_start: usize = 0;
    var index_start: usize = 0;

    for (0..@intCast(draw_data.CmdListsCount)) |command_list_index| {
        const command_list: *imgui.cimgui.ImDrawList = draw_data.CmdLists.Data[command_list_index];

        const vertices: []Vertex = @ptrCast(command_list.VtxBuffer.Data[0..@as(usize, @intCast(command_list.VtxBuffer.Size))]);
        const indices: []u16 = command_list.IdxBuffer.Data[0..@as(usize, @intCast(command_list.IdxBuffer.Size))];

        @memcpy(gpu.mem.toAccessibleSlice(gpu_vertices[vertex_start .. vertex_start + vertices.len], .cpu), vertices);
        @memcpy(gpu.mem.toAccessibleSlice(gpu_indices[index_start .. index_start + indices.len], .cpu), indices);

        for (0..@intCast(command_list.CmdBuffer.Size)) |command_index| {
            const command: imgui.cimgui.ImDrawCmd = command_list.CmdBuffer.Data[command_index];

            gpu.launchRasterDrawIndexed(command_buffer, self.pipeline, &.{
                gpu_projection,
                gpu_vertices.ptr,
            }, &.{
                .{
                    .index_count = @intCast(command.ElemCount),
                    .index_start = @intCast(index_start + command.IdxOffset),
                    .vertex_offset = @intCast(vertex_start + command.VtxOffset),
                },
            }, @ptrCast(gpu_indices));
        }

        vertex_start += vertices.len;
        index_start += indices.len;
    }
}

pub const Vertex = extern struct {
    position: [2]f32,
    uv: [2]u32,
    color: u32,
};

pub fn vertexMain(
    projection: *addrspace(gpu_start.address_space) math.Matrix(f32, 4, 4),
    vertices: [*]addrspace(gpu_start.address_space) Vertex,
    draw_parameters: gpu_start.RasterDrawCommandParameters,
) struct { @Vector(4, f32), PipelinePacket } {
    _ = projection; // autofix
    const vertex = vertices[draw_parameters.vertex_index];

    var vertex4: math.Vec4(f32) = .{ .x = vertex.position[0], .y = vertex.position[1], .z = 0, .w = 1 };

    const Color = packed struct(u32) {
        r: u8,
        g: u8,
        b: u8,
        a: u8,
    };

    vertex4.x /= 640 / 2;
    vertex4.y /= 480 / 2;
    vertex4.x -= 1;
    vertex4.y -= 1;
    //vertex4 = math.Matrix(f32, 4, 4).mulVec(projection.*, vertex4);
    const color: Color = @bitCast(vertex.color);

    var out_colour: @Vector(4, f32) = .{
        @floatFromInt(color.r),
        @floatFromInt(color.g),
        @floatFromInt(color.b),
        @floatFromInt(color.a),
    };

    out_colour /= @splat(255);

    return .{
        .{ vertex4.x, vertex4.y, vertex4.z, vertex4.w },
        .{
            .colour = out_colour,
        },
    };
}

pub fn fragmentMain(
    input: PipelinePacket,
) @Vector(4, f32) {
    return input.colour;
}

const PipelinePacket = extern struct {
    colour: @Vector(4, f32),
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
