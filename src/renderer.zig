fn watcherCallback(context: ?*anyopaque, path: [:0]const u8, event: watchers.Event) !void {
    const watcher_context: *WatcherContext = @ptrCast(@alignCast(context.?));

    switch (event) {
        .modified => {
            const shader_query = watcher_context.shaders.getPtr(std.fs.path.stem(path)) orelse return;

            const file_path = try std.Io.Dir.cwd().readFileAlloc(
                watcher_context.io,
                path,
                watcher_context.gpa,
                .unlimited,
            );

            if (std.mem.containsAtLeast(u8, path, 1, ".glsl")) {
                return;
            }

            const actual_file_path = file_path[2 .. file_path.len - 1];

            const file_data = try std.Io.Dir.cwd().readFileAlloc(
                watcher_context.io,
                actual_file_path,
                watcher_context.gpa,
                .unlimited,
            );

            try watcher_context.shader_compile_queue.append(watcher_context.gpa, .{
                .binary = file_data,
                .type = shader_query.type,
                .shader_name = std.fs.path.basename(path),
            });
        },
    }
}

fn watcherThread(watcher: *watchers.Watcher) !void {
    _ = watcher; // autofix
    //try watcher.start(.{});
}

const watchers = @import("watchers.zig");

const WatcherContext = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    shaders: std.StringHashMapUnmanaged(ShaderModule) = .empty,
    shader_compile_queue: std.ArrayList(struct {
        shader_name: []const u8,
        binary: []const u8,
        type: u32,
    }) = .empty,
};

const ShaderModule = struct {
    shader: u32,
    type: u32,
    program_index: u32,
    source_index: u32,
};

const Shaders = struct {
    env_map_shader: *gpu.Pipeline,
    gizmo_shader: *gpu.Pipeline,
};

pub const Context = struct {
    window: *glfw.Window,
    gpu_device: *gpu.Device,
    gpu_gpa: gpu.mem.Allocator,
    gpu_arena_instance: gpu.heap.ArenaAllocator,
    gpu_arena: gpu.mem.Allocator,
    graphics_queue: *gpu.Queue,
    swapchain_texture: *gpu.Texture,
    descriptor_mapping: gpu.DescriptorHeapMapping,
    command_buffer: *gpu.CommandBuffer,
    env_map_texture: *gpu.Texture,
    shaders_watcher: *watchers.Watcher,
    io: std.Io,
    watcher_context: *WatcherContext,
    watcher_thread: std.Thread,
    shaders: *Shaders,
    descriptor_heap: *gpu.DescriptorHeap,
    sampler_heap: *gpu.DescriptorHeap,
    asym_uniforms_buffer: [][2][4][4]f32,
    gizmo_draw_buffer: []asym.geo.DrawCommand,
    gizmo_vertex_buffer: []u8,
    gizmo_uniform_buffer: u32,
    asym_transforms_buffer: []asym.geo.AffineTransform3D,
    asym_materials_buffer: []asym.geo.Material,
    asym_parameters_buffer: []f32,
    asym_grapheme_buffers: []shtmap.Sheetmap,
    asym_grapheme_pigeon_hole_buffers: []@import("lib").shaders.common.asym.GraphemePidgeonHole,
    asym_grapheme_instances_buffer: [][4]f32,
    asym_glyph_metrics_buffer: []@import("lib").shaders.common.asym.GlyphMetric,
    asym_transform_offsets_by_type_buffer: []u32,
    asym_parameter_offsets_by_type_buffer: []u32,

    const shtmap = @import("shaders/sheetmap.zig");

    pub fn init(
        arena: std.mem.Allocator,
        window: *glfw.Window,
        io: std.Io,
    ) !Context {
        var context: Context = undefined;

        context.io = io;
        context.window = window;
        context.shaders_watcher = try arena.create(watchers.Watcher);
        context.watcher_context = try arena.create(WatcherContext);
        context.watcher_context.* = .{
            .io = io,
            .gpa = arena,
        };
        context.shaders_watcher.* = try .init(io, arena);
        context.shaders = try arena.create(Shaders);

        const gpu_device = try gpu.selectDevice(
            .{},
            arena,
        );
        context.gpu_device = gpu_device;

        gpu.setStateDevice(gpu_device);

        context.gpu_gpa = gpu.heap.page_allocator;

        context.shaders_watcher.setCallback(watcherCallback, context.watcher_context);

        var env_map_width: c_int = 0;
        var env_map_height: c_int = 0;
        var env_map_comps: c_int = 0;

        const embedded_environment_map = @embedFile("assets/vintage_measuring_lab_2k.png");

        const env_map_data = stb_image.stbi_load_from_memory(
            embedded_environment_map,
            @intCast(embedded_environment_map.len),
            &env_map_width,
            &env_map_height,
            &env_map_comps,
            0,
        );

        const env_map_des: gpu.TextureDescription = .{
            .dimensions = .{ @intCast(env_map_width), @intCast(env_map_height), 1 },
            .format = .rgb8_unorm24,
        };

        const env_map_mem_desc = gpu.textureMemoryDescription(env_map_des);

        const tex_memory = try context.gpu_gpa.alloc(
            u8,
            env_map_mem_desc.size,
            env_map_mem_desc.memory_type,
        );

        @memcpy(tex_memory, env_map_data[0..@intCast(env_map_width * env_map_height * @sizeOf([3]u8))]);

        const env_map_texture = gpu.createTexture(env_map_des, tex_memory);

        const descriptor_heap_memory_info = gpu.descriptorHeapMemoryDescription(@sizeOf(gpu.TextureDescriptor) * 2048);
        const sampler_descriptor_heap_memory_info = gpu.descriptorHeapMemoryDescription(@sizeOf(gpu.TextureDescriptor) * 2048);

        const descriptor_heap_mem = try context.gpu_gpa.alloc(
            u8,
            descriptor_heap_memory_info.size,
            descriptor_heap_memory_info.memory_type,
        );
        @memset(descriptor_heap_mem, 0);

        const sampler_descriptor_heap_mem = try context.gpu_gpa.alloc(
            u8,
            sampler_descriptor_heap_memory_info.size,
            sampler_descriptor_heap_memory_info.memory_type,
        );
        @memset(sampler_descriptor_heap_mem, 0);

        context.descriptor_heap = try gpu.createDescriptorHeap(descriptor_heap_mem);
        context.sampler_heap = try gpu.createDescriptorHeap(sampler_descriptor_heap_mem);

        _ = gpu.readDescriptorTextureIntoHeap(
            env_map_texture,
            context.sampler_heap,
            9 * @sizeOf(gpu.TextureDescriptor),
        );

        context.asym_uniforms_buffer = try context.gpu_gpa.alloc([2][4][4]f32, 1, .gpu);
        context.gizmo_draw_buffer = try context.gpu_gpa.alloc(asym.geo.DrawCommand, 1024, .gpu);
        context.gizmo_vertex_buffer = try context.gpu_gpa.alloc(u8, 1024, .gpu);
        context.asym_parameters_buffer = try context.gpu_gpa.alloc(f32, 1024, .gpu);
        context.asym_transforms_buffer = try context.gpu_gpa.alloc(asym.geo.AffineTransform3D, 1024, .gpu);
        context.asym_materials_buffer = try context.gpu_gpa.alloc(asym.geo.Material, 1024, .gpu);
        context.asym_grapheme_buffers = try context.gpu_gpa.alloc(shtmap.Sheetmap, 1024, .gpu);
        context.asym_grapheme_pigeon_hole_buffers = try context.gpu_gpa.alloc(@import("lib").shaders.common.asym.GraphemePidgeonHole, 1024, .gpu);
        context.asym_grapheme_instances_buffer = try context.gpu_gpa.alloc([4]f32, 1024, .gpu);
        context.asym_transform_offsets_by_type_buffer = try context.gpu_gpa.alloc(
            u32,
            std.meta.fieldNames(asym.geo.PrimitiveType).len,
            .gpu,
        );
        context.asym_parameter_offsets_by_type_buffer = try context.gpu_gpa.alloc(
            u32,
            std.meta.fieldNames(asym.geo.PrimitiveType).len,
            .gpu,
        );

        const sheetmap_binding = 20;

        _ = shtmap; // autofix

        _ = gpu.readSliceDescriptorIntoHeap(
            context.asym_grapheme_buffers,
            context.descriptor_heap,
            sheetmap_binding * @sizeOf(gpu.TextureDescriptor),
        );
        _ = gpu.readSliceDescriptorIntoHeap(
            context.asym_grapheme_pigeon_hole_buffers,
            context.descriptor_heap,
            (sheetmap_binding + 1) * @sizeOf(gpu.TextureDescriptor),
        );
        _ = gpu.readSliceDescriptorIntoHeap(
            &.{},
            context.descriptor_heap,
            (sheetmap_binding + 2) * @sizeOf(gpu.TextureDescriptor),
        );
        _ = gpu.readSliceDescriptorIntoHeap(
            &.{},
            context.descriptor_heap,
            (sheetmap_binding + 3) * @sizeOf(gpu.TextureDescriptor),
        );
        _ = gpu.readSliceDescriptorIntoHeap(
            &.{},
            context.descriptor_heap,
            (sheetmap_binding + 4) * @sizeOf(gpu.TextureDescriptor),
        );

        const desc_mapping: gpu.DescriptorHeapMapping = .{
            .binding_count = 80,
            .binding_first = 16,
            .heap_offset = 0,
            .heap_array_stride = @sizeOf(gpu.TextureDescriptor),

            .sampler_binding_count = 16,
            .sampler_binding_first = 0,
            .sampler_heap_offset = 0,
            .sampler_heap_array_stride = @sizeOf(gpu.TextureDescriptor),
        };
        context.descriptor_mapping = desc_mapping;

        try context.loadRasterVertexPipeline(
            arena,
            "env_map_vertex.spv",
            "env_map_fragment.spv",
            &context.shaders.env_map_shader,
            desc_mapping,
        );

        try context.loadRasterVertexPipeline(
            arena,
            "asym_vertex.spv",
            "asym_fragment.spv",
            &context.shaders.gizmo_shader,
            desc_mapping,
        );

        try imgui.impl.opengl3.init(.{});
        try imgui.impl.glfw.initForOpenGL(window, .{});

        context.watcher_thread = try std.Thread.spawn(.{}, watcherThread, .{context.shaders_watcher});

        const asym_binding_start = 70;

        _ = gpu.readSliceDescriptorIntoHeap(
            context.asym_uniforms_buffer,
            context.descriptor_heap,
            asym_binding_start * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readSliceDescriptorIntoHeap(
            context.gizmo_draw_buffer,
            context.descriptor_heap,
            (asym_binding_start + 1) * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readSliceDescriptorIntoHeap(
            context.asym_materials_buffer,
            context.descriptor_heap,
            (asym_binding_start + 2) * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readSliceDescriptorIntoHeap(
            context.asym_transforms_buffer,
            context.descriptor_heap,
            (asym_binding_start + 3) * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readSliceDescriptorIntoHeap(
            context.asym_parameters_buffer,
            context.descriptor_heap,
            (asym_binding_start + 4) * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readSliceDescriptorIntoHeap(
            context.gizmo_vertex_buffer,
            context.descriptor_heap,
            (asym_binding_start + 5) * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readSliceDescriptorIntoHeap(
            context.asym_parameter_offsets_by_type_buffer,
            context.descriptor_heap,
            (asym_binding_start + 6) * @sizeOf(gpu.TextureDescriptor),
        );

        return context;
    }

    pub fn deinit(context: Context) void {
        context.shaders_watcher.stop();
        context.watcher_thread.join();
    }

    pub fn beginFrame(
        context: *Context,
    ) void {
        context.command_buffer = gpu.queueStartCommandRecording(context.graphics_queue);

        const command_buffer = context.command_buffer;

        gpu.rasterPassBegin(command_buffer, .{
            .color_attachments = &.{.{
                .texture = context.swapchain_texture,
                .clear = .{ 0, 0, 1, 0 },
            }},
            .depth_attachment = .{
                .texture = context.swapchain_texture,
                .clear = 1,
            },
            .stencil_attachment = .{
                .texture = context.swapchain_texture,
                .clear = 0,
            },
        });

        gpu.setStateDescriptorHeap(command_buffer, context.descriptor_heap);
        gpu.setStateSamplerDescriptorHeap(command_buffer, context.sampler_heap);

        imgui.impl.opengl3.newFrame();

        const framebuffer_size = context.window.getFramebufferSize();

        gpu.setStateViewport(command_buffer, .{
            0,
            0,
            @floatFromInt(framebuffer_size[0]),
            @floatFromInt(framebuffer_size[1]),
        });

        while (context.watcher_context.shader_compile_queue.pop()) |entry| {
            const shader_query = context.watcher_context.shaders.getPtr(entry.shader_name).?;
            _ = shader_query; // autofix

            //context.watcher_context.programs.items[shader_query.program_index].program.* = loadShaderProgramRuntime(
            //    context,
            //    context.watcher_context.gpa,
            //    context.watcher_context.programs.items[shader_query.program_index].sources,
            //) catch unreachable;
        }
    }

    pub fn endFrame(
        context: Context,
    ) void {
        const command_buffer = context.command_buffer;
        gpu.rasterPassEnd(command_buffer);
        gpu.queueEndCommandRecording(command_buffer);
    }

    const asym = @import("asym.zig");

    fn printableAscii() []const u21 {
        var ret: []const u21 = &.{};
        for (32..127) |i| ret = ret ++ [_]u21{@intCast(i)};
        return ret;
    }

    pub fn loadTypeFaceTextureFromTTF(
        context: *Context,
        gpa: std.mem.Allocator,
        io: std.Io,
        geo_ctx: *const asym.geo.Context,
        typeface_handle: asym.geo.TextTypeFaceHandle,
        typeface_ttf: []const u8,
    ) !?*Texture {
        _ = io; // autofix
        const Generator = @import("msdf-zig");

        var gen: Generator = try .create(typeface_ttf);

        const sdf_type: Generator.SdfType = .mtsdf;

        const opts: Generator.Options = .{
            .sdf_type = sdf_type,
            .px_size = 64,
            .px_range = 8,
            .coloring_rng_seed = 0,
            .validate_shape = true,
            .normalize_shape = true,
            .orient_contours = true,
        };

        const typeface = geo_ctx.type_faces.items[@backingInt(typeface_handle)];

        const printable_ascii = comptime printableAscii();
        var sdfs: []?Generator.GeneratedGlyph = try gpa.alloc(?Generator.GeneratedGlyph, typeface.codepoints_to_glyph.count());
        defer gpa.free(sdfs);

        @memset(sdfs, null);

        const glyph_metrics = try gpa.alloc(@import("lib").shaders.common.asym.GlyphMetric, typeface.codepoints_to_glyph.count());
        defer gpa.free(glyph_metrics);

        @memset(glyph_metrics, .{});

        var max_width: u32 = 0;
        var max_height: u32 = 0;

        for (printable_ascii) |codepoint| {
            const data = try gen.generateSingle(gpa, codepoint, &opts);

            max_width = @max(max_width, data.metrics.width);
            max_height = @max(max_height, data.metrics.height);

            const glyph_index = typeface.codepoints_to_glyph.getIndex(codepoint).?;
            sdfs[glyph_index] = data;
        }

        const texture_handle, const texture_mem = try context.gpu_gpa.allocTexture(
            .{
                .dimensions = .{ max_width, max_height, @intCast(typeface.codepoints_to_glyph.count()) },
                .type = .array_2d,
            },
        );

        const commands = gpu.queueStartCommandRecording(context.graphics_queue);

        for (sdfs, glyph_metrics, 0..) |*maybe_data, *metrics, glyph_index| {
            if (maybe_data.* == null) {
                continue;
            }

            const data = maybe_data.*.?;
            defer data.deinit(gpa);

            if (data.pixels.len == 0) {
                continue;
            }
            metrics.width = @floatFromInt(data.metrics.width);
            metrics.height = @floatFromInt(data.metrics.height);
            metrics.advance = @floatCast(data.metrics.advance);
            metrics.bearing_x = @floatCast(data.metrics.bearing_x);
            metrics.bearing_y = @floatCast(data.metrics.bearing_y);

            gpu.mem.copyToTexture(
                commands,
                u8,
                texture_handle,
                .{
                    .offset = .{
                        0,
                        0,
                        @intCast(glyph_index),
                    },
                    .dimensions = .{
                        data.metrics.width,
                        data.metrics.height,
                        1,
                    },
                },
                texture_mem,
                data.pixels,
            );
        }

        context.asym_glyph_metrics_buffer = try context.gpu_gpa.alloc(
            @import("lib").shaders.common.asym.GlyphMetric,
            glyph_metrics.len,
            .gpu,
        );

        const sheetmap_binding = 20;

        _ = gpu.readSliceDescriptorIntoHeap(
            context.asym_glyph_metrics_buffer,
            context.descriptor_heap,
            (sheetmap_binding + 5) * @sizeOf(gpu.TextureDescriptor),
        );

        gpu.mem.copy(
            commands,
            @import("lib").shaders.common.asym.GlyphMetric,
            context.asym_glyph_metrics_buffer,
            glyph_metrics,
        );

        gpu.queueEndCommandRecording(commands);
        gpu.queueSubmit(
            context.graphics_queue,
            &.{commands},
            &.{},
        );

        return texture_handle;
    }

    pub fn renderGizmos(
        context: *Context,
        gpa: std.mem.Allocator,
        geo_context: *const asym.geo.Context,
        scene: *const asym.geo.Scene,
        views: []const asym.geo.Scene.View,
        typeface_textures: []?*Texture,
    ) void {
        const command_buffer = context.command_buffer;

        _ = typeface_textures; // autofix
        gpu.setStatePipeline(command_buffer, context.shaders.gizmo_shader);
        gpu.setStateViewport(
            command_buffer,
            .{ 0, 0, @floatFromInt(context.window.getSize()[0]), @floatFromInt(context.window.getSize()[1]) },
        );
        gpu.setStateScissor(
            command_buffer,
            .{ 0, 0, @intCast(context.window.getSize()[0]), @intCast(context.window.getSize()[1]) },
        );

        var transforms_offset: usize = 0;
        var materials_offset: usize = 0;

        for (scene.transforms_by_type.values, scene.materials_by_type.values, 0..) |transforms, materials, type_index| {
            if (transforms.items.len == 0) {
                continue;
            }

            gpu.mem.copy(
                command_buffer,
                u32,
                context.asym_transform_offsets_by_type_buffer[type_index..],
                &.{@intCast(transforms_offset)},
            );

            gpu.mem.copy(
                command_buffer,
                asym.geo.AffineTransform3D,
                context.asym_transforms_buffer[transforms_offset..],
                transforms.items,
            );

            gpu.mem.copy(
                command_buffer,
                asym.geo.Material,
                context.asym_materials_buffer[materials_offset..],
                materials.items,
            );

            transforms_offset += transforms.items.len;
            materials_offset += materials.items.len;
        }

        for (views) |*view| {
            var iter = view.iterate();

            gpu.setStateScissor(command_buffer, .{
                @intFromFloat(view.scissor[0]),
                @intFromFloat(view.scissor[1]),
                @intFromFloat(view.scissor[2]),
                @intFromFloat(view.scissor[3]),
            });

            const Mat4x4 = [4]@Vector(4, f32);

            const view_projection = zmath.mul(@as(Mat4x4, @bitCast(view.view)), @as(Mat4x4, @bitCast(view.projection)));

            gpu.mem.copy(
                command_buffer,
                [2][4][4]f32,
                context.asym_uniforms_buffer,
                &.{
                    .{
                        @bitCast(view_projection),
                        @splat(@splat(@floatCast(glfw.getTime()))),
                    },
                },
            );

            var text_buffer_entry_begin: usize = 0;

            var draw_buffer_offset: usize = 0;
            var parameter_buffer_offset: usize = 0;

            while (iter.next()) |tuple| {
                const state, const group = tuple;
                _ = state; // autofix

                defer text_buffer_entry_begin += group.draws_by_type.get(.text).len;

                var quadrat_buffer_begin: usize = 0;

                for (group.draws_by_type.get(.text), 0..) |draws, draw_command_index| {
                    for (0..draws.instance_count) |instance_id| {
                        const draw_index = draw_command_index + instance_id;
                        const text_buffer = scene.text_buffer_entires.items[text_buffer_entry_begin + draw_index];

                        var line_iter: std.mem.SplitIterator(u8, .sequence) = .{
                            .delimiter = "\n",
                            .buffer = text_buffer,
                            .index = 0,
                        };

                        const typeface_data = &geo_context.type_faces.items[0];

                        var grapheme_buffer_height: u32 = 0;
                        var grapheme_buffer_width: u32 = 0;

                        while (line_iter.next()) |line| {
                            grapheme_buffer_width = @max(grapheme_buffer_width, @as(u32, @intCast(line.len)));
                            grapheme_buffer_height += 1;
                        }

                        line_iter.reset();

                        const GraphemeBin = @import("lib").shaders.common.asym.GraphemePidgeonHole;

                        const grapheme_buffer_bins = gpa.alloc(GraphemeBin, grapheme_buffer_width * grapheme_buffer_height) catch @panic("oom");
                        defer gpa.free(grapheme_buffer_bins);
                        var line_index: u32 = 0;

                        while (line_iter.next()) |line| {
                            defer line_index += 1;

                            for (line, 0..) |char, column_index| {
                                const bin = &grapheme_buffer_bins[column_index + line_index * grapheme_buffer_width];

                                const glyph_index: u16 = @intCast(typeface_data.codepoints_to_glyph.getIndex(char).?);
                                bin.grapheme_slice = @bitCast(@as(u32, glyph_index));
                                if (char == ' ') {
                                    bin.grapheme_slice = @bitCast(@as(u32, std.math.maxInt(u32)));
                                }
                            }
                        }

                        gpu.mem.copy(
                            command_buffer,
                            shtmap.Sheetmap,
                            context.asym_grapheme_buffers[draw_index..],
                            &.{
                                shtmap.Sheetmap{
                                    .quadrat_buffer_begin = @intCast(quadrat_buffer_begin),
                                    .width = grapheme_buffer_width,
                                    .height = grapheme_buffer_height,
                                },
                            },
                        );

                        gpu.mem.copy(
                            command_buffer,
                            GraphemeBin,
                            context.asym_grapheme_pigeon_hole_buffers[quadrat_buffer_begin..],
                            grapheme_buffer_bins,
                        );

                        quadrat_buffer_begin += grapheme_buffer_bins.len * @sizeOf(GraphemeBin);
                    }
                }

                for (group.draws_by_type.values, group.parameters_by_type.values, 0..) |
                    draws,
                    params,
                    type_index,
                | {
                    if (draws.len == 0) {
                        continue;
                    }

                    gpu.mem.copySingle(
                        command_buffer,
                        u32,
                        &context.asym_parameter_offsets_by_type_buffer[type_index],
                        &@intCast(parameter_buffer_offset),
                    );

                    gpu.mem.copy(
                        command_buffer,
                        f32,
                        context.asym_parameters_buffer[parameter_buffer_offset..],
                        params,
                    );

                    gpu.mem.copy(
                        command_buffer,
                        asym.geo.DrawCommand,
                        context.gizmo_draw_buffer[draw_buffer_offset..],
                        draws,
                    );

                    draw_buffer_offset += draws.len;
                    parameter_buffer_offset += params.len;
                }

                gpu.setStateBlend(command_buffer, .{});
                gpu.setStateDepthStencil(command_buffer, .{});

                gpu.dispatchRasterDraw(
                    command_buffer,
                    @as([*]gpu.RasterDrawCommand, @ptrCast(context.gizmo_draw_buffer.ptr))[0 .. context.gizmo_draw_buffer.len / 2],
                    .{
                        .command_stride = @sizeOf(asym.geo.DrawCommand),
                        .command_offset = draw_buffer_offset * @sizeOf(asym.geo.DrawCommand),
                    },
                );
            }
        }
    }

    pub fn loadRasterVertexPipeline(
        context: *Context,
        arena: std.mem.Allocator,
        comptime vertex_ir_path: []const u8,
        comptime fragment_ir_path: []const u8,
        pipeline: **gpu.Pipeline,
        descriptor_mapping: gpu.DescriptorHeapMapping,
    ) !void {
        _ = context; // autofix
        _ = arena; // autofix
        pipeline.* = gpu.createRasterVertexPipeline(
            @embedFile(vertex_ir_path),
            @embedFile(fragment_ir_path),
            descriptor_mapping,
            .{},
        );
    }

    pub fn loadComputePipeline(
        context: *Context,
        arena: std.mem.Allocator,
        comptime compute_path: []const u8,
        pipeline: **gpu.Pipeline,
        descriptor_mapping: gpu.DescriptorHeapMapping,
    ) !void {
        _ = context; // autofix
        _ = arena; // autofix
        pipeline.* = gpu.createComputePipeline(
            @embedFile(compute_path),
            descriptor_mapping,
        );
    }
};

pub const Simulation = struct {
    vertex_buffer: []u8 = undefined,

    simulation_vertex_buffer: [][4]f32 = undefined,
    simulation_draws_buffer: []gpu.RasterDrawCommand = undefined,
    simulation_bounds_buffer: [][4]u32 = undefined,

    simulation_material_buffer: []u16 = undefined,
    simulation_deviation_buffer: []i8 = undefined,
    simulation_temperature_buffer: []f32 = undefined,

    ray_stats_buffer: *RayStats = undefined,

    heat_measurement_buffer: *f32 = undefined,

    voxel_materials_buffer: []VoxelMaterial = undefined,
    voxel_materials_visual_buffer: []VoxelMaterialVisual = undefined,

    shaders: *SimShaders,

    point_light_buffer: []PointLight = undefined,

    uniform_buffer: *ShaderUniforms = undefined,

    sdf_elements_3d_buffer: []SdfElement3D = undefined,
    sdf_elements_3d_transforms_buffer: []AffineTransform3D = undefined,
    sdf_elements_3d_params_buffer: []f32 = undefined,
    sdf_elements_3d_bounds_buffer: [][4]f32 = undefined,

    csg_composite_material_buffer: []u8 = undefined,

    voxel_allocator_bins_buffer: *VoxelAllocatorBins = undefined,
    voxel_pallete_memory_buffer: []u16 = undefined,
    voxel_pallete_counters_buffer: []u16 = undefined,
    voxel_bit_buffer_memory_buffer: []u32 = undefined,
    voxel_temperature_memory_buffer: []f32 = undefined,
    voxel_allocator_buffer: []VoxelChunkAllocator = undefined,
    voxel_chunks_buffer: []VoxelChunksAllocation = undefined,

    voxel_bit_buffer_memory_texture: *Texture = undefined,
    voxel_chunk_allocations_texture: *Texture = undefined,
    voxel_chunk_positions_texture: *Texture = undefined,

    voxel_heap_bit_buffer: []u32 = undefined,
    voxel_positions_buffer: []u32 = undefined,

    scene_thumbnails: std.StringHashMapUnmanaged(?*Texture) = .empty,
    scene_2d_texture: ?*Texture = null,
    scene_2d_texture_width: u32 = 0,
    scene_2d_texture_height: u32 = 0,

    simulation_read_offset: u32 = 0,
    simulation_write_offset: u32 = 0,

    command_buffer: *gpu.CommandBuffer = undefined,

    const SimShaders = struct {
        renderer_program: *gpu.Pipeline = undefined,
        simulation_shader: *gpu.Pipeline = undefined,
        thermal_shader: *gpu.Pipeline = undefined,
        grain_simulation_shader: *gpu.Pipeline = undefined,
        fill_region_shader: *gpu.Pipeline = undefined,
        generate_chunk_draws: *gpu.Pipeline = undefined,
        gizmo_shader: *gpu.Pipeline = undefined,
        depth_prepass_shader: *gpu.Pipeline = undefined,
        bounds_depth_prepass_shader: *gpu.Pipeline = undefined,
        raymarched_sdf_shader: *gpu.Pipeline = undefined,
        sdf_texture_compute: *gpu.Pipeline = undefined,

        old_fill_region_shader: *gpu.Pipeline = undefined,
    };

    pub fn init(
        context: *Context,
        sim: @import("Simulation.zig"),
        arena: std.mem.Allocator,
    ) !Simulation {
        var gpu_sim: Simulation = .{
            .shaders = try arena.create(SimShaders),
        };
        gpu_sim.command_buffer = context.command_buffer;

        try context.loadRasterVertexPipeline(
            arena,
            "renderer_vertex.spv",
            "renderer_fragment.spv",
            &gpu_sim.shaders.renderer_program,
            context.descriptor_mapping,
        );

        try context.loadComputePipeline(
            arena,
            "thermal_compute.spv",
            &gpu_sim.shaders.thermal_shader,
            context.descriptor_mapping,
        );
        try context.loadComputePipeline(
            arena,
            "grain_simulation.spv",
            &gpu_sim.shaders.grain_simulation_shader,
            context.descriptor_mapping,
        );
        gpu_sim.shaders.simulation_shader = gpu_sim.shaders.grain_simulation_shader;
        try context.loadComputePipeline(
            arena,
            "fill_region.spv",
            &gpu_sim.shaders.fill_region_shader,
            context.descriptor_mapping,
        );
        try context.loadComputePipeline(
            arena,
            "generate_chunk_draws.spv",
            &gpu_sim.shaders.generate_chunk_draws,
            context.descriptor_mapping,
        );
        try context.loadComputePipeline(
            arena,
            "sdf_texture_compute.spv",
            &gpu_sim.shaders.sdf_texture_compute,
            context.descriptor_mapping,
        );
        try context.loadRasterVertexPipeline(
            arena,
            "gizmo_shader_vertex.spv",
            "gizmo_shader_fragment.spv",
            &gpu_sim.shaders.gizmo_shader,
            context.descriptor_mapping,
        );

        try context.loadRasterVertexPipeline(
            arena,
            "gizmo_shader_vertex.spv",
            "depth_prepass_fragment.spv",
            &gpu_sim.shaders.depth_prepass_shader,
            context.descriptor_mapping,
        );

        try context.loadRasterVertexPipeline(
            arena,
            "renderer_vertex.spv",
            "depth_prepass_fragment.spv",
            &gpu_sim.shaders.bounds_depth_prepass_shader,
            context.descriptor_mapping,
        );

        try context.loadRasterVertexPipeline(
            arena,
            "renderer_vertex.spv",
            "sdf_renderer_fragment.spv",
            &gpu_sim.shaders.raymarched_sdf_shader,
            context.descriptor_mapping,
        );

        gpu_sim.scene_2d_texture, _ = try context.gpu_gpa.allocTexture(.{
            .type = .@"2d",
            .dimensions = .{ 512, 512, 1 },
        });
        const buffer_length = sim.width * sim.height * sim.depth;

        gpu_sim.uniform_buffer = try context.gpu_gpa.create(ShaderUniforms, .gpu);
        gpu_sim.simulation_material_buffer = try context.gpu_gpa.alloc(u16, buffer_length * 2, .gpu);
        gpu_sim.simulation_temperature_buffer = try context.gpu_gpa.alloc(f32, buffer_length * 2, .gpu);
        gpu_sim.simulation_deviation_buffer = try context.gpu_gpa.alloc(i8, buffer_length * 2, .gpu);
        gpu_sim.heat_measurement_buffer = try context.gpu_gpa.create(f32, .gpu);
        gpu_sim.sdf_elements_3d_bounds_buffer = try context.gpu_gpa.alloc([4]f32, 1024, .gpu);
        gpu_sim.sdf_elements_3d_buffer = try context.gpu_gpa.alloc(SdfElement3D, 1024, .gpu);
        gpu_sim.sdf_elements_3d_transforms_buffer = try context.gpu_gpa.alloc(AffineTransform3D, 1024, .gpu);
        gpu_sim.sdf_elements_3d_params_buffer = try context.gpu_gpa.alloc(f32, 1024, .gpu);
        gpu_sim.voxel_materials_buffer = try context.gpu_gpa.alloc(VoxelMaterial, sim.voxel_materials.items.len, .gpu);
        gpu_sim.voxel_materials_visual_buffer = try context.gpu_gpa.alloc(VoxelMaterialVisual, sim.voxel_materials_visual.items.len, .gpu);
        gpu_sim.point_light_buffer = try context.gpu_gpa.alloc(PointLight, 128, .gpu);
        gpu_sim.voxel_allocator_bins_buffer = try context.gpu_gpa.create(VoxelAllocatorBins, .gpu);
        gpu_sim.voxel_pallete_memory_buffer = try context.gpu_gpa.alloc(u16, 64 * 64 * 64 * 8, .gpu);
        gpu_sim.voxel_pallete_counters_buffer = try context.gpu_gpa.alloc(u16, 64 * 64 * 64, .gpu);
        gpu_sim.voxel_temperature_memory_buffer = try context.gpu_gpa.alloc(f32, 64 * 64 * 64 * 16, .gpu);
        gpu_sim.voxel_allocator_buffer = try context.gpu_gpa.alloc(VoxelChunkAllocator, 128, .gpu);
        gpu_sim.voxel_chunks_buffer = try context.gpu_gpa.alloc(VoxelChunksAllocation, 64 * 64 * 64, .gpu);
        gpu_sim.voxel_heap_bit_buffer = try context.gpu_gpa.alloc(u32, 16 * 16 * 16 * 16 * 16 * 16, .gpu);
        gpu_sim.voxel_positions_buffer = try context.gpu_gpa.alloc(u32, 16 * 16 * 16, .gpu);
        gpu_sim.simulation_vertex_buffer = try context.gpu_gpa.alloc([4]f32, 10_000, .gpu);
        gpu_sim.simulation_draws_buffer = try context.gpu_gpa.alloc(gpu.RasterDrawCommand, 128, .gpu);
        gpu_sim.simulation_bounds_buffer = try context.gpu_gpa.alloc([4]u32, 2, .gpu);
        gpu_sim.ray_stats_buffer = try context.gpu_gpa.create(RayStats, .gpu);

        const upload_cmds = gpu.queueStartCommandRecording(context.graphics_queue);
        defer gpu.queueSubmit(
            context.graphics_queue,
            &.{upload_cmds},
            &.{},
        );

        gpu.mem.copySingle(
            upload_cmds,
            RayStats,
            gpu_sim.ray_stats_buffer,
            &.{},
        );

        const brick_map_width = 16;

        gpu_sim.voxel_bit_buffer_memory_texture, _ = try context.gpu_gpa.allocTexture(.{
            .type = .@"3d",
            .dimensions = @splat(16 * brick_map_width),
            .format = .r16_u16,
        });

        gpu_sim.voxel_chunk_allocations_texture, _ = try context.gpu_gpa.allocTexture(.{
            .type = .@"3d",
            .dimensions = @splat(brick_map_width),
            .format = .r32_u32,
        });

        gpu_sim.voxel_chunk_positions_texture, _ = try context.gpu_gpa.allocTexture(.{
            .type = .@"3d",
            .dimensions = @splat(brick_map_width),
            .format = .r16_u16,
        });

        _ = gpu.readTextureSliceDescriptorIntoHeap(
            gpu_sim.voxel_bit_buffer_memory_texture,
            .{
                .dimensions = @splat(16 * brick_map_width),
                .mode = .read_write,
            },
            context.sampler_heap,
            0 * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readTextureSliceDescriptorIntoHeap(
            gpu_sim.voxel_chunk_allocations_texture,
            .{
                .dimensions = @splat(brick_map_width),
                .mode = .read_write,
            },
            context.sampler_heap,
            1 * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readTextureSliceDescriptorIntoHeap(
            gpu_sim.voxel_chunk_positions_texture,
            .{
                .dimensions = @splat(brick_map_width),
                .mode = .read_write,
            },
            context.sampler_heap,
            2 * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readDescriptorTextureIntoHeap(
            gpu_sim.voxel_bit_buffer_memory_texture,
            context.sampler_heap,
            5 * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readDescriptorTextureIntoHeap(
            gpu_sim.voxel_chunk_positions_texture,
            context.sampler_heap,
            6 * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readSliceDescriptorIntoHeap(
            gpu_sim.uniform_buffer,
            context.descriptor_heap,
            0 * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readSliceDescriptorIntoHeap(
            gpu_sim.voxel_pallete_counters_buffer,
            context.descriptor_heap,
            1 * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readSliceDescriptorIntoHeap(
            gpu_sim.voxel_temperature_memory_buffer,
            context.descriptor_heap,
            2 * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readSliceDescriptorIntoHeap(
            gpu_sim.voxel_allocator_buffer,
            context.descriptor_heap,
            3 * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readSliceDescriptorIntoHeap(
            gpu_sim.voxel_allocator_bins_buffer,
            context.descriptor_heap,
            4 * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readSliceDescriptorIntoHeap(
            gpu_sim.voxel_allocator_buffer,
            context.descriptor_heap,
            5 * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readSliceDescriptorIntoHeap(
            gpu_sim.voxel_heap_bit_buffer,
            context.descriptor_heap,
            6 * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readSliceDescriptorIntoHeap(
            gpu_sim.voxel_positions_buffer,
            context.descriptor_heap,
            7 * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readSliceDescriptorIntoHeap(
            gpu_sim.voxel_pallete_memory_buffer,
            context.descriptor_heap,
            8 * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readSliceDescriptorIntoHeap(
            gpu_sim.simulation_vertex_buffer,
            context.descriptor_heap,
            10 * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readSliceDescriptorIntoHeap(
            gpu_sim.simulation_draws_buffer,
            context.descriptor_heap,
            11 * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readSliceDescriptorIntoHeap(
            gpu_sim.simulation_bounds_buffer,
            context.descriptor_heap,
            12 * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readSliceDescriptorIntoHeap(
            gpu_sim.simulation_material_buffer,
            context.descriptor_heap,
            13 * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readSliceDescriptorIntoHeap(
            gpu_sim.simulation_temperature_buffer,
            context.descriptor_heap,
            14 * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readSliceDescriptorIntoHeap(
            gpu_sim.simulation_deviation_buffer,
            context.descriptor_heap,
            15 * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readSliceDescriptorIntoHeap(
            gpu_sim.voxel_materials_buffer,
            context.descriptor_heap,
            16 * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readSliceDescriptorIntoHeap(
            gpu_sim.voxel_materials_visual_buffer,
            context.descriptor_heap,
            17 * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readSliceDescriptorIntoHeap(
            gpu_sim.point_light_buffer,
            context.descriptor_heap,
            18 * @sizeOf(gpu.TextureDescriptor),
        );

        //spot lights
        _ = gpu.readSliceDescriptorIntoHeap(
            &.{},
            context.descriptor_heap,
            19 * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readSliceDescriptorIntoHeap(
            gpu_sim.sdf_elements_3d_buffer,
            context.descriptor_heap,
            20 * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readSliceDescriptorIntoHeap(
            gpu_sim.sdf_elements_3d_transforms_buffer,
            context.descriptor_heap,
            21 * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readSliceDescriptorIntoHeap(
            gpu_sim.sdf_elements_3d_params_buffer,
            context.descriptor_heap,
            22 * @sizeOf(gpu.TextureDescriptor),
        );

        _ = gpu.readSliceDescriptorIntoHeap(
            gpu_sim.sdf_elements_3d_bounds_buffer,
            context.descriptor_heap,
            23 * @sizeOf(gpu.TextureDescriptor),
        );

        const voxel_allocator_bins: VoxelAllocatorBins = .{
            .chunk_grid_size = .{ 64, 64, 64 },
        };

        gpu.mem.copySingle(
            upload_cmds,
            VoxelAllocatorBins,
            gpu_sim.voxel_allocator_bins_buffer,
            &voxel_allocator_bins,
        );

        gpu.mem.set(upload_cmds, VoxelChunksAllocation, gpu_sim.voxel_chunks_buffer, .{
            .allocation = std.math.maxInt(u32),
            .bit_count = 0,
        });

        return gpu_sim;
    }

    pub fn deinit() void {}

    pub fn updateCSGProgram(
        gpu_sim: *Simulation,
        sim: @import("Simulation.zig"),
        program: CSGProgram,
    ) !void {
        _ = sim; // autofix

        if (program.elements.items.len != 0) {
            gpu.mem.copy(
                gpu_sim.command_buffer,
                SdfElement3D,
                gpu_sim.sdf_elements_3d_buffer,
                program.elements.items,
            );
        }

        if (program.element_params.items.len != 0) {
            gpu.mem.copy(
                gpu_sim.command_buffer,
                f32,
                gpu_sim.sdf_elements_3d_params_buffer,
                program.element_params.items,
            );
        }

        if (program.transforms.items.len != 0) {
            gpu.mem.copy(
                gpu_sim.command_buffer,
                AffineTransform3D,
                gpu_sim.sdf_elements_3d_transforms_buffer,
                program.transforms.items,
            );
        }

        if (program.element_bounds.items.len != 0) {
            gpu.mem.copy(
                gpu_sim.command_buffer,
                [4]f32,
                gpu_sim.sdf_elements_3d_bounds_buffer,
                program.element_bounds.items,
            );
        }
    }

    pub fn update(gpu_sim: *Simulation, sim: *@import("Simulation.zig"), shader_uniforms: ShaderUniforms) void {
        gpu.mem.copy(
            gpu_sim.command_buffer,
            VoxelMaterial,
            gpu_sim.voxel_materials_buffer,
            sim.voxel_materials.items,
        );

        gpu.mem.copy(
            gpu_sim.command_buffer,
            VoxelMaterialVisual,
            gpu_sim.voxel_materials_visual_buffer,
            sim.voxel_materials_visual.items,
        );

        var upload_uniforms = shader_uniforms;

        upload_uniforms.simulation_read_offset = gpu_sim.simulation_write_offset;
        upload_uniforms.simulation_write_offset = gpu_sim.simulation_read_offset;

        gpu.mem.copySingle(
            gpu_sim.command_buffer,
            ShaderUniforms,
            gpu_sim.uniform_buffer,
            &upload_uniforms,
        );

        gpu.mem.copy(
            gpu_sim.command_buffer,
            PointLight,
            gpu_sim.point_light_buffer,
            sim.point_lights.items,
        );

        if (sim.gpu_sim.shaders.fill_region_shader != sim.gpu_sim.shaders.old_fill_region_shader) {
            sim.csg_dirty = true;
        }

        sim.csg_dirty = true;

        if (!sim.enable_simulation and sim.csg_dirty) {
            gpu.setStatePipeline(gpu_sim.command_buffer, gpu_sim.shaders.fill_region_shader);

            sim.csg_dirty = false;

            gpu.dispatchCompute(
                gpu_sim.command_buffer,
                &.{
                    .{
                        .workgroup_count_x = sim.width / 8,
                        .workgroup_count_y = sim.height / 8,
                        .workgroup_count_z = sim.depth / 8,
                    },
                },
            );
        }

        upload_uniforms.simulation_read_offset = gpu_sim.simulation_read_offset;
        upload_uniforms.simulation_write_offset = gpu_sim.simulation_write_offset;

        gpu.mem.copySingle(
            gpu_sim.command_buffer,
            ShaderUniforms,
            gpu_sim.uniform_buffer,
            &upload_uniforms,
        );

        gpu.barrier(
            gpu_sim.command_buffer,
            .compute,
            .compute,
            .{
                .images = true,
                .shader_storage_memory = true,
            },
        );

        if (sim.enable_simulation) {
            gpu.setStatePipeline(gpu_sim.command_buffer, gpu_sim.shaders.thermal_shader);
            gpu.dispatchCompute(
                gpu_sim.command_buffer,
                &.{
                    .{
                        .workgroup_count_x = sim.width / 8,
                        .workgroup_count_y = sim.height / 8,
                        .workgroup_count_z = sim.depth / 8,
                    },
                },
            );

            gpu.barrier(
                gpu_sim.command_buffer,
                .compute,
                .compute,
                .{
                    .shader_storage_memory = true,
                },
            );

            upload_uniforms.simulation_read_offset = gpu_sim.simulation_write_offset;
            upload_uniforms.simulation_write_offset = gpu_sim.simulation_read_offset;

            gpu.mem.copySingle(
                gpu_sim.command_buffer,
                ShaderUniforms,
                gpu_sim.uniform_buffer,
                &upload_uniforms,
            );

            gpu.setStatePipeline(gpu_sim.command_buffer, gpu_sim.shaders.grain_simulation_shader);
            gpu.dispatchCompute(
                gpu_sim.command_buffer,
                &.{
                    .{
                        .workgroup_count_x = sim.width / 8,
                        .workgroup_count_y = sim.height / 8,
                        .workgroup_count_z = sim.depth / 8,
                    },
                },
            );

            upload_uniforms.simulation_read_offset = gpu_sim.simulation_read_offset;
            upload_uniforms.simulation_write_offset = gpu_sim.simulation_write_offset;

            gpu.mem.copySingle(
                gpu_sim.command_buffer,
                ShaderUniforms,
                gpu_sim.uniform_buffer,
                &upload_uniforms,
            );

            gpu.barrier(
                gpu_sim.command_buffer,
                .compute,
                .compute,
                .{
                    .shader_storage_memory = true,
                    .images = true,
                },
            );
        }

        gpu.setStatePipeline(gpu_sim.command_buffer, gpu_sim.shaders.generate_chunk_draws);

        const chunk_size = 16;

        gpu.dispatchCompute(
            gpu_sim.command_buffer,
            &.{
                .{
                    .workgroup_count_x = (sim.width / chunk_size) / 8,
                    .workgroup_count_y = (sim.height / chunk_size) / 8,
                    .workgroup_count_z = (sim.depth / chunk_size) / 8,
                },
            },
        );

        if (sim.enable_simulation) {
            std.mem.swap(
                u32,
                &gpu_sim.simulation_read_offset,
                &gpu_sim.simulation_write_offset,
            );

            sim.timestep_index += 1;

            gpu.barrier(
                gpu_sim.command_buffer,
                .compute,
                .compute,
                .{
                    .shader_storage_memory = true,
                },
            );
        }

        gpu_sim.shaders.old_fill_region_shader = gpu_sim.shaders.fill_region_shader;
    }

    pub fn render(
        sim: Simulation,
        context: Context,
        shader_uniforms: ShaderUniforms,
        render_texture: ?*Texture,
        scene_root_index: u32,
        options: struct {
            render_sdf_raymarched: bool = false,
        },
    ) void {
        var actual_uniforms = shader_uniforms;
        actual_uniforms.sdf_texture_root = scene_root_index;

        gpu.mem.copySingle(
            sim.command_buffer,
            ShaderUniforms,
            sim.uniform_buffer,
            &actual_uniforms,
        );

        gpu.mem.copySingle(
            sim.command_buffer,
            RayStats,
            sim.ray_stats_buffer,
            &RayStats{},
        );

        gpu.barrier(
            sim.command_buffer,
            .compute,
            .raster_fragment,
            .{
                .images = true,
                .draw_commands = true,
            },
        );

        if (render_texture) |texture| {
            gpu.rasterPassBegin(
                sim.command_buffer,
                .{
                    .color_attachments = &.{
                        .{
                            .texture = texture,
                            .clear = .{ 0, 0, 0, 0 },
                        },
                    },
                    //TODO: add depth stencil buffer
                },
            );
        }

        gpu.setStatePipeline(sim.command_buffer, context.shaders.env_map_shader);
        gpu.setStateDepthStencil(sim.command_buffer, .{});

        gpu.dispatchRasterDraw(
            sim.command_buffer,
            &.{
                .{
                    .count = 36,
                    .instance_count = 1,
                    .first = 0,
                    .first_instance = 0,
                },
            },
            .{
                .command_stride = @sizeOf(gpu.RasterDrawCommand),
                .command_offset = 0,
            },
        );

        gpu.setStatePipeline(sim.command_buffer, sim.shaders.depth_prepass_shader);
        gpu.setStateDepthStencil(sim.command_buffer, .{
            .depth_mode = .{
                .read = true,
                .write = false,
            },
            .depth_test = .always,
            .stencil_back = .{
                .fail_op = .keep,
                .pass_op = .replace,
                .depth_fail_op = .keep,
                .reference = 1,
            },
            .stencil_write_mask = 0xff,
            .stencil_read_mask = 0,
        });
        gpu.setStateCull(sim.command_buffer, .clockwise);

        gpu.dispatchRasterDraw(
            sim.command_buffer,
            sim.simulation_draws_buffer,
            .{
                .command_stride = @sizeOf(gpu.RasterDrawCommand),
                .command_offset = 0,
            },
        );

        gpu.setStatePipeline(sim.command_buffer, sim.shaders.gizmo_shader);
        gpu.setStateCull(sim.command_buffer, .clockwise);
        gpu.setStatePolygonMode(sim.command_buffer, .line);

        gpu.dispatchRasterDraw(
            sim.command_buffer,
            sim.simulation_draws_buffer,
            .{
                .command_stride = @sizeOf(gpu.RasterDrawCommand),
                .command_offset = 0,
            },
        );

        gpu.setStatePolygonMode(sim.command_buffer, .fill);

        if (options.render_sdf_raymarched) {
            gpu.setStatePipeline(sim.command_buffer, sim.shaders.raymarched_sdf_shader);
        } else {
            gpu.setStatePipeline(sim.command_buffer, sim.shaders.renderer_program);
        }

        gpu.setStateCull(
            sim.command_buffer,
            .clockwise,
        );
        gpu.setStateDepthStencil(sim.command_buffer, .{
            .depth_mode = .{
                .read = true,
                .write = true,
            },
            .depth_test = .less,
            .stencil_back = .{
                .testing = .equal,
                .fail_op = .keep,
                .pass_op = .keep,
                .depth_fail_op = .keep,
                .reference = 1,
            },
            .stencil_write_mask = 0,
            .stencil_read_mask = 0xff,
        });

        gpu.dispatchRasterDraw(
            sim.command_buffer,
            &.{
                .{
                    .count = 36,
                    .instance_count = 1,
                    .first = 0,
                    .first_instance = 0,
                },
            },
            .{
                .command_stride = @sizeOf(gpu.RasterDrawCommand),
                .command_offset = 0,
            },
        );

        if (render_texture) |_| {
            gpu.rasterPassEnd(sim.command_buffer);
        }
    }

    pub fn renderSceneThumbnail(
        gpu_sim: *Simulation,
        context: Context,
        sim: *@import("Simulation.zig"),
        scene_root_index: u32,
        scene_path: []const u8,
        gpa: std.mem.Allocator,
    ) !?*Texture {
        sim.csg_dirty = true;

        gpu.setStateDescriptorHeap(gpu_sim.command_buffer, context.descriptor_heap);
        gpu.setStateSamplerDescriptorHeap(gpu_sim.command_buffer, context.sampler_heap);

        gpu.mem.copy(
            gpu_sim.command_buffer,
            u8,
            (std.mem.asBytes(gpu_sim.uniform_buffer).ptr + @offsetOf(ShaderUniforms, "sdf_texture_root"))[0..4],
            std.mem.asBytes(&scene_root_index),
        );

        const is_enabled: bool = sim.enable_simulation;
        sim.update(scene_root_index);

        const thumbnail_result = try gpu_sim.scene_thumbnails.getOrPut(gpa, std.fs.path.basename(scene_path));

        const thumbnail_texture, const thumbnail_mem = try context.gpu_gpa.allocTexture(
            .{
                .dimensions = .{ 128, 128, 1 },
            },
        );
        _ = thumbnail_mem; // autofix

        thumbnail_result.value_ptr.* = thumbnail_texture;

        gpu.setStateViewport(gpu_sim.command_buffer, .{ 0, 0, 128, 128 });

        sim.projection_matrix = @bitCast((zmath.perspectiveFovRhGl(
            sim.camera.fov,
            @as(f32, @floatFromInt(128)) / @as(f32, @floatFromInt(128)),
            sim.camera.near,
            sim.camera.far,
        )));
        sim.view_matrix = @bitCast((zmath.lookAtRh(
            .{ 128, 128, 128, 0 },
            .{ 0, 0, 0, 0 },
            .{ 0, 1, 0, 0 },
        )));

        sim.render(
            context,
            thumbnail_result.value_ptr.*,
            scene_root_index,
            .{},
        );

        gpu.setStateViewport(gpu_sim.command_buffer, .{
            0,
            0,
            @floatFromInt(context.window.getSize()[0]),
            @floatFromInt(context.window.getSize()[1]),
        });

        sim.enable_simulation = is_enabled;
        return null;
    }

    pub fn render2DScene(
        gpu_sim: *Simulation,
        context: Context,
        sim: *@import("Simulation.zig"),
        scene_root_index: u32,
        gpa: std.mem.Allocator,
        width: u32,
        height: u32,
    ) !*Texture {
        _ = sim; // autofix
        _ = gpa; // autofix
        gpu.mem.copy(
            gpu_sim.command_buffer,
            u8,
            (std.mem.asBytes(gpu_sim.uniform_buffer).ptr + @offsetOf(ShaderUniforms, "sdf_texture_root"))[0..4],
            std.mem.asBytes(&scene_root_index),
        );
        const command_buffer = context.command_buffer;
        _ = command_buffer; // autofix

        if (gpu_sim.scene_2d_texture_width != width or gpu_sim.scene_2d_texture_height != height) {
            gpu.destroyTexture(gpu_sim.scene_2d_texture.?);
            //TODO: create new texture

            //gpu_sim.scene_2d_texture = @ptrFromInt(scene_2d_texture);
            gpu_sim.scene_2d_texture_width = width;
            gpu_sim.scene_2d_texture_height = height;
        }

        gpu.setStatePipeline(gpu_sim.command_buffer, gpu_sim.shaders.sdf_texture_compute);

        const dispatch_width = try std.math.divCeil(u32, width, 8);
        const dispatch_height = try std.math.divCeil(u32, height, 8);

        gpu.dispatchCompute(gpu_sim.command_buffer, &.{
            .{
                .workgroup_count_x = dispatch_width,
                .workgroup_count_y = dispatch_height,
            },
        });

        gpu.barrier(
            gpu_sim.command_buffer,
            .compute,
            .raster_fragment,
            .{
                .images = true,
            },
        );

        return gpu_sim.scene_2d_texture.?;
    }
};

const VoxelAllocatorBins = extern struct {
    voxel_allocator_bin: [15]i32 = @splat(-1),
    allocators_bump: u32 = 0,
    voxel_temperature_bump: u32 = 0,
    voxel_pallete_bump: u32 = 0,
    voxel_pallete_counters_bump: u32 = 0,
    voxel_bit_buffer_bump: u32 = 0,
    input_chunk_grid: u32 = 0,
    padding: [3]u32 = undefined,
    chunk_grid_size: [3]u32 = undefined,
    allocation_lock: u32 = 0,
};

const VoxelChunkAllocator = extern struct {
    next_allocator: i32,
    pallete_memory_start: u32,
    pallete_counters_start: u32,
    bit_buffer_start: u32,
    temperature_buffer_start: u32,
    deviation_buffer_start: u32,
    memory_allocated_bits: u32,
};

const VoxelChunksAllocation = extern struct {
    allocation: u32,
    bit_count: u32,
};

const SdfElement3D = @import("Simulation.zig").SdfElement3D;

const RayStats = @import("Simulation.zig").RayStats;
const ShaderUniforms = @import("Simulation.zig").ShaderUniforms;
const VoxelMaterial = @import("Simulation.zig").VoxelMaterial;
const VoxelMaterialVisual = @import("Simulation.zig").VoxelMaterialVisual;
const PointLight = @import("Simulation.zig").PointLight;
const CSGProgram = @import("Simulation.zig").CSGProgram;
const CSGTree = @import("main.zig").CSGTree;
const AffineTransform3D = @import("Simulation.zig").AffineTransform3D;
const std = @import("std");
const Texture = @import("gpu.zig").Texture;
const imgui = @import("imgui.zig");
const glfw = @import("zglfw");
const stb_image = @import("stb_image.zig");
const zmath = @import("lib").zmath;
const gpu = @import("gpu.zig");
