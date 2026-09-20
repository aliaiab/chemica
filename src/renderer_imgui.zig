pipeline_compiler: gpu.pipelines.Compiler,
pipeline: gpu.pipelines.Compiler.PipelineIndex,

pub fn init(
    pipeline_compiler: gpu.pipelines.Compiler,
    sampler_heap: []gpu.TextureDescriptor,
    gpu_gpa: gpu.mem.Allocator,
    sampler_allocator: gpu.mem.Allocator,
) !RendererImGui {
    _ = sampler_heap; // autofix
    _ = gpu_gpa; // autofix
    _ = sampler_allocator; // autofix
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

    const self: RendererImGui = .{
        .pipeline = try pipeline_compiler.compileRasterVertexPipeline(pipeline_comptime, .{
            .color_targets = &.{.{
                .format = .bgra8_srgb32,
                .write_mask = 0xff,
            }},
            .depth_format = .depth_stencil_u24_u8,
            .stencil_format = .depth_stencil_u24_u8,
        }),
        .pipeline_compiler = pipeline_compiler,
    };

    return self;
}

pub fn update(
    self: *RendererImGui,
    commands: *gpu.CommandBuffer,
    draw_data: *const imgui.DrawData,
    sampler_heap: []gpu.TextureDescriptor,
    gpa: gpu.mem.Allocator,
    transient_arena: gpu.mem.Allocator,
    sampler_allocator: gpu.mem.Allocator,
) !void {
    _ = self; // autofix
    var was_texture_updates: bool = false;

    for (0..@intCast(draw_data.Textures.*.Size)) |i| {
        const texture = draw_data.Textures[i].Data[0];

        if (texture.*.Status == imgui.cimgui.ImTextureStatus_WantCreate) {
            std.debug.print("wanna create tex[{}] = {}\n", .{ i, texture.* });
            was_texture_updates = true;

            const width: u32 = @intCast(texture.*.Width);
            const height: u32 = @intCast(texture.*.Height);

            const format: gpu.ImageFormat = imFormatToGpuFormat(texture.*.Format);

            const font_texture = try gpa.allocTexture(.{
                .format = format,
                .dimensions = .{ width, height, 1 },
            });

            const sampler_index = try sampler_allocator.allocTextureDescriptor(
                sampler_heap,
                font_texture,
            );
            texture.*.TexID = @backingInt(sampler_index);
            texture.*.BackendUserData = @ptrFromInt(@backingInt(sampler_index));
            texture.*.Status = imgui.cimgui.ImTextureStatus_OK;

            const pixel_bytes: []u8 = texture.*.Pixels[0..@intCast(width * height)];

            const texture_src = try transient_arena.allocDupe(u8, pixel_bytes);

            gpu.mem.copyToTexture(
                commands,
                u8,
                .{
                    .dimensions = .{ @intCast(width), @intCast(height), 1 },
                    .format = format,
                },
                font_texture,
                texture_src,
            );
        }
    }

    if (was_texture_updates) {
        commands.barrier(.transfer, .raster_fragment, .{ .descriptors = true });
    }
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

    commands.setStateBlend(.alpha_compositing_state);

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
                @intFromFloat(command.ClipRect.z),
                @intFromFloat(command.ClipRect.w),
            });

            var sampler_index: gpu.kernel.SamplerHeap.Index = .null;

            if (command.TexRef._TexData) |tex_data| {
                if (tex_data.*.TexID != 0) {
                    sampler_index = @fromBackingInt(@truncate(tex_data.*.TexID));
                }
            }

            commands.launchRasterDrawIndexed(pipeline, &.{
                @ptrFromInt(@backingInt(sampler_index)),
                gpu.mem.toAccessiblePointer(gpu_projection, .gpu),
                gpu.mem.toAccessiblePointer(gpu_vertices.ptr, .gpu),
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

fn imFormatToGpuFormat(format: imgui.cimgui.ImTextureFormat) gpu.ImageFormat {
    return switch (format) {
        imgui.cimgui.ImTextureFormat_RGBA32 => .rgba8_unorm32,
        imgui.cimgui.ImTextureFormat_Alpha8 => .a8_unorm8,
        else => unreachable,
    };
}

pub const Vertex = extern struct {
    position: [2]f32,
    uv: [2]f32,
    color: u32,
};

pub fn vertexKernel(
    sampler_index: gpu.kernel.SamplerHeap.Index,
    projection: *addrspace(gpu.kernel.address_space) const math.Matrix(f32, 4, 4),
    vertices: [*]addrspace(gpu.kernel.address_space) const Vertex,
    draw_parameters: gpu.kernel.RasterDrawCommandParameters,
) struct { [4]f32, PipelinePacket } {
    _ = sampler_index; // autofix
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
        },
    };
}

const PipelinePacket = extern struct {
    colour: @Vector(4, f32),
    uv: [2]f32,
};

pub fn fragmentKernel(
    sampler: gpu.kernel.SamplerHeap.Index,
    input: PipelinePacket,
    samplers: gpu.kernel.SamplerHeap,
) ?[4]f32 {
    var texel = samplers.imageSample(
        sampler,
        @Vector(4, f32),
        input.uv,
    );
    texel[0] = 1;
    texel[1] = 1;
    texel[2] = 1;

    const res = input.colour * texel;

    return res;
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
