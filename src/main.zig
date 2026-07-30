pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(arena);
    _ = args; // autofix

    if (@import("builtin").os.tag == .linux and @import("builtin").mode == .Debug) {
        //We do this in debug mode so that we can do renderdoc captures
        //try glfw.initHint(.platform, glfw.Platform.x11);
    }

    try glfw.init();
    defer glfw.terminate();

    glfw.windowHint(.context_version_major, 4);
    glfw.windowHint(.context_version_minor, 6);
    glfw.windowHint(.opengl_debug_context, true);
    glfw.windowHint(.opengl_profile, .opengl_core_profile);

    const window = try glfw.createWindow(
        640,
        480,
        "Chemica",
        null,
        null,
    );
    defer window.destroy();

    window.maximize();
    glfw.makeContextCurrent(window);
    glfw.swapInterval(0);

    var gl_procs: gl.ProcTable = undefined;

    if (!gl_procs.init(glfw.getProcAddress)) return error.GLInitFailed;

    gl.makeProcTableCurrent(&gl_procs);
    defer gl.makeProcTableCurrent(null);

    gl.Enable(gl.BLEND);
    gl.Enable(gl.DEPTH_TEST);
    gl.Enable(gl.CULL_FACE);
    gl.CullFace(gl.BACK);
    gl.FrontFace(gl.CCW);
    gl.DepthMask(1);
    gl.DepthFunc(gl.LESS);
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

    var simulation: Simulation = try .init(
        arena,
        @bitCast(window.getSize()),
    );
    defer simulation.deinit(arena);

    var voxel_material_names: std.ArrayList([]const u8) = .empty;

    try simulation.voxel_materials.append(arena, .{
        .heat_conductivity = 0,
    });
    try simulation.voxel_materials_visual.append(arena, .{});
    try voxel_material_names.append(arena, "Air");

    try simulation.voxel_materials.append(arena, .{
        .heat_conductivity = 0.5,
    });
    try simulation.voxel_materials_visual.append(arena, .{
        .albedo = packUnorm4x8(.{ 0.89, 0.79, 0.55, 1.0 }),
    });
    try voxel_material_names.append(arena, "Sand");

    try simulation.voxel_materials.append(arena, .{
        .heat_conductivity = 1,
        .melting_point = 1000,
    });
    try simulation.voxel_materials_visual.append(arena, .{
        .albedo = packUnorm4x8(.{ 0.29, 0.29, 0.29, 1.0 }),
    });
    try voxel_material_names.append(arena, "Stone");

    try simulation.voxel_materials.append(arena, .{
        .heat_conductivity = 0.9,
        .melting_point = 0,
        .density = 0.5,
    });
    try simulation.voxel_materials_visual.append(arena, .{
        .albedo = packUnorm4x8(.{ 0.17, 0.56, 0.82, 0.19 }),
    });
    try voxel_material_names.append(arena, "Water");

    try simulation.voxel_materials.append(arena, .{
        .heat_conductivity = 3,
        .melting_point = 3000,
        .boiling_point = 4000,
    });
    try simulation.voxel_materials_visual.append(arena, .{
        .albedo = 0xff1d2971,
    });
    try voxel_material_names.append(arena, "Copper");

    if (true) {
        simulation.voxel_materials.clearAndFree(arena);
        simulation.voxel_materials_visual.clearAndFree(arena);
        voxel_material_names.clearAndFree(arena);

        try simulation.voxel_materials.append(arena, .{
            .heat_conductivity = 0,
        });
        try simulation.voxel_materials_visual.append(arena, .{});
        try voxel_material_names.append(arena, "Air");

        const materials_file_source = @embedFile("assets/pbr_materials.json");

        const PbrMaterialsJson = struct {
            data: []Material,

            const Material = struct {
                name: []const u8,
                color: []Color,
                metalness: f32 = 1,
                roughness: f32 = 1,
                density: []const f32 = &.{1},
                transmission: f32 = 0,
                ior: f32 = 1,

                pub const Color = struct {
                    colorSpace: []const u8,
                    color: [3]f32,
                };
            };
        };

        const materials_json_parsed = try std.json.parseFromSlice(
            PbrMaterialsJson,
            arena,
            materials_file_source,
            .{ .ignore_unknown_fields = true },
        );

        const materials_json = materials_json_parsed.value;

        for (materials_json.data) |material| {
            try voxel_material_names.append(arena, material.name);
            try simulation.voxel_materials_visual.append(arena, .{
                .albedo = packUnorm4x8(
                    .{
                        material.color[0].color[0],
                        material.color[0].color[1],
                        material.color[0].color[2],
                        1 - material.transmission,
                    },
                ),
                .roughness_metalness = packUnorm4x8(.{
                    material.roughness + 0.25,
                    material.metalness,
                    0,
                    0,
                }),
                .refractive_index = material.ior,
            });
            try simulation.voxel_materials.append(arena, .{
                .density = material.density[0],
            });
        }
    }

    const voxel_material_names_ptrs = try arena.alloc([*]const u8, voxel_material_names.items.len);

    for (voxel_material_names_ptrs, voxel_material_names.items) |*ptr, name| {
        ptr.* = name.ptr;
    }

    try simulation.csg_invocations.append(arena, .{
        .transform = .identity,
        .bound_min = undefined,
        .bound_max = undefined,
    });

    _ = imgui.createContext(.{});

    try imgui.impl.glfw.initForOpenGL(window, .{});
    defer imgui.impl.glfw.shutdown();

    try imgui.impl.opengl3.init(.{});
    defer imgui.impl.opengl3.shutdown();

    imguiStyleSetup();

    imgui.loadIniSettingsFromMemory(@embedFile("assets/imgui.ini"));

    defer blk: {
        std.Io.Dir.cwd().access(init.io, "src/assets/", .{}) catch |e| {
            switch (e) {
                error.FileNotFound => {
                    imgui.getIO().WantSaveIniSettings = false;
                    break :blk;
                },
                else => @panic(""),
            }
        };

        imgui.saveIniSettingsToDisk("src/assets/imgui.ini");
    }

    var last_mouse_pos: [2]f32 = undefined;

    last_mouse_pos[0] = @floatCast(window.getCursorPos()[0]);
    last_mouse_pos[1] = @floatCast(window.getCursorPos()[1]);

    var camera: Camera = .{
        .eye = .{ 90, 90, 90 },
        .target = .{ 0, 0, 0 },
        .fov = std.math.degreesToRadians(70),
        .zoom = 1,
        .near = 0.1,
        .far = 1000,
        .projection = @bitCast(zmath.identity()),
        .view = @bitCast(zmath.identity()),
    };

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

    var env_map_texture: u32 = 0;

    gl.CreateTextures(gl.TEXTURE_2D, 1, @ptrCast(&env_map_texture));
    gl.TextureStorage2D(
        env_map_texture,
        1,
        gl.RGB8,
        env_map_width,
        env_map_height,
    );
    gl.TextureSubImage2D(
        env_map_texture,
        0,
        0,
        0,
        env_map_width,
        env_map_height,
        gl.RGB,
        gl.UNSIGNED_BYTE,
        env_map_data,
    );

    const env_map_shader = try Simulation.loadShaderProgram(arena, &.{
        .{ .type = gl.VERTEX_SHADER, .binary = @embedFile("shaders/Include/EnvMapVertex.spv") },
        .{ .type = gl.FRAGMENT_SHADER, .binary = @embedFile("shaders/Include/EnvMapFragment.spv") },
    });
    defer gl.DeleteProgram(env_map_shader);

    _ = window.setScrollCallback(glfwScrollCallback);
    var mouse_scroll: f32 = 0;

    window.setUserPointer(&mouse_scroll);

    var csg_tree: CSGTree = try .init(arena);

    csg_tree = try .initFromZonMemory(@embedFile("assets/test_scenes/metal_spheres.chemc.zon"), arena);

    var selected_node_handles: std.ArrayList(CSGTreeNodeHandle) = .empty;
    var node_parents: std.ArrayList(CSGTreeNodeHandle) = .empty;
    var selected_node_parents: std.ArrayList(std.ArrayList(CSGTreeNodeHandle)) = .empty;
    var copied_node_handles: std.ArrayList(CSGTreeNodeHandle) = .empty;
    var copied_node_parents: std.ArrayList(std.ArrayList(CSGTreeNodeHandle)) = .empty;

    var csg_program: Simulation.CSGProgram = .{};

    var csg_reparent_commands: std.ArrayList(CSGReparentCommand) = .empty;

    try simulation.point_lights.append(arena, .{
        .position = .{ 128, 128, 64 },
        .radiance = 1,
        .colour = packUnorm4x8(.{ 0.5, 0.5, 0.5, 1 }),
    });

    camera.target = .{
        @floatFromInt(simulation.width / 2),
        @floatFromInt(simulation.height / 2),
        @floatFromInt(simulation.depth / 2),
    };

    simulation.enable_simulation = false;

    imgui.getIO().ConfigFlags |= imgui.cimgui.ImGuiConfigFlags_DockingEnable;

    var maybe_sim_file: ?std.Io.File = null;
    defer if (maybe_sim_file) |sim_file| sim_file.close(init.io);

    var sim_file_path: []const u8 = "";

    defer if (maybe_sim_file) |sim_file| {
        csg_tree.saveToFile(init.io, sim_file) catch @panic("");
    };

    const heat_measurement_values = try arena.alloc(f32, 512);

    const enthalpy_change_values = try arena.alloc(f32, 512);

    const dir_to_browse = try std.Io.Dir.cwd().openDir(
        init.io,
        "src/assets/test_scenes",
        .{ .iterate = true },
    );

    defer dir_to_browse.close(init.io);

    var thumbnail_gen_queue: std.ArrayList([]const u8) = .empty;

    //Array of opengl textures
    var file_thumbnails: std.StringHashMapUnmanaged(u32) = .empty;

    {
        var iter = dir_to_browse.iterate();

        while (try iter.next(init.io)) |entry| {
            if (std.mem.containsAtLeast(u8, entry.name, 1, ".chemc.zon")) {
                try thumbnail_gen_queue.append(arena, try dir_to_browse.realPathFileAlloc(init.io, entry.name, arena));
            }
        }
    }

    imgui.getIO().WantSaveIniSettings = false;
    imgui.getIO().IniSavingRate = 0;

    while (!window.shouldClose()) {
        glfw.pollEvents();

        gl.BindFramebuffer(gl.FRAMEBUFFER, 0);

        gl.ClearColor(0, 0, 0, 1);
        gl.ClearDepthf(1);
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        imgui.impl.glfw.newFrame();
        imgui.impl.opengl3.newFrame();

        const framebuffer_size = window.getFramebufferSize();

        gl.Viewport(0, 0, framebuffer_size[0], framebuffer_size[1]);

        //Camera Controls
        {
            const cursor_pos_f64: [2]f64 = window.getCursorPos();
            const cursor_pos: [2]f32 = .{
                @floatCast(cursor_pos_f64[0]),
                @floatCast(cursor_pos_f64[1]),
            };

            const cursor_delta_x = cursor_pos[0] - last_mouse_pos[0];
            const cursor_delta_y = cursor_pos[1] - last_mouse_pos[1];

            const norm_delta_x = cursor_delta_x / @as(f32, @floatFromInt(window.getSize()[0]));
            const norm_delta_y = cursor_delta_y / @as(f32, @floatFromInt(window.getSize()[1]));

            const angle_x = norm_delta_x * std.math.tau;
            const angle_y = norm_delta_y * std.math.tau;

            const rotation_x = zmath.quatFromAxisAngle(.{ 0, 1, 0, 0 }, -angle_x);
            const rotation_y = zmath.quatFromAxisAngle(.{ 0, 0, 1, 0 }, angle_y);
            const rotation = math.mulQuat(rotation_x, rotation_y);

            var new_eye = zmath.rotate(rotation, .{
                camera.eye[0] - camera.target[0],
                camera.eye[1] - camera.target[1],
                camera.eye[2] - camera.target[2],
                0,
            });

            new_eye += .{ camera.target[0], camera.target[1], camera.target[2], 0 };

            if (window.getMouseButton(.left) != .release and !imgui.isAnyItemActive() and !imguizmo.ImGuizmo_IsUsing()) {
                camera.eye = .{ new_eye[0], new_eye[1], new_eye[2] };
            }

            const zoom_factor: @Vector(3, f32) = @splat(std.math.clamp(mouse_scroll, -1, 1));

            var eye: @Vector(3, f32) = camera.eye;
            const target: @Vector(3, f32) = camera.target;

            eye += zoom_factor * (eye - target);
            mouse_scroll = 0;

            camera.eye = eye;

            last_mouse_pos = cursor_pos;
        }

        gl.BindTextureUnit(22, env_map_texture);

        //Thumbnail gen
        {
            if (thumbnail_gen_queue.pop()) |scene_path| {
                const scene_file = try std.Io.Dir.cwd().openFile(init.io, scene_path, .{});
                defer scene_file.close(init.io);

                var scene: CSGTree = try .initFromFile(init.io, scene_file, gpa);
                defer scene.nodes.deinit(gpa);

                var scene_program: Simulation.CSGProgram = .{};

                try scene.compile(gpa, &scene_program);
                simulation.csg_dirty = true;

                try simulation.updateCSGProgram(scene_program);

                const is_enabled: bool = simulation.enable_simulation;
                simulation.update();

                const thumbnail_result = try file_thumbnails.getOrPut(arena, std.fs.path.basename(scene_path));

                gl.CreateTextures(gl.TEXTURE_2D, 1, @ptrCast(thumbnail_result.value_ptr));
                gl.TextureStorage2D(thumbnail_result.value_ptr.*, 1, gl.RGBA8, 128, 128);
                gl.Viewport(0, 0, 128, 128);

                simulation.projection_matrix = @bitCast((zmath.perspectiveFovRhGl(
                    camera.fov,
                    @as(f32, @floatFromInt(128)) / @as(f32, @floatFromInt(128)),
                    camera.near,
                    camera.far,
                )));
                simulation.view_matrix = @bitCast((zmath.lookAtRh(
                    .{ 128, 128, 128, 0 },
                    .{ 0, 0, 0, 0 },
                    .{ 0, 1, 0, 0 },
                )));

                gl.UseProgram(env_map_shader);
                gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, simulation.uniform_buffer);
                gl.BindTexture(gl.TEXTURE_2D, env_map_texture);
                gl.BindTextureUnit(2, env_map_texture);

                gl.BindVertexArray(simulation.vertex_array);
                gl.Disable(gl.CULL_FACE);
                gl.DrawArrays(gl.TRIANGLES, 0, 36);

                simulation.render(thumbnail_result.value_ptr.*);

                simulation.enable_simulation = is_enabled;
            }
        }

        camera.projection = @bitCast((zmath.perspectiveFovRhGl(
            camera.fov,
            @as(f32, @floatFromInt(window.getSize()[0])) / @as(f32, @floatFromInt(window.getSize()[1])),
            camera.near,
            camera.far,
        )));
        camera.view = @bitCast((zmath.lookAtRh(
            .{ camera.eye[0], camera.eye[1], camera.eye[2], 0 },
            .{ camera.target[0], camera.target[1], camera.target[2], 0 },
            .{ 0, 1, 0, 0 },
        )));

        simulation.model_matrix = @bitCast(zmath.transpose(zmath.identity()));
        simulation.view_matrix = camera.view;
        simulation.projection_matrix = camera.projection;

        try csg_tree.compile(arena, &csg_program);

        try simulation.updateCSGProgram(csg_program);

        simulation.update();

        gl.UseProgram(env_map_shader);
        gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, simulation.uniform_buffer);
        gl.BindTexture(gl.TEXTURE_2D, env_map_texture);
        gl.BindTextureUnit(2, env_map_texture);

        gl.BindVertexArray(simulation.vertex_array);
        gl.Disable(gl.CULL_FACE);
        gl.DrawArrays(gl.TRIANGLES, 0, 36);

        const previous_enthalpy = heat_measurement_values[(simulation.timestep_index -| 1) % (heat_measurement_values.len)];

        heat_measurement_values[simulation.timestep_index % (heat_measurement_values.len)] = @floatFromInt(simulation.measured_heat);
        heat_measurement_values[simulation.timestep_index % (heat_measurement_values.len)] /= @floatFromInt(1);

        enthalpy_change_values[simulation.timestep_index % (enthalpy_change_values.len)] = @as(f32, @floatFromInt(simulation.measured_heat)) - previous_enthalpy;

        simulation.render(null);

        if (imgui.isKeyPressed(imgui.cimgui.ImGuiKey_Space)) {
            simulation.enable_simulation = !simulation.enable_simulation;
        }

        if (window.getKey(.r) == .press) {
            simulation.csg_dirty = true;
            simulation.enable_simulation = false;
        }

        if (imgui.isKeyPressed(imgui.cimgui.ImGuiKey_Delete)) {
            for (selected_node_handles.items, 0..) |selected_node, i| {
                const maybe_node_index = std.mem.find(
                    CSGTreeNodeHandle,
                    csg_tree.getNode(.root).children.items,
                    &.{selected_node},
                );

                if (maybe_node_index) |node_index| {
                    csg_tree.deleteNode(
                        gpa,
                        .root,
                        node_index,
                    );

                    _ = selected_node_handles.swapRemove(i);
                    if (selected_node_parents.items.len != 0) {
                        _ = selected_node_parents.swapRemove(i);
                    }

                    simulation.csg_dirty = true;
                }
            }
        }

        imgui.newFrame();

        _ = imgui.dockspaceOverViewport(.{});

        {
            imguizmo.beginFrame();

            imguizmo.setRect(
                0,
                0,
                @floatFromInt(window.getSize()[0]),
                @floatFromInt(window.getSize()[1]),
            );

            imguizmo.enable(true);

            if (imgui.isKeyPressed(imgui.cimgui.ImGuiKey_F)) {
                if (selected_node_handles.items.len != 0) {
                    camera.target = csg_tree.getNode(selected_node_handles.items[0]).transform.position;
                }
            }

            if (selected_node_handles.items.len != 0 and !imgui.isAnyItemActive()) blk: {
                var pressed: bool = false;

                var name: [:0]const u8 = "";
                var unary_op: Simulation.CSGInstructionOp = .identity;
                var child_op: Simulation.CSGInstructionOp = .binary_op_union;

                if (imgui.isKeyPressed(imgui.cimgui.ImGuiKey_E)) {
                    pressed = true;
                    name = "Extrude";
                    unary_op = .unary_op_extrude_pre;
                }

                if (imgui.isKeyPressed(imgui.cimgui.ImGuiKey_R) and imgui.isKeyDown(imgui.cimgui.ImGuiKey_LeftCtrl)) {
                    pressed = true;
                    name = "Revolve";
                    unary_op = .unary_op_revolve;
                }

                if (imgui.isKeyPressed(imgui.cimgui.ImGuiKey_U)) {
                    pressed = true;

                    child_op = .binary_op_union;
                    name = "Union";

                    if (imgui.isKeyDown(imgui.cimgui.ImGuiKey_S)) {
                        child_op = .binary_op_smooth_union;
                        name = "Smooth Union";
                    }
                }
                if (imgui.isKeyPressed(imgui.cimgui.ImGuiKey_I)) {
                    pressed = true;

                    child_op = .binary_op_intersection;
                    name = "Intersection";

                    if (imgui.isKeyDown(imgui.cimgui.ImGuiKey_S)) {
                        child_op = .binary_op_smooth_intersection;
                        name = "Smooth Intersection";
                    }
                }
                if (imgui.isKeyPressed(imgui.cimgui.ImGuiKey_D)) {
                    pressed = true;

                    child_op = .binary_op_difference;
                    name = "Difference";

                    if (imgui.isKeyDown(imgui.cimgui.ImGuiKey_S)) {
                        child_op = .binary_op_smooth_difference;
                        name = "Smooth Difference";
                    }
                }

                if (!pressed) break :blk;

                const union_node_handle = try csg_tree.addNode(arena, .root);

                const union_node = csg_tree.getNode(union_node_handle);
                union_node.* = .{};

                union_node.unary_op = unary_op;
                union_node.child_op = child_op;
                union_node.name = name;

                if (union_node.unary_op == .unary_op_extrude_pre) {
                    union_node.data = .{ .extrude = .{ .h = 10 } };
                }

                var midpoint: @Vector(3, f32) = @splat(0);

                for (selected_node_handles.items) |selected_node_handle| {
                    const selected_node = csg_tree.getNode(selected_node_handle);

                    midpoint += selected_node.transform.position;

                    try csg_tree.moveNode(
                        arena,
                        selected_node_handle,
                        .root,
                        union_node_handle,
                    );
                }

                union_node.transform.position = midpoint / @as(@Vector(3, f32), @splat(@floatFromInt(selected_node_handles.items.len)));

                for (selected_node_handles.items) |selected_node_handle| {
                    const selected_node = csg_tree.getNode(selected_node_handle);

                    selected_node.transform.position[0] -= union_node.transform.position[0];
                    selected_node.transform.position[1] -= union_node.transform.position[1];
                    selected_node.transform.position[2] -= union_node.transform.position[2];
                    selected_node.transform.uniform_scale = 1;
                }

                selected_node_handles.clearRetainingCapacity();
                try selected_node_handles.append(arena, union_node_handle);

                simulation.csg_dirty = true;
            }

            imgui.showDemoWindow(.{});

            var csg_editor_window_pos: [2]f32 = undefined;

            const enable_nfd = true;

            if (imgui.begin("CSG Editor", .{})) {
                csg_editor_window_pos = @bitCast(imgui.cimgui.ImGui_GetWindowPos());

                if (true or imgui.beginMenuBar()) {
                    if (imgui.beginMenu("File", .{})) {
                        defer imgui.endMenu();
                        if (imgui.menuItem("New", .{})) {
                            csg_tree.nodes.deinit(arena);
                            selected_node_handles.clearRetainingCapacity();
                            selected_node_parents.clearRetainingCapacity();
                            csg_tree = try .init(arena);
                            csg_program.instructions.clearRetainingCapacity();
                            simulation.csg_dirty = true;
                            maybe_sim_file = null;
                        }
                        if (imgui.menuItem("Open", .{})) {
                            if (enable_nfd) {
                                const nfd = @import("nfd");
                                const maybe_path = try nfd.openFileDialog("*.zon", ".");

                                if (maybe_path) |path| {
                                    csg_tree.nodes.deinit(arena);
                                    const file = try std.Io.Dir.cwd().openFile(init.io, path, .{
                                        .mode = .read_write,
                                    });

                                    if (maybe_sim_file) |sim_file| {
                                        sim_file.close(init.io);
                                    }

                                    selected_node_handles.clearRetainingCapacity();
                                    selected_node_parents.clearRetainingCapacity();

                                    csg_program.instructions.clearRetainingCapacity();

                                    csg_tree = try .initFromFile(init.io, file, arena);

                                    sim_file_path = try std.Io.Dir.cwd().realPathFileAlloc(init.io, path, arena);
                                    maybe_sim_file = file;
                                    simulation.csg_dirty = true;
                                    simulation.enable_simulation = false;
                                }
                            }
                        }
                        if (imgui.menuItem("Save", .{ .shortcut = "Ctrl+S" })) {
                            if (maybe_sim_file) |sim_file| {
                                try csg_tree.saveToFile(init.io, sim_file);

                                try thumbnail_gen_queue.append(arena, sim_file_path);
                            }
                        }
                        if (imgui.menuItem("Save As...", .{})) {
                            if (enable_nfd) {
                                const nfd = @import("nfd");
                                const maybe_path = try nfd.saveFileDialog("*.zon", "./src/assets/test_scenes");

                                if (maybe_path) |path| {
                                    const file = try std.Io.Dir.cwd().createFile(init.io, path, .{});
                                    sim_file_path = try std.Io.Dir.cwd().realPathFileAlloc(init.io, path, arena);

                                    if (maybe_sim_file) |sim_file| {
                                        sim_file.close(init.io);
                                    }
                                    maybe_sim_file = file;

                                    try csg_tree.saveToFile(init.io, file);
                                }
                            }
                        }
                    }
                }

                imgui.separator(.{});

                imgui.text("Transform", .{});

                if (selected_node_handles.items.len != 0) {
                    const selected_node = csg_tree.getNode(selected_node_handles.items[0]);

                    simulation.csg_dirty |= imgui.dragFloat3(
                        "Translation",
                        "{}",
                        @ptrCast(&selected_node.transform.position[0]),
                        .{},
                    );

                    simulation.csg_dirty |= imgui.dragFloat(
                        "Scale",
                        "{}",
                        &selected_node.transform.uniform_scale,
                        .{},
                    );

                    simulation.csg_dirty |= imgui.dragFloat3(
                        "Rotation",
                        "{}",
                        @ptrCast(&selected_node.transform.rotation[0]),
                        .{},
                    );

                    //selected_node.transform.rotation = zmath.normalize4(selected_node.transform.rotation);

                    if (selected_node.material != .air) {
                        var material: usize = @intFromEnum(selected_node.material);

                        //simulation.csg_dirty |= imgui.combo("Material", &material, voxel_material_names_ptrs);

                        var input_buffer: [1024]u8 = [1]u8{0} ** 1024;

                        for (voxel_material_names.items, 0..) |mat_name, mat_id| {
                            if (mat_id == material) {
                                std.mem.copyForwards(u8, &input_buffer, mat_name);
                            }
                        }

                        if (imgui.inputText(
                            "Material",
                            &input_buffer,
                            .{},
                        )) |str| {
                            for (voxel_material_names.items, 0..) |mat_name, mat_id| {
                                if (std.mem.eql(u8, mat_name, str)) {
                                    material = mat_id;
                                    simulation.csg_dirty = true;
                                    break;
                                }
                            }
                        }

                        selected_node.material = @enumFromInt(material);
                    }

                    if (selected_node.data == .extrude) {
                        simulation.csg_dirty |= imgui.dragFloat(
                            "Extrusion",
                            "{}",
                            &selected_node.data.extrude.h,
                            .{},
                        );
                    }
                }

                if (imgui.button("Add Node", .{})) {
                    imgui.openPopup("node_type_popup");
                }

                if (imgui.beginPopup("node_type_popup")) {
                    if (imgui.selectable("Box")) {
                        const node_handle = try csg_tree.addNode(arena, .root);

                        const node = csg_tree.getNode(node_handle);

                        node.* = .{};
                        node.data = .{
                            .box = .{ .bounds = .{ 10, 10, 10 } },
                        };
                        node.transform = .identity;
                        node.transform.position = .{
                            @floatFromInt(simulation.width / 2),
                            @floatFromInt(simulation.height / 2),
                            @floatFromInt(simulation.depth / 2),
                        };
                        node.material = @enumFromInt(1);

                        node.name = "Box";
                        simulation.csg_dirty = true;

                        try selected_node_handles.append(arena, node_handle);
                        try selected_node_parents.append(arena, .empty);
                    }

                    if (imgui.selectable("Sphere")) {
                        const node_handle = try csg_tree.addNode(arena, .root);

                        const node = csg_tree.getNode(node_handle);

                        node.* = .{};
                        node.data = .{
                            .sphere = .{ .radius = 10 },
                        };
                        node.transform = .identity;
                        node.transform.position = .{
                            @floatFromInt(simulation.width / 2),
                            @floatFromInt(simulation.height / 2),
                            @floatFromInt(simulation.depth / 2),
                        };
                        node.material = @enumFromInt(1);
                        node.name = "Sphere";
                        simulation.csg_dirty = true;

                        try selected_node_handles.append(arena, node_handle);
                        try selected_node_parents.append(arena, .empty);
                    }

                    imgui.endPopup();
                }

                const root_node = csg_tree.getNode(.root);

                node_parents.clearRetainingCapacity();

                for (root_node.children.items) |child| {
                    const selected = try imGuiCSGTreeNode(
                        csg_tree,
                        arena,
                        .root,
                        child,
                        &node_parents,
                        &selected_node_handles,
                        &selected_node_parents,
                        &csg_reparent_commands,
                    );

                    if (selected) {
                        try selected_node_handles.append(arena, child);
                        try selected_node_parents.append(arena, .empty);
                    }
                }

                for (csg_reparent_commands.items) |reparent| {
                    csg_tree.deleteNode(arena, reparent.source_parent, std.mem.find(
                        CSGTreeNodeHandle,
                        csg_tree.getNode(reparent.source_parent).children.items,
                        &.{reparent.source},
                    ).?);

                    try csg_tree.getNode(reparent.destination).children.append(
                        arena,
                        reparent.source,
                    );

                    simulation.csg_dirty = true;
                }

                csg_reparent_commands.clearRetainingCapacity();
            }
            imgui.end();

            if (imgui.begin("Simulation", .{})) {
                if (imgui.button("Play/Pause Simulation", .{})) {
                    simulation.enable_simulation = !simulation.enable_simulation;
                }

                imgui.sameLine(.{});

                _ = imgui.checkbox("Radiative Cooling", &simulation.enable_radiative_cooling);

                if (imgui.button("Reset Simulation", .{})) {
                    simulation.csg_dirty = true;
                    simulation.enable_simulation = false;
                }

                var heat_unit: []const u8 = "J";
                var heat_value: f32 = @floatFromInt(simulation.measured_heat);

                if (simulation.measured_heat >= 1e3 and simulation.measured_heat < 1e6) {
                    heat_value *= 1e-3;
                    heat_unit = "KJ";
                }

                if (simulation.measured_heat >= 1e6) {
                    heat_value *= 1e-6;
                    heat_unit = "MJ";
                }

                imgui.text("Total Heat: {:.2}{s}", .{ heat_value, heat_unit });

                imgui.plotLines("Total Enthalpy: ", heat_measurement_values);
                imgui.plotLines("Enthalpy Change: ", enthalpy_change_values);
            }
            imgui.end();

            if (imgui.begin("Renderer", .{})) {
                _ = imgui.valueEdit("Mode", &simulation.renderer_view_type, .{});
            }
            imgui.end();

            if (imgui.begin("File Browser", .{})) {
                var dir_iter = dir_to_browse.iterate();

                while (try dir_iter.next(init.io)) |entry| {
                    if (std.mem.containsAtLeast(u8, entry.name, 1, ".chemc.zon")) {
                        imgui.text("{s}", .{entry.name});
                        if (imgui.imageButton(
                            .fromFmt("{s}", .{entry.name}),
                            file_thumbnails.get(entry.name) orelse 0,
                            .{ 100, 100 },
                            .{},
                        )) {
                            maybe_sim_file = try dir_to_browse.openFile(init.io, entry.name, .{ .mode = .read_write });
                            sim_file_path = try dir_to_browse.realPathFileAlloc(init.io, entry.name, arena);

                            csg_tree = try .initFromFile(init.io, maybe_sim_file.?, arena);
                            selected_node_handles.clearRetainingCapacity();
                            selected_node_parents.clearRetainingCapacity();
                            simulation.csg_dirty = true;
                            simulation.enable_simulation = false;
                        }
                    }
                }
            }
            imgui.end();

            @import("imgui_log.zig").viewer("Log");

            imguizmo.view.beginFrame();
            if (imgui.begin("View Gizmo", .{ .flags = .{
                .no_background = true,
                .no_title_bar = true,
                .no_move = true,
                .no_resize = true,
                .no_mouse_inputs = true,
            }, .size = .{ @floatFromInt(window.getSize()[0]), @floatFromInt(window.getSize()[1]) } })) {
                var camera_rot: [4]f32 = .{ 0, 0, 0, 0 };

                camera_rot[0] = -camera.view[2][0];
                camera_rot[1] = -camera.view[2][1];
                camera_rot[2] = -camera.view[2][2];

                camera_rot[0] = camera.target[0] - camera.eye[0];
                camera_rot[1] = camera.target[1] - camera.eye[1];
                camera_rot[2] = camera.target[2] - camera.eye[2];

                camera_rot = -zmath.normalize4(camera_rot);
                camera_rot[3] = 0;

                std.log.info("win_pos = {any}", .{csg_editor_window_pos});

                if (imguizmo.view.rotate(
                    &camera.eye,
                    &camera_rot,
                    camera.target,
                    .{ csg_editor_window_pos[0] - 100, csg_editor_window_pos[1] + 100 },
                    .{},
                )) {
                    //camera.view[2][0] = -camera_rot[0];
                    //camera.view[2][1] = -camera_rot[1];
                    //camera.view[2][2] = -camera_rot[2];
                }
            }
            imgui.end();

            if (window.getKey(.left_control) != .release and window.getKey(.c) == .press) {
                copied_node_handles = try selected_node_handles.clone(arena);
                copied_node_parents = try selected_node_parents.clone(arena);
            }

            if (imgui.isKeyDown(imgui.cimgui.ImGuiKey_LeftCtrl) and imgui.isKeyPressed(imgui.cimgui.ImGuiKey_V)) {
                for (copied_node_handles.items, copied_node_parents.items) |copied_node, parents| {
                    _ = try csg_tree.copyNode(arena, copied_node, if (parents.items.len == 0) .root else parents.getLast());
                    simulation.csg_dirty = true;
                }
            }

            {
                const mouse_pos_f64 = window.getCursorPos();
                const mouse_pos: [2]f32 = .{ @floatCast(mouse_pos_f64[0]), @floatCast(mouse_pos_f64[1]) };

                const inv_proj = zmath.inverse(@as([4]@Vector(4, f32), @bitCast(camera.projection)));
                _ = inv_proj; // autofix
                const inv_view = zmath.inverse(@as([4]@Vector(4, f32), @bitCast(camera.view)));
                const view: [4]@Vector(4, f32) = @bitCast(camera.view);
                const projection: [4]@Vector(4, f32) = @bitCast(camera.projection);
                const inv_proj_view = zmath.inverse(zmath.mul(projection, view));

                const window_size_int = window.getSize();
                const window_size: [2]f32 = .{ @floatFromInt(window_size_int[0]), @floatFromInt(window_size_int[1]) };

                std.log.info("mouse_pos: {any}", .{mouse_pos});
                std.log.info("window_size: {any}", .{window_size});
                var ndc = @Vector(4, f32){
                    (2.0 * mouse_pos[0]) / window_size[0] - 1,
                    1.0 - 2.0 * (mouse_pos[1] / window_size[1]),
                    -1,
                    1,
                };

                std.log.info("ndc: {any}", .{ndc});

                var ray_origin: @Vector(4, f32) = zmath.mul(
                    inv_proj_view,
                    ndc,
                );
                ndc[2] = 1;
                var ray_end: @Vector(4, f32) = zmath.mul(
                    inv_proj_view,
                    ndc,
                );

                if (ray_origin[3] != 0) {
                    ray_origin[0] /= ray_origin[3];
                    ray_origin[1] /= ray_origin[3];
                }
                ray_origin *= @splat(128);

                if (ray_end[3] != 0) {
                    ray_end[0] /= ray_end[3];
                    ray_end[1] /= ray_end[3];
                }

                std.log.info("ray_origin: {}", .{ray_origin});
                //ray_origin = zmath.normalize3(ray_origin);

                ray_origin[0] = camera.eye[0];
                ray_origin[1] = camera.eye[1];
                ray_origin[2] = camera.eye[2];

                const front_vector = zmath.mul(inv_view, @Vector(4, f32){ 0, 0, 1, 0 });
                _ = front_vector; // autofix
                //ray_origin *= @splat(128);
                const ray_direction = @Vector(4, f32){ camera.target[0], camera.target[1], camera.target[2], 0 } - @Vector(4, f32){ camera.eye[0], camera.eye[1], camera.eye[2], 0 };
                //const ray_direction = ray_end - ray_origin;

                //ray_direction[0] = -camera.view[2][0];
                //ray_direction[1] = -camera.view[2][1];
                //ray_direction[2] = -camera.view[2][2];

                std.log.info("ray_origin: {}", .{ray_origin});
                std.log.info("ray_direction: {}", .{ray_direction});

                const maybe_inst = csg_program.rayMarchSDF(
                    .{ ray_origin[0], ray_origin[1], ray_origin[2] },
                    .{ ray_direction[0], ray_direction[1], ray_direction[2] },
                );

                if (maybe_inst) |inst| {
                    std.log.info("inst: {}", .{inst});

                    if (window.getMouseButton(.left) == .press and !imguizmo.ImGuizmo_IsUsing()) {
                        if (csg_program.instructions_to_nodes.get(inst)) |node| {
                            selected_node_handles.clearRetainingCapacity();
                            selected_node_parents.clearRetainingCapacity();
                            try selected_node_handles.append(
                                arena,
                                node,
                            );
                            try selected_node_parents.append(arena, .empty);
                        }
                    }
                }
            }

            if (selected_node_handles.items.len != 0) {
                const selected_node = csg_tree.getNode(selected_node_handles.items[0]);

                var matrix: [4]@Vector(4, f32) = zmath.identity();

                var local_bounds: [2][3]f32 = undefined;

                var resultant_transform = selected_node.transform;

                if (selected_node_parents.items.len != 0) {
                    for (selected_node_parents.items[0].items) |parent_handle| {
                        const parent = csg_tree.getNode(parent_handle);

                        resultant_transform = .compose(parent.transform, resultant_transform);
                    }
                }

                var rotation: @Vector(4, f32) = selected_node.transform.rotation;

                rotation = math.mulQuat(resultant_transform.rotation, rotation);

                matrix = zmath.mul(zmath.matFromQuat(rotation), matrix);

                if (selected_node.data == .box) {
                    local_bounds[0][0] = -@as(f32, @floatFromInt(std.math.sign(selected_node.data.box.bounds[0]))) * resultant_transform.uniform_scale;
                    local_bounds[0][1] = -@as(f32, @floatFromInt(std.math.sign(selected_node.data.box.bounds[1]))) * resultant_transform.uniform_scale;
                    local_bounds[0][2] = -@as(f32, @floatFromInt(std.math.sign(selected_node.data.box.bounds[2]))) * resultant_transform.uniform_scale;

                    local_bounds[1][0] = -local_bounds[0][0] * resultant_transform.uniform_scale;
                    local_bounds[1][1] = -local_bounds[0][1] * resultant_transform.uniform_scale;
                    local_bounds[1][2] = -local_bounds[0][2] * resultant_transform.uniform_scale;
                    matrix = zmath.mul(matrix, zmath.scaling(
                        selected_node.data.box.bounds[0],
                        selected_node.data.box.bounds[1],
                        selected_node.data.box.bounds[2],
                    ));
                } else {
                    matrix = zmath.mul(matrix, zmath.scaling(
                        resultant_transform.uniform_scale,
                        resultant_transform.uniform_scale,
                        resultant_transform.uniform_scale,
                    ));
                }

                var position: @Vector(3, f32) = @splat(0);

                position += resultant_transform.position;

                matrix = zmath.mul(matrix, zmath.translation(
                    position[0],
                    position[1],
                    position[2],
                ));

                const snap: [3]f32 = .{ 1, 1, 1 };
                _ = snap; // autofix

                var delta_matrix: [4][4]f32 = undefined;
                var delta_quat: @Vector(4, f32) = .{ 0, 0, 0, 0 };
                var stub_mat: [4][4]f32 = @bitCast(zmath.identity());
                stub_mat = @bitCast(zmath.matFromQuat(resultant_transform.rotation));

                if (imguizmo.manipulate(
                    @ptrCast(&camera.view),
                    @ptrCast(&camera.projection),
                    .universal,
                    .local,
                    @ptrCast(&matrix),
                    @ptrCast(&delta_quat),
                    .{
                        .local_bounds = if (selected_node.data == .box) @ptrCast(&local_bounds) else null,
                        .delta_matrix = @ptrCast(&delta_matrix),
                    },
                )) {}

                const translation: [3]f32 = .{
                    @floor(matrix[3][0]),
                    @floor(matrix[3][1]),
                    @floor(matrix[3][2]),
                };
                _ = translation; // autofix

                const scale: [3]f32 = .{
                    (matrix[0][0]),
                    (matrix[1][1]),
                    (matrix[2][2]),
                };

                const delta_translation: [3]f32 = .{
                    @floor(delta_matrix[3][0]),
                    @floor(delta_matrix[3][1]),
                    @floor(delta_matrix[3][2]),
                };

                const delta_scale: [3]f32 = .{
                    (delta_matrix[0][0]),
                    (delta_matrix[1][1]),
                    (delta_matrix[2][2]),
                };

                const old_transform = selected_node.transform;
                const old_data = selected_node.data;

                for (selected_node_handles.items) |node_handle| {
                    const node = csg_tree.getNode(node_handle);

                    node.transform.position[0] += delta_translation[0];
                    node.transform.position[1] += delta_translation[1];
                    node.transform.position[2] += delta_translation[2];

                    if (selected_node_handles.items[0] != node_handle or selected_node.data != .box) {
                        node.transform.uniform_scale += delta_scale[0];
                    }
                }

                if (selected_node.data == .box) {
                    selected_node.data.box.bounds[0] = @floor(scale[0]);
                    selected_node.data.box.bounds[1] = @floor(scale[1]);
                    selected_node.data.box.bounds[2] = @floor(scale[2]);
                }

                if (selected_node.data != .empty and selected_node.data != .box) {
                    selected_node.transform.uniform_scale = scale[0];
                } else {
                    selected_node.transform.uniform_scale = 1;
                }

                delta_quat[3] = 0;
                //selected_node.transform.rotation = math.mulQuat(delta_quat, selected_node.transform.rotation);
                selected_node.transform.rotation = @as(@Vector(4, f32), selected_node.transform.rotation) + delta_quat;
                //selected_node.transform.rotation = zmath.normalize4(selected_node.transform.rotation);
                //selected_node.transform.rotation = zmath.normalize4(selected_node.transform.rotation);

                const Static = struct {
                    pub var quat_total: @Vector(4, f32) = @splat(0);
                };
                //selected_node.transform.rotation += delta_quat;
                //selected_node.transform.rotation = zmath.normalize4(selected_node.transform.rotation);
                Static.quat_total += delta_quat;
                //selected_node.transform.rotation[3] = 1;
                //Static.quat_total = zmath.normalize4(Static.quat_total);

                if (!std.meta.eql(old_data, selected_node.data)) {
                    simulation.csg_dirty = true;
                }

                if (!std.meta.eql(old_transform, selected_node.transform)) {
                    simulation.csg_dirty = true;
                }
            }
        }

        imgui.render();

        imgui.impl.opengl3.renderDrawData(imgui.getDrawData());

        glfw.swapBuffers(window);
    }
}

const CSGReparentCommand = struct {
    source: CSGTreeNodeHandle,
    source_parent: CSGTreeNodeHandle,
    destination: CSGTreeNodeHandle = .null,
};

fn imGuiCSGTreeNode(
    tree: CSGTree,
    gpa: std.mem.Allocator,
    parent_handle: CSGTreeNodeHandle,
    node_handle: CSGTreeNodeHandle,
    parents: *std.ArrayList(CSGTreeNodeHandle),
    selected_nodes: *std.ArrayList(CSGTreeNodeHandle),
    selected_node_parents: *std.ArrayList(std.ArrayList(CSGTreeNodeHandle)),
    reparent_commands: *std.ArrayList(CSGReparentCommand),
) !bool {
    imgui.pushId(node_handle);
    defer imgui.popId();

    const node = tree.getNode(node_handle);

    var selected: bool = false;

    if (imgui.treeNode(node.name, .{
        .flags = .{
            .selected = std.mem.find(CSGTreeNodeHandle, selected_nodes.items, &.{node_handle}) != null,
        },
    })) {
        defer imgui.treePop();

        if (imgui.isItemClicked()) {
            if (selected_nodes.items.len == 0) {
                selected = true;
            } else {
                if (imgui.isKeyDown(imgui.cimgui.ImGuiKey_LeftShift)) {
                    selected = true;
                } else {
                    selected = true;
                    selected_nodes.clearRetainingCapacity();
                    selected_node_parents.clearRetainingCapacity();
                }
            }
        }

        if (imgui.beginDragDropSource(.{})) {
            defer imgui.endDragDropSource();

            _ = imgui.setDragDropPayload(
                CSGReparentCommand{
                    .source = node_handle,
                    .source_parent = parent_handle,
                },
                .{},
            );
        }

        if (imgui.beginDragDropTarget()) {
            defer imgui.endDragDropTarget();

            if (imgui.acceptDragDropTarget(CSGReparentCommand, .{})) |reparent_command| {
                var actual_command = reparent_command;

                actual_command.destination = node_handle;

                try reparent_commands.append(gpa, actual_command);
            }
        }

        if (node.children.items.len != 0) {
            try parents.append(gpa, node_handle);
        }

        for (node.children.items) |child| {
            const child_selected = try imGuiCSGTreeNode(
                tree,
                gpa,
                node_handle,
                child,
                parents,
                selected_nodes,
                selected_node_parents,
                reparent_commands,
            );

            if (child_selected) {
                try selected_nodes.append(gpa, child);
                try selected_node_parents.append(gpa, try parents.clone(gpa));
            }
        }

        if (node.children.items.len != 0) {
            _ = parents.pop();
        }
    }

    return selected;
}

const Camera = struct {
    eye: [3]f32,
    target: [3]f32,
    fov: f32,
    zoom: f32,
    near: f32,
    far: f32,

    projection: [4][4]f32,
    view: [4][4]f32,
};

fn packUnorm4x8(vector: [4]f32) u32 {
    const Rgba = packed struct(u32) {
        x: u8,
        y: u8,
        z: u8,
        w: u8,
    };

    var v = vector;

    v[0] = std.math.clamp(v[0], 0, 1);
    v[1] = std.math.clamp(v[1], 0, 1);
    v[2] = std.math.clamp(v[2], 0, 1);
    v[3] = std.math.clamp(v[3], 0, 1);

    const rgba: Rgba = .{
        .x = @intFromFloat(v[0] * 255),
        .y = @intFromFloat(v[1] * 255),
        .z = @intFromFloat(v[2] * 255),
        .w = @intFromFloat(v[3] * 255),
    };

    return @bitCast(rgba);
}

pub const CSGTreeNodeHandle = enum(u32) {
    root = 0,
    null = std.math.maxInt(u32),
    _,
};

const CSGTree = struct {
    nodes: std.ArrayList(CSGTreeNode) = .empty,

    pub fn init(gpa: std.mem.Allocator) !CSGTree {
        var self: CSGTree = .{};

        try self.nodes.append(gpa, .{});

        return self;
    }

    pub fn initFromFile(io: std.Io, file: std.Io.File, arena: std.mem.Allocator) !CSGTree {
        var sim_file_reader = file.reader(io, &.{});

        const stat = try file.stat(io);

        const sim_file_source = try sim_file_reader.interface.readAlloc(arena, stat.size);
        const sim_file_source_z = try arena.dupeZ(u8, sim_file_source);

        return try .initFromZonMemory(sim_file_source_z, arena);
    }

    pub fn initFromZonMemory(zon: [:0]const u8, arena: std.mem.Allocator) !CSGTree {
        const serialized_tree = try std.zon.parse.fromSliceAlloc(
            CSGTreeZonSerializable,
            arena,
            zon,
            null,
            .{},
        );

        const tree = @as(*const CSGTree, @ptrCast(&serialized_tree)).*;

        return tree;
    }

    pub fn saveToFile(self: *@This(), io: std.Io, file: std.Io.File) !void {
        self.trimArrayLists();

        try file.setLength(io, 0);
        var sim_file_writer = file.writer(io, &.{});
        try std.zon.stringify.serializeArbitraryDepth(@as(*CSGTreeZonSerializable, @ptrCast(self)).*, .{
            .emit_default_optional_fields = false,
        }, &sim_file_writer.interface);
    }

    pub fn trimArrayLists(self: *@This()) void {
        self.nodes.capacity = self.nodes.items.len;
        self.trimNodeArrayList(self.getNode(.root));
    }

    pub fn trimNodeArrayList(tree: @This(), node: *CSGTreeNode) void {
        node.children.capacity = node.children.items.len;

        for (node.children.items) |child| {
            tree.trimNodeArrayList(tree.getNode(child));
        }
    }

    pub fn getNode(self: @This(), handle: CSGTreeNodeHandle) *CSGTreeNode {
        return &self.nodes.items[@intFromEnum(handle)];
    }

    pub fn addNode(self: *@This(), gpa: std.mem.Allocator, parent: CSGTreeNodeHandle) !CSGTreeNodeHandle {
        const handle_int: u32 = @intCast(self.nodes.items.len);
        const handle: CSGTreeNodeHandle = @enumFromInt(handle_int);
        try self.nodes.append(gpa, .{});

        try self.nodes.items[@intFromEnum(parent)].children.append(gpa, handle);

        return handle;
    }

    pub fn copyNode(
        self: *@This(),
        gpa: std.mem.Allocator,
        handle: CSGTreeNodeHandle,
        parent: CSGTreeNodeHandle,
    ) !CSGTreeNodeHandle {
        const new_handle = try self.addNode(gpa, parent);

        const node = self.getNode(handle);
        self.getNode(new_handle).* = node.*;

        self.getNode(new_handle).children = try node.children.clone(gpa);

        const children = self.getNode(new_handle).children.items;

        for (children) |*child| {
            const new_child = try self.copyNode(gpa, child.*, new_handle);

            child.* = new_child;
        }

        return new_handle;
    }

    pub fn moveNode(
        self: *@This(),
        gpa: std.mem.Allocator,
        handle: CSGTreeNodeHandle,
        previous_parent: CSGTreeNodeHandle,
        new_parent: CSGTreeNodeHandle,
    ) !void {
        const previous_parent_node = self.getNode(previous_parent);
        const new_parent_node = self.getNode(new_parent);

        self.deleteNode(
            gpa,
            previous_parent,
            std.mem.find(CSGTreeNodeHandle, previous_parent_node.children.items, &.{handle}).?,
        );

        try new_parent_node.children.append(gpa, handle);
    }

    pub fn deleteNode(
        self: *@This(),
        gpa: std.mem.Allocator,
        parent: CSGTreeNodeHandle,
        child_index: usize,
    ) void {
        _ = gpa; // autofix
        //
        _ = self.getNode(parent).children.swapRemove(child_index);
    }

    pub fn compile(
        tree: *@This(),
        gpa: std.mem.Allocator,
        program: *Simulation.CSGProgram,
    ) !void {
        program.instructions.clearRetainingCapacity();
        program.instructions_box.clearRetainingCapacity();
        program.instructions_sphere.clearRetainingCapacity();
        program.instructions_extrude_post.clearRetainingCapacity();
        program.transforms.clearRetainingCapacity();
        program.instructions_to_nodes.clearRetainingCapacity();

        try tree.compileNode(
            .root,
            gpa,
            program,
            .null,
        );
    }

    pub fn compileNode(
        tree: *@This(),
        node_handle: CSGTreeNodeHandle,
        gpa: std.mem.Allocator,
        program: *Simulation.CSGProgram,
        parent_handle: CSGTreeNodeHandle,
    ) !void {
        const node = tree.getNode(node_handle);

        std.log.info("compile_node: {any}", .{node.*});

        if (node.unary_op != .identity and node_handle != .root) {
            try program.instructions.append(gpa, .{
                .csg_op = node.unary_op,
                .stream_index = 0,
            });
        }

        const transform_index: u32 = @intCast(program.transforms.items.len);

        var parent_transform: Simulation.CSGRigidTransform = .identity;

        if (parent_handle != .null) {
            parent_transform = tree.getNode(parent_handle).transform;
        }

        const resolved_transform: Simulation.CSGRigidTransform = .compose(parent_transform, node.transform);

        try program.transforms.append(gpa, resolved_transform);

        var identity_transform_index: ?u32 = null;

        if (node.unary_op == .unary_op_extrude_pre and node_handle != .root) {
            const extrude_pre = &program.instructions.items[program.instructions.items.len - 1];

            identity_transform_index = @intCast(program.transforms.items.len);

            try program.transforms.append(gpa, .identity);

            extrude_pre.* = .{
                .csg_op = .unary_op_extrude_pre,
                .stream_index = 0,
            };
        }

        if (node.data != .empty) {
            const instruction_index: u32 = @intCast(program.instructions.items.len);
            const instruction = try program.instructions.addOne(gpa);

            try program.instructions_to_nodes.put(gpa, instruction_index, node_handle);

            switch (node.data) {
                .box => |box| {
                    const stream_index: u32 = @intCast(program.instructions_box.items.len);

                    const box_data = try program.instructions_box.addOne(gpa);

                    box_data.* = .{
                        .bounds = box.bounds,
                        .rigid_transform = transform_index,
                        .material = node.material,
                    };

                    if (identity_transform_index) |ident_index| {
                        box_data.rigid_transform = ident_index;
                    }

                    instruction.csg_op = .box;
                    instruction.stream_index = stream_index;
                },
                .sphere => |sphere| {
                    const stream_index: u32 = @intCast(program.instructions_sphere.items.len);

                    const box_data = try program.instructions_sphere.addOne(gpa);

                    box_data.* = .{
                        .radius = sphere.radius,
                        .rigid_transform = transform_index,
                        .material = node.material,
                    };

                    if (identity_transform_index) |ident_index| {
                        box_data.rigid_transform = ident_index;
                    }

                    instruction.csg_op = .sphere;
                    instruction.stream_index = stream_index;
                },
                .extrude => {},
                .empty => {},
            }
        }

        for (node.children.items, 0..) |child, i| {
            try tree.compileNode(
                child,
                gpa,
                program,
                node_handle,
            );

            if (i != 0) {
                try program.instructions.append(gpa, .{
                    .csg_op = node.child_op,
                    .stream_index = 0,
                });
            }
        }

        if (node.unary_op == .unary_op_extrude_pre) {
            const extrude_post = try program.instructions.addOne(gpa);
            const stream_index: u32 = @intCast(program.instructions_extrude_post.items.len);
            const post = try program.instructions_extrude_post.addOne(gpa);

            post.h = node.data.extrude.h;

            extrude_post.* = .{
                .csg_op = .unary_op_extrude_post,
                .stream_index = stream_index,
            };
        }

        if (node.data != .empty and node.data != .extrude and node.children.items.len != 0) {
            try program.instructions.append(gpa, .{
                .csg_op = .binary_op_union,
                .stream_index = 0,
            });
        }
    }
};

const CSGTreeZonSerializable = struct {
    nodes: std.ArrayList(CSGTreeNodeZonSerializable) = .empty,
};

const CSGTreeNode = struct {
    transform: Simulation.CSGRigidTransform = .identity,
    data: Data = .empty,
    material: Simulation.VoxelMaterialHandle = .air,
    children: std.ArrayList(CSGTreeNodeHandle) = .empty,
    name: [:0]const u8 = "",
    unary_op: Simulation.CSGInstructionOp = .identity,
    child_op: Simulation.CSGInstructionOp = .binary_op_union,

    pub const Data = union(enum) {
        empty: void,
        box: struct {
            bounds: [3]f32,
        },
        sphere: struct {
            radius: f32,
        },
        extrude: struct {
            h: f32,
        },
    };
};

const CSGTreeNodeZonSerializable = struct {
    transform: Simulation.CSGRigidTransform = .identity,
    data: CSGTreeNode.Data = .empty,
    material: u32 = 0,
    children: std.ArrayList(u32) = .empty,
    name: [:0]const u8 = "",
    unary_op: Simulation.CSGInstructionOp = .identity,
    child_op: Simulation.CSGInstructionOp = .binary_op_union,
};

fn glfwScrollCallback(window: *glfw.Window, x: f64, y: f64) callconv(.c) void {
    _ = x; // autofix
    const scroll = window.getUserPointer(f32);

    scroll.?.* = @floatCast(-y * 0.1);
}

///Call this to send a log message to the log viewer
pub fn logMessage(
    comptime message_level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    @import("imgui_log.zig").logMessage(
        message_level,
        scope,
        format,
        args,
    ) catch @panic("");
}

pub const std_options: std.Options = .{
    .logFn = logMessage,
};

export const font_data = @embedFile("assets/JetBrainsMono_regular.ttf");
export const font_data_size: u32 = font_data.len;

extern fn imguiStyleSetup() void;

const imgui = @import("imgui.zig");
const Simulation = @import("Simulation.zig");
const zmath = @import("zmath");
const glfw = @import("zglfw");
const gl = @import("gl");
const zigimg = @import("zigimg");
const std = @import("std");
const stb_image = @import("stb_image.zig");
const imguizmo = @import("imguizmo.zig");
const math = @import("math.zig");
