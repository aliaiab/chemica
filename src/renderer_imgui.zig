pipeline_compiler: gpu.pipelines.Compiler,
pipeline: gpu.pipelines.Compiler.PipelineIndex,
font_texture: []gpu.TextureByte,
font_texture_sampler_index: gpu.kernel.SamplerHeap.Index,

pub fn init(
    pipeline_compiler: gpu.pipelines.Compiler,
    sampler_heap: []gpu.TextureDescriptor,
    gpu_gpa: gpu.mem.Allocator,
    sampler_allocator: gpu.mem.Allocator,
) !RendererImGui {
    const io = imgui.getIO();

    var pixel_pointer: [*c]u8 = undefined;
    var width: c_int = 0;
    var height: c_int = 0;
    var out_bytes_per_pixel: c_int = 0;

    imgui.cimgui.ImFontAtlas_GetTexDataAsAlpha8(
        io.Fonts,
        &pixel_pointer,
        &width,
        &height,
        &out_bytes_per_pixel,
    );

    const font_texture = try gpu_gpa.allocTexture(.{
        .format = .r8_unorm8,
        .dimensions = .{ @intCast(width), @intCast(height), 1 },
    });

    const pixel_bytes: []u8 = pixel_pointer[0..@intCast(width * height)];

    const texture_src = try gpu_gpa.allocDupe(u8, pixel_bytes);

    const cmds = gpu.queueStartCommandRecording(.{}, .{});
    defer gpu.queueSubmit(.{}, &.{cmds}, &.{});

    gpu.mem.copyToTexture(
        cmds,
        u8,
        .{
            .dimensions = .{ @intCast(width), @intCast(height), 1 },
            .format = .r8_unorm8,
        },
        font_texture,
        texture_src,
    );

    gpu.barrier(cmds, .transfer, .raster_fragment, .{});

    const self: RendererImGui = .{
        .pipeline = try pipeline_compiler.compileRasterVertexPipeline(pipeline_comptime, .{
            .color_targets = &.{.{
                .format = .bgra8_srgb32,
                .write_mask = 0xff,
            }},
            .depth_format = .depth_stencil_u24_u8,
            .stencil_format = .depth_stencil_u24_u8,
        }),
        .font_texture = font_texture,
        .font_texture_sampler_index = try sampler_allocator.allocTextureDescriptor(
            sampler_heap,
            font_texture,
        ),
        .pipeline_compiler = pipeline_compiler,
    };

    return self;
}

pub fn render(
    self: *RendererImGui,
    io: std.Io,
    commands: *gpu.CommandBuffer,
    draw_data: *const imgui.DrawData,
    transient_arena: gpu.mem.Allocator,
) !void {
    _ = io; // autofix
    const pipeline = self.pipeline_compiler.getPipeline(self.pipeline) orelse return;

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

            commands.setStateScissor(.{
                @intFromFloat(command.ClipRect.x),
                @intFromFloat(command.ClipRect.y),
                @intFromFloat(command.ClipRect.z + command.ClipRect.x),
                @intFromFloat(command.ClipRect.w + command.ClipRect.y),
            });

            commands.launchRasterDrawIndexed(pipeline, &.{
                gpu_projection,
                gpu_vertices.ptr,
                @ptrFromInt(@backingInt(self.font_texture_sampler_index)),
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
    uv: [2]f32,
    color: u32,
};

pub fn vertexKernel(
    projection: *addrspace(gpu.kernel.address_space) const math.Matrix(f32, 4, 4),
    vertices: [*]addrspace(gpu.kernel.address_space) const Vertex,
    sampler_index: gpu.kernel.SamplerHeap.Index,
    draw_parameters: gpu.kernel.RasterDrawCommandParameters,
) struct { [4]f32, PipelinePacket } {
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
            .uv = vertex.uv,
            .sampler_index = sampler_index,
        },
    };
}

const PipelinePacket = extern struct {
    colour: [4]f32,
    uv: [2]f32,
    sampler_index: gpu.kernel.SamplerHeap.Index,
};

pub fn fragmentKernel(
    input: PipelinePacket,
) ?[4]f32 {
    if (false) {
        var sampler_heap: gpu.kernel.SamplerHeap = undefined;
        var texel = sampler_heap.imageSample(
            @fromBackingInt(1),
            input.uv,
        );

        texel[1] = 1;
        texel[2] = 1;
        texel[3] = 1;
    }

    if (input.colour[0] < 0.5) {
        //return null;
    }

    return input.colour;
}

pub const pipeline_comptime = gpu.kernel.exportRasterVertexPipeline(@This(), "vertexKernel", "fragmentKernel", .{});

comptime {
    _ = pipeline_comptime;
}

const math = @import("math.zig");
const gpu = @import("gpu.zig");
const imgui = @import("imgui.zig");
const std = @import("std");
const RendererImGui = @This();
