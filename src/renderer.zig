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
    window_extents: [2]u32,
    gpu_gpa: gpu.mem.Allocator,
    gpu_staging_arena: gpu.mem.Allocator,
    gpu_staging_fbas: [2]gpu.heap.FixedBufferAllocator,
    gpu_staging_fba_index: usize,
    gpu_arena_instance: gpu.heap.ArenaAllocator,
    gpu_arena: gpu.mem.Allocator,
    swapchain_texture: []gpu.TextureByte,
    command_buffer: *gpu.CommandBuffer,
    shaders_watcher: *watchers.Watcher,
    io: std.Io,
    watcher_context: *WatcherContext,
    watcher_thread: std.Thread,
    shaders: *Shaders,
    sampler_heap: []gpu.TextureDescriptor,
    sampler_heap_fba: gpu.heap.FixedBufferAllocator,
    sampler_heap_alloc: gpu.mem.Allocator,
    asym_uniforms_buffer: [][2][4][4]f32,
    gizmo_draw_buffer: []asym.geo.DrawCommand,
    gizmo_vertex_buffer: []u8,
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
        io: std.Io,
    ) !Context {
        var context: Context = undefined;

        context.io = io;
        context.shaders_watcher = try arena.create(watchers.Watcher);
        context.watcher_context = try arena.create(WatcherContext);
        context.watcher_context.* = .{
            .io = io,
            .gpa = arena,
        };
        context.shaders_watcher.* = try .init(io, arena);
        context.shaders = try arena.create(Shaders);

        try gpu.selectDevice(
            .{},
            arena,
            std.heap.smp_allocator,
        );

        context.gpu_gpa = gpu.heap.page_allocator;
        const gpu_staging_buffer = try context.gpu_gpa.alloc(u8, 32 * 1024 * 1024, .gpu_cpu_writable);
        context.gpu_staging_fbas[0] = .init(gpu_staging_buffer[0 .. gpu_staging_buffer.len / 2]);
        context.gpu_staging_fbas[1] = .init(gpu_staging_buffer[gpu_staging_buffer.len / 2 ..]);
        context.gpu_staging_arena = context.gpu_staging_fbas[0].allocator();
        context.gpu_staging_fba_index = 0;

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
        _ = env_map_data; // autofix

        const upload_cmds = gpu.queueStartCommandRecording(.{}, .{});
        defer gpu.queueSubmit(.{}, &.{upload_cmds}, &.{});

        const env_map_texture = try context.gpu_gpa.allocTexture(.{
            .dimensions = .{ @intCast(env_map_width), @intCast(env_map_height), 1 },
            .format = .rgba8_unorm32,
        });

        const env_map_staging_mem = try context.gpu_staging_arena.alloc(
            u32,
            @intCast(env_map_width * env_map_height),
            .gpu_cpu_writable,
        );

        for (gpu.mem.toAccessibleSlice(env_map_staging_mem)) |*color_out| {
            color_out.* = 0xffaaffaa;
        }

        gpu.mem.copyToTexture(
            upload_cmds,
            u8,
            .{
                .dimensions = .{ @intCast(env_map_width), @intCast(env_map_height), 1 },
                .format = .rgba8_unorm32,
            },
            env_map_texture,
            @ptrCast(env_map_staging_mem),
        );

        const sampler_descriptor_heap_memory_info = gpu.samplerHeapMemoryDescription(@sizeOf(gpu.TextureDescriptor) * 2048);

        const sampler_descriptor_heap_mem = try context.gpu_gpa.alloc(
            gpu.TextureDescriptor,
            sampler_descriptor_heap_memory_info.size / @sizeOf(gpu.TextureDescriptor),
            sampler_descriptor_heap_memory_info.memory_type,
        );

        context.sampler_heap = sampler_descriptor_heap_mem;
        context.sampler_heap_fba = .init(@ptrCast(context.sampler_heap));
        context.sampler_heap_alloc = context.sampler_heap_fba.allocator();

        const env_map_descriptor = try context.sampler_heap_alloc.allocTextureDescriptor(
            context.sampler_heap,
            env_map_texture,
        );
        _ = env_map_descriptor; // autofix

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

        try context.loadRasterVertexPipeline(
            arena,
            "env_map_renderer_vertex.spv",
            "env_map_renderer_fragment.spv",
            &context.shaders.env_map_shader,
        );

        try context.loadRasterVertexPipeline(
            arena,
            "asym_renderer_vertex.spv",
            "asym_renderer_fragment.spv",
            &context.shaders.gizmo_shader,
        );

        context.watcher_thread = try std.Thread.spawn(.{}, watcherThread, .{context.shaders_watcher});

        return context;
    }

    pub fn deinit(context: Context) void {
        context.shaders_watcher.stop();
        context.watcher_thread.join();
    }

    pub fn beginFrame(
        context: *Context,
    ) void {
        context.command_buffer = gpu.queueStartCommandRecording(.{}, .{
            .sampler_heap = context.sampler_heap,
        });

        const command_buffer = context.command_buffer;

        const framebuffer_size = context.window_extents;

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
        _ = command_buffer; // autofix
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
    ) !?[]gpu.TextureByte {
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

        var texture_memory: []gpu.TextureByte = &.{};

        if (false) {
            texture_memory = try context.gpu_gpa.allocTexture(
                .{
                    .dimensions = .{ max_width, max_height, 1 },
                    .layer_count = @intCast(typeface.codepoints_to_glyph.count()),
                    .format = .rgba8_unorm32,
                    .type = .array_2d,
                },
            );
            context.sampler_heap[10] = gpu.createTextureDescriptor(texture_memory);
        }

        context.gpu_staging_arena = context.gpu_staging_fbas[0].allocator();

        const commands = gpu.queueStartCommandRecording(.{}, .{});

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

            if (false) {
                gpu.mem.copyToTexture(
                    commands,
                    u8,
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
                        .format = .rgba8_unorm32,
                    },
                    texture_memory,
                    try context.gpu_staging_arena.allocDupe(u8, data.pixels),
                );
            }
        }

        context.asym_glyph_metrics_buffer = try context.gpu_gpa.alloc(
            @import("lib").shaders.common.asym.GlyphMetric,
            glyph_metrics.len,
            .gpu,
        );

        gpu.mem.copy(
            commands,
            @import("lib").shaders.common.asym.GlyphMetric,
            context.asym_glyph_metrics_buffer,
            try context.gpu_staging_arena.allocDupe(@import("lib").shaders.common.asym.GlyphMetric, glyph_metrics),
        );

        if (false) {
            gpu.queueSubmit(
                .{},
                &.{commands},
                &.{},
            );
        }

        return texture_memory;
    }

    pub fn renderGizmos(
        context: *Context,
        gpa: std.mem.Allocator,
        geo_context: *const asym.geo.Context,
        scene: *const asym.geo.Scene,
        views: []const asym.geo.Scene.View,
        typeface_textures: []?[]gpu.TextureByte,
    ) !void {
        const command_buffer = context.command_buffer;

        _ = typeface_textures; // autofix
        gpu.setStateViewport(
            command_buffer,
            .{ 0, 0, @floatFromInt(context.window_extents[0]), @floatFromInt(context.window_extents[1]) },
        );
        gpu.setStateScissor(
            command_buffer,
            .{ 0, 0, @intCast(context.window_extents[0]), @intCast(context.window_extents[1]) },
        );

        const staging_arena = context.gpu_staging_fbas[1].allocator();

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
                try staging_arena.allocDupe(u32, &.{@intCast(transforms_offset)}),
            );

            gpu.mem.copy(
                command_buffer,
                asym.geo.AffineTransform3D,
                context.asym_transforms_buffer[transforms_offset..],
                try staging_arena.allocDupe(asym.geo.AffineTransform3D, transforms.items),
            );

            gpu.mem.copy(
                command_buffer,
                asym.geo.Material,
                context.asym_materials_buffer[materials_offset..],
                try staging_arena.allocDupe(asym.geo.Material, materials.items),
            );

            transforms_offset += transforms.items.len;
            materials_offset += materials.items.len;
        }

        for (views) |*view| {
            var iter = view.iterate();

            const Mat4x4 = [4]@Vector(4, f32);

            const view_projection = zmath.mul(@as(Mat4x4, @bitCast(view.view)), @as(Mat4x4, @bitCast(view.projection)));

            gpu.mem.copy(
                command_buffer,
                [2][4][4]f32,
                context.asym_uniforms_buffer,
                try staging_arena.allocDupe([2][4][4]f32, &.{
                    .{
                        @bitCast(view_projection),
                        @splat(@splat(@floatCast(glfw.getTime()))),
                    },
                }),
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
                            try staging_arena.allocDupe(shtmap.Sheetmap, &.{
                                shtmap.Sheetmap{
                                    .quadrat_buffer_begin = @intCast(quadrat_buffer_begin),
                                    .width = grapheme_buffer_width,
                                    .height = grapheme_buffer_height,
                                },
                            }),
                        );

                        gpu.mem.copy(
                            command_buffer,
                            GraphemeBin,
                            context.asym_grapheme_pigeon_hole_buffers[quadrat_buffer_begin..],
                            try staging_arena.allocDupe(GraphemeBin, grapheme_buffer_bins),
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
                        &(try staging_arena.allocDupe(u32, &.{@intCast(parameter_buffer_offset)}))[0],
                    );

                    gpu.mem.copy(
                        command_buffer,
                        f32,
                        context.asym_parameters_buffer[parameter_buffer_offset..],
                        try staging_arena.allocDupe(f32, params),
                    );

                    gpu.mem.copy(
                        command_buffer,
                        asym.geo.DrawCommand,
                        context.gizmo_draw_buffer[draw_buffer_offset..],
                        try staging_arena.allocDupe(asym.geo.DrawCommand, draws),
                    );

                    draw_buffer_offset += draws.len;
                    parameter_buffer_offset += params.len;
                }
            }
        }

        const framebuffer_size = context.window_extents;
        _ = framebuffer_size; // autofix

        gpu.rasterPassBegin(context.command_buffer, .{
            .color_attachments = &.{.{
                .texture = context.swapchain_texture,
                .clear = .{ 0, 0, 1, 0 },
            }},
        });
        defer gpu.rasterPassEnd(context.command_buffer);

        for (views) |*view| {
            var iter = view.iterate();

            gpu.setStateScissor(command_buffer, .{
                @intFromFloat(view.scissor[0]),
                @intFromFloat(view.scissor[1]),
                @intFromFloat(view.scissor[2]),
                @intFromFloat(view.scissor[3]),
            });

            var draw_buffer_offset: usize = 0;

            while (iter.next()) |tuple| {
                const state, const group = tuple;
                _ = state; // autofix
                for (group.draws_by_type.values, group.parameters_by_type.values, 0..) |
                    draws,
                    params,
                    type_index,
                | {
                    _ = params; // autofix
                    _ = type_index; // autofix
                    if (draws.len == 0) {
                        continue;
                    }

                    draw_buffer_offset += draws.len;
                }

                gpu.setStateBlend(command_buffer, .{});
                gpu.setStateDepthStencil(command_buffer, .{});

                gpu.launchRasterDraw(
                    command_buffer,
                    context.shaders.gizmo_shader,
                    &.{},
                    @as([*]gpu.RasterDrawCommand, @ptrCast(context.gizmo_draw_buffer[0..].ptr))[0..draw_buffer_offset],
                    .{
                        .command_stride = @sizeOf(asym.geo.DrawCommand),
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
    ) !void {
        _ = context; // autofix
        _ = arena; // autofix
        pipeline.* = gpu.createRasterVertexPipeline(
            @embedFile(vertex_ir_path),
            @embedFile(fragment_ir_path),
            .{
                .color_targets = &.{.{
                    .format = .bgra8_srgb32,
                    .write_mask = 0xff,
                }},
                .depth_format = .depth_stencil_u24_u8,
                .stencil_format = .depth_stencil_u24_u8,
            },
        );
    }

    pub fn loadComputePipeline(
        context: *Context,
        arena: std.mem.Allocator,
        comptime compute_path: []const u8,
        pipeline: **gpu.Pipeline,
    ) !void {
        _ = context; // autofix
        _ = arena; // autofix
        pipeline.* = gpu.createComputePipeline(
            @embedFile(compute_path),
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

    voxel_bit_buffer_memory_texture: []gpu.TextureByte = undefined,
    voxel_chunk_allocations_texture: []gpu.TextureByte = undefined,
    voxel_chunk_positions_texture: []gpu.TextureByte = undefined,

    voxel_heap_bit_buffer: []u32 = undefined,
    voxel_positions_buffer: []u32 = undefined,

    simulation_state: *@import("lib").shaders.common.SimulationState = undefined,
    simulation_rendering_state: *@import("lib").shaders.common.SimulationRenderingState = undefined,

    scene_thumbnails: std.StringHashMapUnmanaged(?[]gpu.TextureByte) = .empty,
    scene_2d_texture: ?[]gpu.TextureByte = null,
    scene_2d_texture_width: u32 = 0,
    scene_2d_texture_height: u32 = 0,

    simulation_read_offset: u32 = 0,
    simulation_write_offset: u32 = 0,

    command_buffer: *gpu.CommandBuffer = undefined,
    staging_arena: gpu.mem.Allocator = undefined,

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
        );

        try context.loadComputePipeline(
            arena,
            "thermal_compute_compute.spv",
            &gpu_sim.shaders.thermal_shader,
        );
        try context.loadComputePipeline(
            arena,
            "grain_simulation_compute.spv",
            &gpu_sim.shaders.grain_simulation_shader,
        );
        gpu_sim.shaders.simulation_shader = gpu_sim.shaders.grain_simulation_shader;
        try context.loadComputePipeline(
            arena,
            "fill_region_compute.spv",
            &gpu_sim.shaders.fill_region_shader,
        );
        try context.loadComputePipeline(
            arena,
            "generate_chunk_draws_compute.spv",
            &gpu_sim.shaders.generate_chunk_draws,
        );
        try context.loadComputePipeline(
            arena,
            "sdf_texture_compute.spv",
            &gpu_sim.shaders.sdf_texture_compute,
        );
        try context.loadRasterVertexPipeline(
            arena,
            "gizmo_renderer_vertex.spv",
            "gizmo_renderer_fragment.spv",
            &gpu_sim.shaders.gizmo_shader,
        );

        try context.loadRasterVertexPipeline(
            arena,
            "gizmo_renderer_vertex.spv",
            "depth_prepass_fragment.spv",
            &gpu_sim.shaders.depth_prepass_shader,
        );

        try context.loadRasterVertexPipeline(
            arena,
            "renderer_vertex.spv",
            "depth_prepass_fragment.spv",
            &gpu_sim.shaders.bounds_depth_prepass_shader,
        );

        try context.loadRasterVertexPipeline(
            arena,
            "renderer_vertex.spv",
            "sdf_renderer_fragment.spv",
            &gpu_sim.shaders.raymarched_sdf_shader,
        );

        gpu_sim.scene_2d_texture = try context.gpu_gpa.allocTexture(.{
            .type = .@"2d",
            .dimensions = .{ 512, 512, 1 },
        });
        const buffer_length = sim.width * sim.height * sim.depth;

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
        gpu_sim.voxel_heap_bit_buffer = try context.gpu_gpa.alloc(u32, 16 * 16 * 16 * 16, .gpu);
        gpu_sim.voxel_positions_buffer = try context.gpu_gpa.alloc(u32, 16 * 16 * 16, .gpu);
        gpu_sim.simulation_vertex_buffer = try context.gpu_gpa.alloc([4]f32, 10_000, .gpu);
        gpu_sim.simulation_draws_buffer = try context.gpu_gpa.alloc(gpu.RasterDrawCommand, 128, .gpu);
        gpu_sim.simulation_bounds_buffer = try context.gpu_gpa.alloc([4]u32, 2, .gpu);
        gpu_sim.ray_stats_buffer = try context.gpu_gpa.create(RayStats, .gpu);
        gpu_sim.vertex_buffer = try context.gpu_gpa.alloc(u8, 1024, .gpu);

        gpu_sim.simulation_state = try context.gpu_gpa.create(@import("lib").shaders.common.SimulationState, .gpu);
        gpu_sim.simulation_rendering_state = try context.gpu_gpa.create(@import("lib").shaders.common.SimulationRenderingState, .gpu);

        context.gpu_staging_fbas[0].end_index = 0;
        context.gpu_staging_fbas[1].end_index = 0;
        context.gpu_staging_arena = context.gpu_staging_fbas[0].allocator();

        gpu_sim.staging_arena = context.gpu_staging_arena;

        const upload_cmds = gpu.queueStartCommandRecording(.{}, .{});
        defer gpu.queueSubmit(
            .{},
            &.{upload_cmds},
            &.{},
        );

        gpu.mem.copySingle(
            upload_cmds,
            RayStats,
            gpu_sim.ray_stats_buffer,
            &(try context.gpu_staging_arena.allocDupe(RayStats, &.{
                .{},
            }))[0],
        );

        const brick_map_width = 16;

        gpu_sim.voxel_bit_buffer_memory_texture = try context.gpu_gpa.allocTexture(.{
            .type = .@"3d",
            .dimensions = @splat(16 * brick_map_width),
            .format = .r16_u16,
        });

        gpu_sim.voxel_chunk_allocations_texture = try context.gpu_gpa.allocTexture(.{
            .type = .@"3d",
            .dimensions = @splat(brick_map_width),
            .format = .r32_u32,
        });

        gpu_sim.voxel_chunk_positions_texture = try context.gpu_gpa.allocTexture(.{
            .type = .@"3d",
            .dimensions = @splat(brick_map_width),
            .format = .r16_u16,
        });

        context.sampler_heap[0] = gpu.createTextureDescriptor(
            gpu_sim.voxel_bit_buffer_memory_texture,
        );

        context.sampler_heap[1] = gpu.createTextureDescriptor(
            gpu_sim.voxel_chunk_allocations_texture,
        );

        context.sampler_heap[1] = gpu.createTextureDescriptor(
            gpu_sim.voxel_chunk_positions_texture,
        );

        context.sampler_heap[5] = gpu.createTextureDescriptor(
            gpu_sim.voxel_bit_buffer_memory_texture,
        );

        context.sampler_heap[6] = gpu.createTextureDescriptor(
            gpu_sim.voxel_chunk_positions_texture,
        );

        const voxel_allocator_bins: VoxelAllocatorBins = .{
            .chunk_grid_size = .{ 64, 64, 64 },
        };

        gpu.mem.copySingle(
            upload_cmds,
            VoxelAllocatorBins,
            gpu_sim.voxel_allocator_bins_buffer,
            &(try context.gpu_staging_arena.allocDupe(VoxelAllocatorBins, &.{voxel_allocator_bins}))[0],
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
        context: *Context,
        sim: @import("Simulation.zig"),
        program: CSGProgram,
    ) !void {
        _ = sim; // autofix
        const staging_arena = context.gpu_staging_fbas[1].allocator();

        if (program.elements.items.len != 0) {
            gpu.mem.copy(
                gpu_sim.command_buffer,
                SdfElement3D,
                gpu_sim.sdf_elements_3d_buffer,
                try staging_arena.allocDupe(SdfElement3D, program.elements.items),
            );
        }

        if (program.element_params.items.len != 0) {
            gpu.mem.copy(
                gpu_sim.command_buffer,
                f32,
                gpu_sim.sdf_elements_3d_params_buffer,
                try staging_arena.allocDupe(f32, program.element_params.items),
            );
        }

        if (program.transforms.items.len != 0) {
            gpu.mem.copy(
                gpu_sim.command_buffer,
                AffineTransform3D,
                gpu_sim.sdf_elements_3d_transforms_buffer,
                try staging_arena.allocDupe(AffineTransform3D, program.transforms.items),
            );
        }

        if (program.element_bounds.items.len != 0) {
            gpu.mem.copy(
                gpu_sim.command_buffer,
                [4]f32,
                gpu_sim.sdf_elements_3d_bounds_buffer,
                try staging_arena.allocDupe([4]f32, program.element_bounds.items),
            );
        }
    }

    pub fn update(gpu_sim: *Simulation, sim: *@import("Simulation.zig")) !void {
        const staging_arena = gpu_sim.staging_arena;

        gpu.mem.copy(
            gpu_sim.command_buffer,
            VoxelMaterial,
            gpu_sim.voxel_materials_buffer,
            try staging_arena.allocDupe(VoxelMaterial, sim.voxel_materials.items),
        );

        gpu.mem.copy(
            gpu_sim.command_buffer,
            VoxelMaterialVisual,
            gpu_sim.voxel_materials_visual_buffer,
            try staging_arena.allocDupe(VoxelMaterialVisual, sim.voxel_materials_visual.items),
        );

        gpu.mem.copy(
            gpu_sim.command_buffer,
            PointLight,
            gpu_sim.point_light_buffer,
            try staging_arena.allocDupe(PointLight, sim.point_lights.items),
        );

        if (sim.gpu_sim.shaders.fill_region_shader != sim.gpu_sim.shaders.old_fill_region_shader) {
            sim.csg_dirty = true;
        }

        sim.csg_dirty = true;

        if (!sim.enable_simulation and sim.csg_dirty) {
            sim.csg_dirty = false;

            gpu.launchCompute(
                gpu_sim.command_buffer,
                gpu_sim.shaders.fill_region_shader,
                &.{},
                &.{
                    .{
                        .workgroup_count_x = sim.width / 8,
                        .workgroup_count_y = sim.height / 8,
                        .workgroup_count_z = sim.depth / 8,
                    },
                },
            );
        }

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
            gpu.launchCompute(
                gpu_sim.command_buffer,
                gpu_sim.shaders.thermal_shader,
                &.{
                    undefined,
                    gpu_sim.simulation_state,
                },
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

            gpu.launchCompute(
                gpu_sim.command_buffer,
                gpu_sim.shaders.grain_simulation_shader,
                &.{},
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
                    .images = true,
                },
            );
        }

        const chunk_size = 16;

        gpu.launchCompute(
            gpu_sim.command_buffer,
            gpu_sim.shaders.generate_chunk_draws,
            &.{
                gpu_sim.vertex_buffer.ptr,
                undefined,
                gpu_sim.simulation_state,
                gpu_sim.simulation_rendering_state,
            },
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
        render_texture: ?[]gpu.TextureByte,
        scene_root_index: u32,
        options: struct {
            render_sdf_raymarched: bool = false,
        },
    ) void {
        _ = scene_root_index; // autofix

        gpu.barrier(
            sim.command_buffer,
            .compute,
            .raster_fragment,
            .{
                .images = true,
                .draw_commands = true,
            },
        );

        const framebuffer_size = context.window_extents;
        _ = framebuffer_size; // autofix

        gpu.rasterPassBegin(context.command_buffer, .{
            .color_attachments = &.{.{
                .texture = context.swapchain_texture,
                .clear = .{ 0, 0, 1, 0 },
            }},
        });

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
                    .render_area = .{
                        .x = 0,
                        .y = 0,
                        .width = 128,
                        .height = 128,
                    },
                    //TODO: add depth stencil buffer
                },
            );
        }

        gpu.setStateDepthStencil(sim.command_buffer, .{});

        gpu.launchRasterDraw(
            sim.command_buffer,
            context.shaders.env_map_shader,
            &.{},
            &.{
                .{
                    .count = 36,
                    .instance_count = 1,
                    .first = 0,
                    .first_instance = 0,
                },
            },
            .{},
        );

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

        gpu.launchRasterDraw(
            sim.command_buffer,
            sim.shaders.depth_prepass_shader,
            &.{
                sim.vertex_buffer.ptr,
                sim.simulation_state,
                sim.simulation_rendering_state,
            },
            sim.simulation_draws_buffer,
            .{},
        );

        gpu.setStateCull(sim.command_buffer, .clockwise);
        gpu.setStatePolygonMode(sim.command_buffer, .line);

        gpu.launchRasterDraw(
            sim.command_buffer,
            sim.shaders.gizmo_shader,
            &.{},
            sim.simulation_draws_buffer,
            .{},
        );

        gpu.setStatePolygonMode(sim.command_buffer, .fill);

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

        gpu.launchRasterDraw(
            sim.command_buffer,
            if (options.render_sdf_raymarched) sim.shaders.raymarched_sdf_shader else sim.shaders.renderer_program,
            &.{},
            &.{
                .{
                    .count = 36,
                    .instance_count = 1,
                    .first = 0,
                    .first_instance = 0,
                },
            },
            .{},
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
    ) !?[]u8 {
        if (true) {
            return null;
        }
        sim.csg_dirty = true;

        const is_enabled: bool = sim.enable_simulation;
        try sim.update(scene_root_index);

        const thumbnail_result = try gpu_sim.scene_thumbnails.getOrPut(gpa, std.fs.path.basename(scene_path));

        const thumbnail_texture = try context.gpu_gpa.allocTexture(
            .{
                .dimensions = .{ 128, 128, 1 },
                .format = .rgba8_unorm32,
            },
        );

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
    ) ![]gpu.TextureByte {
        _ = gpa; // autofix
        _ = scene_root_index; // autofix
        _ = sim; // autofix

        const command_buffer = context.command_buffer;
        _ = command_buffer; // autofix

        if (gpu_sim.scene_2d_texture_width != width or gpu_sim.scene_2d_texture_height != height) {
            //TODO: create new texture

            //gpu_sim.scene_2d_texture = @ptrFromInt(scene_2d_texture);
            gpu_sim.scene_2d_texture_width = width;
            gpu_sim.scene_2d_texture_height = height;
        }

        const dispatch_width = try std.math.divCeil(u32, width, 8);
        const dispatch_height = try std.math.divCeil(u32, height, 8);

        gpu.launchCompute(
            gpu_sim.command_buffer,
            gpu_sim.shaders.sdf_texture_compute,
            &.{},
            &.{
                .{
                    .workgroup_count_x = dispatch_width,
                    .workgroup_count_y = dispatch_height,
                },
            },
        );

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

const renderer_shader = @import("renderer_shader");

const SdfElement3D = @import("Simulation.zig").SdfElement3D;

const RayStats = @import("Simulation.zig").RayStats;
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
