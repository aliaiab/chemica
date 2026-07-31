fn watcherCallback(context: ?*anyopaque, path: [:0]const u8, event: watchers.Event) !void {
    const watcher_context: *WatcherContext = @ptrCast(@alignCast(context.?));

    switch (event) {
        .modified => {
            std.log.info("File was modified! {s}\n", .{path});

            const shader_query = watcher_context.shaders.getPtr(std.fs.path.stem(path)) orelse return;

            const file_path = try std.Io.Dir.cwd().readFileAlloc(
                watcher_context.io,
                path,
                watcher_context.gpa,
                .unlimited,
            );

            const actual_file_path = file_path[2 .. file_path.len - 1];

            std.log.info("{s}\n", .{actual_file_path});
            std.log.info("{any}\n", .{shader_query.*});

            const file_data = try std.Io.Dir.cwd().readFileAlloc(
                watcher_context.io,
                actual_file_path,
                watcher_context.gpa,
                .unlimited,
            );

            watcher_context.*.programs.items[shader_query.program_index].sources[shader_query.source_index] = .{
                .type = shader_query.type,
                .source_path = try watcher_context.gpa.dupe(u8, actual_file_path),
            };

            try watcher_context.shader_compile_queue.append(watcher_context.gpa, .{
                .binary = file_data,
                .type = shader_query.type,
                .shader_name = std.fs.path.basename(path),
            });
        },
    }
}

fn watcherThread(watcher: *watchers.Watcher) !void {
    try watcher.start(.{});
}

const watchers = @import("../watchers.zig");

const WatcherContext = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    shaders: std.StringHashMapUnmanaged(ShaderModule) = .empty,
    programs: std.ArrayList(ShaderProgram) = .empty,
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

const ShaderProgram = struct {
    program: *u32,
    sources: []ShaderSource,
};

const Shaders = struct {
    env_map_shader: u32,
};

pub const Context = struct {
    window: *glfw.Window,
    env_map_texture: u32,
    env_map_shader: u32,
    shaders_watcher: *watchers.Watcher,
    io: std.Io,
    watcher_context: *WatcherContext,
    watcher_thread: std.Thread,
    shaders: *Shaders,

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

        const Static = struct {
            pub var proc_table: gl.ProcTable = undefined;
        };

        if (!Static.proc_table.init(glfw.getProcAddress)) return error.GLInitFailed;

        context.shaders_watcher.setCallback(watcherCallback, context.watcher_context);

        gl.makeProcTableCurrent(&Static.proc_table);

        gl.Enable(gl.BLEND);
        gl.Enable(gl.DEPTH_TEST);
        gl.Enable(gl.CULL_FACE);
        gl.CullFace(gl.BACK);
        gl.FrontFace(gl.CCW);
        gl.DepthMask(1);
        gl.DepthFunc(gl.LESS);
        gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

        var env_map_width: c_int = 0;
        var env_map_height: c_int = 0;
        var env_map_comps: c_int = 0;

        const embedded_environment_map = @embedFile("../assets/vintage_measuring_lab_2k.png");

        const env_map_data = stb_image.stbi_load_from_memory(
            embedded_environment_map,
            @intCast(embedded_environment_map.len),
            &env_map_width,
            &env_map_height,
            &env_map_comps,
            0,
        );

        gl.CreateTextures(gl.TEXTURE_2D, 1, @ptrCast(&context.env_map_texture));
        gl.TextureStorage2D(
            context.env_map_texture,
            1,
            gl.RGB8,
            env_map_width,
            env_map_height,
        );
        gl.TextureSubImage2D(
            context.env_map_texture,
            0,
            0,
            0,
            env_map_width,
            env_map_height,
            gl.RGB,
            gl.UNSIGNED_BYTE,
            env_map_data,
        );

        try context.loadShaderProgram(arena, &.{
            .{ .type = gl.VERTEX_SHADER, .source_path = "env_map_vertex.spv" },
            .{ .type = gl.FRAGMENT_SHADER, .source_path = "env_map_fragment.spv" },
        }, &context.env_map_shader);

        try imgui.impl.opengl3.init(.{});
        try imgui.impl.glfw.initForOpenGL(window, .{});

        context.watcher_thread = try std.Thread.spawn(.{}, watcherThread, .{context.shaders_watcher});

        return context;
    }

    pub fn deinit(context: Context) void {
        context.shaders_watcher.stop();
        context.watcher_thread.join();
    }

    pub fn beginFrame(context: *Context) void {
        gl.BindFramebuffer(gl.FRAMEBUFFER, 0);

        gl.ClearColor(0, 0, 0, 1);
        gl.ClearDepthf(1);
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        imgui.impl.opengl3.newFrame();

        const framebuffer_size = context.window.getFramebufferSize();

        gl.Viewport(0, 0, framebuffer_size[0], framebuffer_size[1]);

        gl.BindTextureUnit(22, context.env_map_texture);

        while (context.watcher_context.shader_compile_queue.pop()) |entry| {
            const shader_query = context.watcher_context.shaders.getPtr(entry.shader_name).?;

            context.watcher_context.programs.items[shader_query.program_index].program.* = loadShaderProgramRuntime(
                context,
                context.watcher_context.gpa,
                context.watcher_context.programs.items[shader_query.program_index].sources,
            ) catch unreachable;
        }
    }

    pub fn endFrame(context: Context) void {
        _ = context; // autofix
    }

    pub fn loadShaderProgram(
        context: *Context,
        arena: std.mem.Allocator,
        comptime sources: []const ShaderSource,
        program: *u32,
    ) !void {
        if (@import("builtin").mode == .Debug) {
            const actual_sources = try arena.dupe(ShaderSource, sources);

            const program_index: u32 = @intCast(context.watcher_context.programs.items.len);

            try context.watcher_context.programs.append(context.watcher_context.gpa, .{
                .program = program,
                .sources = actual_sources,
            });

            for (sources, actual_sources, 0..) |source, *output_source, i| {
                const path_path = try std.fs.path.joinZ(arena, &.{ "zig-out/", std.fs.path.stem(source.source_path) });

                const path = try std.Io.Dir.cwd().readFileAllocOptions(
                    context.io,
                    path_path,
                    arena,
                    .unlimited,
                    .@"1",
                    0,
                );

                try context.watcher_context.shaders.put(context.watcher_context.gpa, std.fs.path.stem(source.source_path), .{
                    .program_index = program_index,
                    .shader = 0,
                    .type = source.type,
                    .source_index = @intCast(i),
                });

                try context.shaders_watcher.addFile(path_path);

                output_source.source_path = path[2 .. path.len - 1];
            }

            program.* = try loadShaderProgramRuntime(context, arena, actual_sources);
            return;
        }

        program.* = gl.CreateProgram();

        if (program.* == 0) return error.ProgramCreationFailed;

        var shaders: [8]u32 = undefined;

        const program_index: u32 = @intCast(context.watcher_context.programs.items.len);

        try context.watcher_context.programs.append(context.watcher_context.gpa, .{
            .program = program,
            .sources = try arena.dupe(ShaderSource, sources),
        });

        for (context.watcher_context.programs.items[program_index].sources) |*source| {
            const path_path = try std.fs.path.join(context.watcher_context.gpa, &.{
                "zig-out/",
                std.fs.path.stem(source.source_path),
            });

            const cache_path = try std.Io.Dir.cwd().readFileAlloc(
                context.watcher_context.io,
                path_path,
                context.watcher_context.gpa,
                .unlimited,
            );

            source.source_path = cache_path[2 .. cache_path.len - 1];
        }

        inline for (sources, 0..) |source, i| {
            const binary = @embedFile(source.source_path);

            shaders[i] = try loadShader(.{ .binary = binary, .type = source.type });

            const path_file_path = try std.mem.joinZ(arena, &.{}, &.{ "zig-out/", std.fs.path.stem(source.source_path) });

            try context.watcher_context.shaders.put(context.watcher_context.gpa, std.fs.path.stem(source.source_path), .{
                .program_index = program_index,
                .shader = shaders[i],
                .type = source.type,
                .source_index = i,
            });

            try context.shaders_watcher.addFile(path_file_path);

            gl.AttachShader(program.*, shaders[i]);
        }

        gl.LinkProgram(program.*);

        var link_status: i32 = 0;

        gl.GetProgramiv(program.*, gl.LINK_STATUS, @ptrCast(&link_status));

        if (link_status == 0) {
            var info_log_length: i32 = 0;

            gl.GetProgramiv(
                program.*,
                gl.INFO_LOG_LENGTH,
                @ptrCast(&info_log_length),
            );

            const info_log = try arena.alloc(u8, @intCast(info_log_length));

            std.log.err(
                "[OpenGL]: Shader Program failed to link: {s}\n",
                .{info_log},
            );

            return error.FailedToLink;
        }

        for (shaders) |shader| {
            gl.DetachShader(program.*, shader);
            gl.DeleteShader(shader);
        }
    }

    pub fn loadShaderProgramRuntime(
        context: *Context,
        arena: std.mem.Allocator,
        sources: []const ShaderSource,
    ) !u32 {
        const program = gl.CreateProgram();

        if (program == 0) return error.ProgramCreationFailed;

        var shaders: [8]u32 = undefined;

        for (sources, 0..) |source, i| {
            std.log.info("src_path: {s}\n", .{source.source_path});

            const binary = try std.Io.Dir.cwd().readFileAlloc(
                context.io,
                source.source_path,
                context.watcher_context.gpa,
                .unlimited,
            );

            shaders[i] = try loadShader(.{ .binary = binary, .type = source.type });

            gl.AttachShader(program, shaders[i]);
        }

        gl.LinkProgram(program);

        var link_status: i32 = 0;

        gl.GetProgramiv(program, gl.LINK_STATUS, @ptrCast(&link_status));

        if (link_status == 0) {
            var info_log_length: i32 = 0;

            gl.GetProgramiv(
                program,
                gl.INFO_LOG_LENGTH,
                @ptrCast(&info_log_length),
            );

            const info_log = try arena.alloc(u8, @intCast(info_log_length));

            std.log.err(
                "[OpenGL]: Shader Program failed to link: {s}\n",
                .{info_log},
            );

            return error.FailedToLink;
        }

        for (shaders) |shader| {
            gl.DetachShader(program, shader);
            gl.DeleteShader(shader);
        }

        return program;
    }
};

pub const Simulation = struct {
    vertex_array: u32 = 0,
    vertex_buffer: u32 = 0,

    simulation_material_buffers: [2]u32 = .{ 0, 0 },
    simulation_deviation_buffers: [2]u32 = .{ 0, 0 },
    simulation_temperature_buffers: [2]u32 = .{ 0, 0 },

    heat_measurement_buffer: u32 = 0,

    voxel_materials_buffer: u32 = 0,
    voxel_materials_visual_buffer: u32 = 0,

    shaders: *SimShaders,

    point_light_buffer: u32 = 0,

    uniform_buffer: u32 = 0,

    csg_instruction_buffer: u32 = 0,
    csg_instructions_box_buffer: u32 = 0,
    csg_instructions_sphere_buffer: u32 = 0,
    csg_instructions_extrude_post_buffer: u32 = 0,
    csg_transform_buffer: u32 = 0,
    csg_composite_material_buffer: u32 = 0,

    scene_thumbnails: std.StringHashMapUnmanaged(?*Texture) = .empty,

    const SimShaders = struct {
        renderer_program: u32 = 0,
        simulation_shader: u32 = 0,
        thermal_shader: u32 = 0,
        grain_simulation_shader: u32 = 0,
        fill_region_shader: u32 = 0,

        old_fill_region_shader: u32 = 0,
    };

    pub fn init(
        context: *Context,
        sim: @import("../Simulation.zig"),
        arena: std.mem.Allocator,
    ) !Simulation {
        var gpu_sim: Simulation = .{
            .shaders = try arena.create(SimShaders),
        };

        try context.loadShaderProgram(arena, &.{
            .{
                .type = gl.VERTEX_SHADER,
                .source_path = "renderer_vertex.spv",
            },
            .{
                .type = gl.FRAGMENT_SHADER,
                .source_path = "renderer_fragment.spv",
            },
        }, &gpu_sim.shaders.renderer_program);
        try context.loadShaderProgram(arena, &.{
            .{
                .type = gl.COMPUTE_SHADER,
                .source_path = "grain_simulation.spv",
            },
        }, &gpu_sim.shaders.simulation_shader);
        try context.loadShaderProgram(arena, &.{
            .{
                .type = gl.COMPUTE_SHADER,
                .source_path = "thermal_compute.spv",
            },
        }, &gpu_sim.shaders.thermal_shader);
        try context.loadShaderProgram(arena, &.{
            .{
                .type = gl.COMPUTE_SHADER,
                .source_path = "grain_simulation.spv",
            },
        }, &gpu_sim.shaders.grain_simulation_shader);
        try context.loadShaderProgram(arena, &.{
            .{
                .type = gl.COMPUTE_SHADER,
                .source_path = "fill_region.spv",
            },
        }, &gpu_sim.shaders.fill_region_shader);

        gl.CreateVertexArrays(1, @ptrCast(&gpu_sim.vertex_array));

        gl.CreateBuffers(1, @ptrCast(&gpu_sim.uniform_buffer));
        gl.CreateBuffers(1, @ptrCast(&gpu_sim.vertex_buffer));
        gl.CreateBuffers(2, &gpu_sim.simulation_material_buffers);
        gl.CreateBuffers(2, &gpu_sim.simulation_temperature_buffers);
        gl.CreateBuffers(2, &gpu_sim.simulation_deviation_buffers);
        gl.CreateBuffers(1, @ptrCast(&gpu_sim.heat_measurement_buffer));

        gl.CreateBuffers(1, @ptrCast(&gpu_sim.csg_instruction_buffer));
        gl.CreateBuffers(1, @ptrCast(&gpu_sim.csg_instructions_box_buffer));
        gl.CreateBuffers(1, @ptrCast(&gpu_sim.csg_instructions_sphere_buffer));
        gl.CreateBuffers(1, @ptrCast(&gpu_sim.csg_instructions_extrude_post_buffer));
        gl.CreateBuffers(1, @ptrCast(&gpu_sim.csg_transform_buffer));
        gl.CreateBuffers(1, @ptrCast(&gpu_sim.csg_composite_material_buffer));

        gl.CreateBuffers(1, @ptrCast(&gpu_sim.voxel_materials_buffer));
        gl.CreateBuffers(1, @ptrCast(&gpu_sim.voxel_materials_visual_buffer));
        gl.CreateBuffers(1, @ptrCast(&gpu_sim.point_light_buffer));

        // gl.CreateBuffers(1, &voxel_allocator_bins_buffer);
        // gl.CreateBuffers(1, &voxel_pallete_memory_buffer);
        // gl.CreateBuffers(1, &voxel_pallete_counters_buffer);
        // gl.CreateBuffers(1, &voxel_bit_buffer_memory_buffer);
        // gl.CreateBuffers(1, &voxel_temperature_memory_buffer);
        // gl.CreateBuffers(1, &voxel_allocator_buffer);
        // gl.CreateBuffers(1, &voxel_chunks_buffer);

        gl.VertexArrayVertexBuffer(
            gpu_sim.vertex_array,
            0,
            gpu_sim.vertex_buffer,
            0,
            @sizeOf([3]f32),
        );

        gl.EnableVertexArrayAttrib(gpu_sim.vertex_array, 0);
        gl.VertexArrayAttribFormat(
            gpu_sim.vertex_array,
            0,
            3,
            gl.FLOAT,
            gl.FALSE,
            0,
        );
        gl.VertexArrayAttribBinding(gpu_sim.vertex_array, 0, 0);

        const vertices = [_]f32{
            0.0, 0.0, 0.0,
            1.0, 1.0, 0.0,
            1.0, 0.0, 0.0,
            1.0, 1.0, 0.0,
            0.0, 0.0, 0.0,
            0.0, 1.0, 0.0,
            0.0, 0.0, 1.0,
            1.0, 0.0, 1.0,
            1.0, 1.0, 1.0,
            1.0, 1.0, 1.0,
            0.0, 1.0, 1.0,
            0.0, 0.0, 1.0,
            0.0, 1.0, 1.0,
            0.0, 1.0, 0.0,
            0.0, 0.0, 0.0,
            0.0, 0.0, 0.0,
            0.0, 0.0, 1.0,
            0.0, 1.0, 1.0,
            1.0, 1.0, 1.0,
            1.0, 0.0, 0.0,
            1.0, 1.0, 0.0,
            1.0, 0.0, 0.0,
            1.0, 1.0, 1.0,
            1.0, 0.0, 1.0,
            0.0, 0.0, 0.0,
            1.0, 0.0, 0.0,
            1.0, 0.0, 1.0,
            1.0, 0.0, 1.0,
            0.0, 0.0, 1.0,
            0.0, 0.0, 0.0,
            0.0, 1.0, 0.0,
            1.0, 1.0, 1.0,
            1.0, 1.0, 0.0,
            1.0, 1.0, 1.0,
            0.0, 1.0, 0.0,
            0.0, 1.0, 1.0,
        };

        gl.NamedBufferStorage(
            gpu_sim.vertex_buffer,
            @sizeOf(@TypeOf(vertices)),
            &vertices,
            gl.DYNAMIC_STORAGE_BIT,
        );

        const buffer_length = sim.width * sim.height * sim.depth;

        gl.NamedBufferStorage(
            gpu_sim.simulation_material_buffers[0],
            buffer_length * @sizeOf(u16),
            null,
            gl.DYNAMIC_STORAGE_BIT,
        );

        gl.NamedBufferStorage(
            gpu_sim.simulation_material_buffers[1],
            buffer_length * @sizeOf(u16),
            null,
            gl.DYNAMIC_STORAGE_BIT,
        );

        gl.NamedBufferStorage(
            gpu_sim.simulation_temperature_buffers[0],
            buffer_length * @sizeOf(f32),
            null,
            gl.DYNAMIC_STORAGE_BIT,
        );

        gl.NamedBufferStorage(
            gpu_sim.simulation_temperature_buffers[1],
            buffer_length * @sizeOf(f32),
            null,
            gl.DYNAMIC_STORAGE_BIT,
        );

        gl.NamedBufferStorage(
            gpu_sim.simulation_deviation_buffers[0],
            buffer_length * @sizeOf(u8),
            null,
            gl.DYNAMIC_STORAGE_BIT,
        );

        gl.NamedBufferStorage(
            gpu_sim.simulation_deviation_buffers[1],
            buffer_length * @sizeOf(u8),
            null,
            gl.DYNAMIC_STORAGE_BIT,
        );

        gl.NamedBufferStorage(
            gpu_sim.heat_measurement_buffer,
            @sizeOf(f32),
            null,
            gl.DYNAMIC_STORAGE_BIT,
        );

        gl.NamedBufferData(
            gpu_sim.voxel_materials_buffer,
            @intCast(@sizeOf(VoxelMaterial) * sim.voxel_materials.items.len),
            sim.voxel_materials.items.ptr,
            gl.DYNAMIC_STORAGE_BIT,
        );

        gl.NamedBufferData(
            gpu_sim.voxel_materials_visual_buffer,
            @intCast(@sizeOf(VoxelMaterialVisual) * sim.voxel_materials_visual.items.len),
            sim.voxel_materials_visual.items.ptr,
            gl.DYNAMIC_STORAGE_BIT,
        );

        gl.NamedBufferData(
            gpu_sim.uniform_buffer,
            @sizeOf(ShaderUniforms),
            null,
            gl.DYNAMIC_DRAW,
        );

        return gpu_sim;
    }

    pub fn deinit() void {}

    pub fn updateCSGProgram(
        gpu_sim: *Simulation,
        sim: @import("../Simulation.zig"),
        program: CSGProgram,
    ) !void {
        if (program.instructions.items.len == 0) {
            return;
        }

        sim.csg_invocations.items[0].bound_min = .{ 0, 0, 0 };
        sim.csg_invocations.items[0].bound_max = .{
            @intCast(sim.width),
            @intCast(sim.height),
            @intCast(sim.depth),
        };

        gl.NamedBufferData(
            gpu_sim.csg_instruction_buffer,
            @intCast(program.instructions.items.len * @sizeOf(CSGInstruction)),
            program.instructions.items.ptr,
            gl.DYNAMIC_DRAW,
        );

        if (program.instructions_box.items.len > 0) {
            gl.NamedBufferData(
                gpu_sim.csg_instructions_box_buffer,
                @intCast(program.instructions_box.items.len * @sizeOf(CSGInstructionBox)),
                program.instructions_box.items.ptr,
                gl.DYNAMIC_DRAW,
            );
        }

        if (program.instructions_sphere.items.len > 0) {
            gl.NamedBufferData(
                gpu_sim.csg_instructions_sphere_buffer,
                @intCast(program.instructions_sphere.items.len * @sizeOf(CSGInstructionSphere)),
                program.instructions_sphere.items.ptr,
                gl.DYNAMIC_DRAW,
            );
        }

        if (program.instructions_extrude_post.items.len > 0) {
            gl.NamedBufferData(
                gpu_sim.csg_instructions_extrude_post_buffer,
                @intCast(program.instructions_extrude_post.items.len * @sizeOf(CSGInstructionExtrudePost)),
                program.instructions_extrude_post.items.ptr,
                gl.DYNAMIC_DRAW,
            );
        }

        gl.NamedBufferData(
            gpu_sim.csg_transform_buffer,
            @intCast(program.transforms.items.len * @sizeOf(CSGRigidTransform)),
            program.transforms.items.ptr,
            gl.DYNAMIC_DRAW,
        );
    }

    pub fn update(gpu_sim: *Simulation, sim: *@import("../Simulation.zig"), shader_uniforms: ShaderUniforms) void {
        gl.NamedBufferData(
            gpu_sim.voxel_materials_buffer,
            @intCast(@sizeOf(VoxelMaterial) * sim.voxel_materials.items.len),
            sim.voxel_materials.items.ptr,
            gl.DYNAMIC_DRAW,
        );
        gl.NamedBufferData(
            gpu_sim.voxel_materials_visual_buffer,
            @intCast(@sizeOf(VoxelMaterialVisual) * sim.voxel_materials_visual.items.len),
            sim.voxel_materials_visual.items.ptr,
            gl.DYNAMIC_DRAW,
        );

        gl.NamedBufferSubData(
            gpu_sim.uniform_buffer,
            0,
            @sizeOf(ShaderUniforms),
            &shader_uniforms,
        );
        gl.NamedBufferData(
            gpu_sim.point_light_buffer,
            @intCast(@sizeOf(PointLight) * sim.point_lights.items.len),
            sim.point_lights.items.ptr,
            gl.DYNAMIC_DRAW,
        );

        gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, gpu_sim.uniform_buffer);
        gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 0, gpu_sim.simulation_temperature_buffers[0]);
        gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 1, gpu_sim.simulation_temperature_buffers[1]);
        gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 2, gpu_sim.voxel_materials_buffer);
        gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 23, gpu_sim.voxel_materials_visual_buffer);
        gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 3, 0);
        gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 4, gpu_sim.simulation_material_buffers[0]);
        gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 10, gpu_sim.csg_transform_buffer);
        gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 11, gpu_sim.csg_instruction_buffer);
        gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 12, gpu_sim.csg_instructions_box_buffer);
        gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 13, gpu_sim.csg_instructions_sphere_buffer);
        gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 30, gpu_sim.csg_instructions_extrude_post_buffer);
        gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 14, gpu_sim.csg_composite_material_buffer);
        gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 20, gpu_sim.simulation_deviation_buffers[0]);
        gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 21, gpu_sim.simulation_deviation_buffers[1]);
        gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 22, gpu_sim.point_light_buffer);
        gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 32, gpu_sim.heat_measurement_buffer);

        if (sim.gpu_sim.shaders.fill_region_shader != sim.gpu_sim.shaders.old_fill_region_shader) {
            sim.csg_dirty = true;
        }

        if (!sim.enable_simulation and sim.csg_dirty) {
            gl.UseProgram(gpu_sim.shaders.fill_region_shader);

            sim.csg_dirty = false;

            const material_clear: u16 = 0;
            const temperature_clear: f32 = 0;
            const deviation_clear: u8 = 0;

            gl.ClearNamedBufferData(
                gpu_sim.simulation_material_buffers[0],
                gl.R16UI,
                gl.RED,
                gl.UNSIGNED_SHORT,
                &material_clear,
            );
            gl.ClearNamedBufferData(
                gpu_sim.simulation_temperature_buffers[0],
                gl.R32UI,
                gl.RED,
                gl.FLOAT,
                &temperature_clear,
            );
            gl.ClearNamedBufferData(
                gpu_sim.simulation_deviation_buffers[0],
                gl.R8I,
                gl.RED,
                gl.BYTE,
                &deviation_clear,
            );

            gl.DispatchCompute(
                sim.width / 8,
                sim.height / 8,
                sim.depth / 8,
            );
        }

        gl.MemoryBarrier(gl.SHADER_STORAGE_BARRIER_BIT);

        if (sim.enable_simulation) {
            gl.ClearNamedBufferData(
                gpu_sim.heat_measurement_buffer,
                gl.R32F,
                gl.RED,
                gl.FLOAT,
                &@as(f32, 0),
            );

            gl.MemoryBarrier(gl.SHADER_STORAGE_BARRIER_BIT);

            gl.UseProgram(gpu_sim.shaders.thermal_shader);
            gl.DispatchCompute(
                sim.width / 8,
                sim.height / 8,
                sim.depth / 8,
            );
            gl.MemoryBarrier(gl.SHADER_STORAGE_BARRIER_BIT);

            gl.UseProgram(gpu_sim.shaders.grain_simulation_shader);
            gl.BindBufferBase(
                gl.SHADER_STORAGE_BUFFER,
                2,
                gpu_sim.voxel_materials_buffer,
            );

            gl.BindBufferBase(
                gl.SHADER_STORAGE_BUFFER,
                4,
                gpu_sim.simulation_material_buffers[0],
            );
            gl.BindBufferBase(
                gl.SHADER_STORAGE_BUFFER,
                5,
                gpu_sim.simulation_material_buffers[1],
            );

            gl.BindBufferBase(
                gl.SHADER_STORAGE_BUFFER,
                6,
                gpu_sim.simulation_temperature_buffers[1],
            );
            gl.BindBufferBase(
                gl.SHADER_STORAGE_BUFFER,
                7,
                gpu_sim.simulation_temperature_buffers[0],
            );

            gl.DispatchCompute(
                sim.width / 8,
                sim.height / 8,
                sim.depth / 8,
            );

            gl.MemoryBarrier(gl.SHADER_STORAGE_BARRIER_BIT);

            gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 3, 0);
            gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 2, 0);
            gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 1, 0);
            gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 0, 0);
            gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, 0);
        }

        if (sim.enable_simulation) {
            std.mem.swap(
                u32,
                &gpu_sim.simulation_material_buffers[0],
                &gpu_sim.simulation_material_buffers[1],
            );

            std.mem.swap(
                u32,
                &gpu_sim.simulation_deviation_buffers[0],
                &gpu_sim.simulation_deviation_buffers[1],
            );

            sim.timestep_index += 1;

            gl.MemoryBarrier(gl.SHADER_STORAGE_BARRIER_BIT);

            //TODO: hard cpu-gpu sync here, must change when porting to vulkan
            gl.GetNamedBufferSubData(
                gpu_sim.heat_measurement_buffer,
                0,
                @sizeOf(i32),
                &sim.measured_heat,
            );
        }

        gpu_sim.shaders.old_fill_region_shader = gpu_sim.shaders.fill_region_shader;
    }

    pub fn render(
        sim: Simulation,
        context: Context,
        shader_uniforms: ShaderUniforms,
        render_texture: ?*Texture,
    ) void {
        gl.NamedBufferSubData(
            sim.uniform_buffer,
            0,
            @sizeOf(ShaderUniforms),
            &shader_uniforms,
        );

        gl.BindBufferBase(
            gl.SHADER_STORAGE_BUFFER,
            0,
            sim.voxel_materials_buffer,
        );
        gl.BindBufferBase(
            gl.SHADER_STORAGE_BUFFER,
            1,
            sim.simulation_material_buffers[0],
        );
        gl.BindBufferBase(
            gl.SHADER_STORAGE_BUFFER,
            2,
            sim.simulation_temperature_buffers[0],
        );
        gl.BindBufferBase(
            gl.SHADER_STORAGE_BUFFER,
            21,
            sim.simulation_deviation_buffers[0],
        );

        gl.BindBufferBase(
            gl.SHADER_STORAGE_BUFFER,
            22,
            sim.point_light_buffer,
        );

        gl.MemoryBarrier(gl.SHADER_IMAGE_ACCESS_BARRIER_BIT);

        var framebuffer: u32 = 0;
        var renderbuffer: u32 = 0;

        if (render_texture) |texture| {
            gl.CreateFramebuffers(1, @ptrCast(&framebuffer));

            gl.BindFramebuffer(gl.FRAMEBUFFER, framebuffer);
            gl.FramebufferTexture2D(
                gl.FRAMEBUFFER,
                gl.COLOR_ATTACHMENT0,
                gl.TEXTURE_2D,
                @intCast(@intFromPtr(texture)),
                0,
            );

            gl.CreateRenderbuffers(1, @ptrCast(&renderbuffer));

            gl.BindRenderbuffer(gl.RENDERBUFFER, renderbuffer);
            gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH24_STENCIL8, 128, 128);
            gl.BindRenderbuffer(gl.RENDERBUFFER, 0);

            gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_STENCIL_ATTACHMENT, gl.RENDERBUFFER, renderbuffer);

            gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
        }

        gl.UseProgram(context.env_map_shader);
        gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, sim.uniform_buffer);
        gl.BindTexture(gl.TEXTURE_2D, context.env_map_texture);
        gl.BindTextureUnit(2, context.env_map_texture);

        gl.BindVertexArray(sim.vertex_array);
        gl.Disable(gl.CULL_FACE);
        gl.DrawArrays(gl.TRIANGLES, 0, 36);

        gl.UseProgram(sim.shaders.renderer_program);
        gl.BindVertexArray(sim.vertex_array);
        gl.CullFace(gl.FRONT);
        defer gl.CullFace(gl.BACK);
        gl.Enable(gl.CULL_FACE);

        gl.DrawArrays(gl.TRIANGLES, 0, 36);

        gl.BindFramebuffer(gl.FRAMEBUFFER, 0);

        if (render_texture) |_| {
            gl.DeleteFramebuffers(1, @ptrCast(&framebuffer));
            gl.DeleteRenderbuffers(1, @ptrCast(&renderbuffer));
        }
    }

    pub fn renderSceneThumbnail(
        gpu_sim: *Simulation,
        context: Context,
        sim: *@import("../Simulation.zig"),
        scene: *CSGTree,
        scene_path: []const u8,
        gpa: std.mem.Allocator,
    ) !?*Texture {
        var scene_program: CSGProgram = .{};

        try scene.compile(gpa, &scene_program);
        sim.csg_dirty = true;

        try sim.updateCSGProgram(scene_program);

        const is_enabled: bool = sim.enable_simulation;
        sim.update();

        const thumbnail_result = try gpu_sim.scene_thumbnails.getOrPut(gpa, std.fs.path.basename(scene_path));

        var texture_handle: u32 = 0;
        gl.CreateTextures(gl.TEXTURE_2D, 1, @ptrCast(&texture_handle));

        thumbnail_result.value_ptr.* = @ptrFromInt(texture_handle);

        gl.TextureStorage2D(texture_handle, 1, gl.RGBA8, 128, 128);
        gl.Viewport(0, 0, 128, 128);

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

        gl.UseProgram(context.env_map_shader);
        gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, gpu_sim.uniform_buffer);
        gl.BindTexture(gl.TEXTURE_2D, context.env_map_texture);
        gl.BindTextureUnit(2, context.env_map_texture);

        gl.BindVertexArray(gpu_sim.vertex_array);
        gl.Disable(gl.CULL_FACE);
        gl.DrawArrays(gl.TRIANGLES, 0, 36);

        sim.render(context, thumbnail_result.value_ptr.*);

        sim.enable_simulation = is_enabled;
        return null;
    }
};

pub const ShaderSource = struct {
    type: u32 = 0,
    source_path: []const u8,
};

pub fn loadShader(source: struct {
    type: u32,
    binary: []const u8,
}) !u32 {
    const shader = gl.CreateShader(source.type);

    gl.ShaderBinary(
        1,
        @ptrCast(&shader),
        gl.SHADER_BINARY_FORMAT_SPIR_V,
        source.binary.ptr,
        @intCast(source.binary.len),
    );

    gl.SpecializeShader(
        shader,
        "main",
        0,
        undefined,
        undefined,
    );

    var success: i32 = 0;

    gl.GetShaderiv(
        shader,
        gl.COMPILE_STATUS,
        @ptrCast(&success),
    );

    if (success == 0) {
        return error.ShaderRejectedBinary;
    }

    return shader;
}

const ShaderUniforms = @import("../Simulation.zig").ShaderUniforms;
const VoxelMaterial = @import("../Simulation.zig").VoxelMaterial;
const VoxelMaterialVisual = @import("../Simulation.zig").VoxelMaterialVisual;
const PointLight = @import("../Simulation.zig").PointLight;
const CSGProgram = @import("../Simulation.zig").CSGProgram;
const CSGTree = @import("../main.zig").CSGTree;
const CSGRigidTransform = @import("../Simulation.zig").CSGRigidTransform;
const CSGInstruction = @import("../Simulation.zig").CSGInstruction;
const CSGInstructionBox = @import("../Simulation.zig").CSGInstructionBox;
const CSGInstructionSphere = @import("../Simulation.zig").CSGInstructionSphere;
const CSGInstructionExtrudePost = @import("../Simulation.zig").CSGInstructionExtrudePost;
const std = @import("std");
const Texture = @import("../gpu.zig").Texture;
const gl = @import("gl");
const imgui = @import("../imgui.zig");
const glfw = @import("zglfw");
const stb_image = @import("../stb_image.zig");
const zmath = @import("zmath");
