pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(arena);
    _ = args; // autofix

    if (@import("builtin").os.tag == .linux and @import("builtin").mode == .debug) {
        //We do this in debug mode so that we can do renderdoc captures
        if (!@import("options").enable_nfd) {
            try glfw.initHint(.platform, glfw.Platform.x11);
        }
    }

    try glfw.init();
    defer glfw.terminate();

    if (@import("builtin").os.tag != .macos) {
        glfw.windowHint(.context_version_major, 4);
        glfw.windowHint(.context_version_minor, 6);
        glfw.windowHint(.opengl_debug_context, true);
        glfw.windowHint(.opengl_profile, .opengl_core_profile);
    } else {
        glfw.windowHint(.client_api, .no_api);
        glfw.windowHint(.cocoa_retina_framebuffer, true);
    }

    const content_scale = imgui.cimgui.cImGui_ImplGlfw_GetContentScaleForMonitor(@ptrCast(glfw.getPrimaryMonitor()));

    const window = try glfw.createWindow(
        @intFromFloat(640 * content_scale),
        @intFromFloat(480 * content_scale),
        "Chemica",
        null,
        null,
    );
    defer window.destroy();

    window.maximize();
    glfw.makeContextCurrent(window);
    glfw.swapInterval(0);

    _ = imgui.createContext(.{});

    var gpu_context = try gpu.Context.init(arena, window, init.io);
    defer gpu_context.deinit();

    //imgui.getStyle()._MainScale = content_scale;
    //imgui.cimgui.ImGuiStyle_ScaleAllSizes(imgui.getStyle(), content_scale);
    //imgui.cimgui.ImGui_ScaleWindowsInViewport(@ptrCast(imgui.cimgui.ImGui_GetMainViewport()), 1 / content_scale);

    var simulation: Simulation = try .init(
        &gpu_context,
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

    imguiStyleSetup();

    if (@import("builtin").mode == .debug) {
        imgui.loadIniSettingsFromDisk("src/assets/imgui.ini");
    } else {
        imgui.loadIniSettingsFromMemory(@embedFile("assets/imgui.ini"));
    }

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

    _ = window.setScrollCallback(glfwScrollCallback);
    var mouse_scroll: f32 = 0;

    window.setUserPointer(&mouse_scroll);

    var csg_tree_3d: CSGTree = try .init(arena);
    var csg_tree: *CSGTree = &csg_tree_3d;
    var csg_tree_2d: CSGTree = try .init(arena);

    //csg_tree = try .initFromZonMemory(@embedFile("assets/test_scenes/metal_spheres.chemc.zon"), arena);

    var selected_node_handles: std.ArrayList(CSGTreeNodeHandle) = .empty;
    var copied_node_handles: std.ArrayList(CSGTreeNodeHandle) = .empty;

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
        csg_tree.saveToFile(init.io, gpa, sim_file) catch @panic("");
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

    {
        var iter = dir_to_browse.iterate();

        while (try iter.next(init.io)) |entry| {
            if (std.mem.containsAtLeast(u8, entry.name, 1, ".chemc.zon")) {
                try thumbnail_gen_queue.append(arena, try dir_to_browse.realPathFileAlloc(init.io, entry.name, arena));
            }
        }
    }

    var sample_scenes_thumbnails: std.ArrayList(?*gpu.Texture) = .empty;
    var sample_scenes: std.ArrayList(CSGTree) = .empty;

    const sample_scenes_zon_paths = [_][:0]const u8{
        //("assets/sample_scenes/metal_blocks.chemc.zon"),
    };
    comptime var sample_scenes_zon: [sample_scenes_zon_paths.len][:0]const u8 = undefined;

    comptime for (sample_scenes_zon_paths, 0..) |path, i| {
        sample_scenes_zon[i] = @embedFile(path);
    };

    gpu_context.beginFrame();

    var enable_transform_gizmo: bool = false;

    if (false) {
        for (sample_scenes_zon, sample_scenes_zon_paths) |sample_scene_zon, path| {
            const sample_scene = try sample_scenes.addOne(arena);
            sample_scene.* = try .initFromZonMemory(sample_scene_zon, arena);

            simulation.camera = camera;

            const thumbnail = try simulation.gpu_sim.renderSceneThumbnail(
                gpu_context,
                &simulation,
                sample_scene,
                path,
                arena,
            );

            try sample_scenes_thumbnails.append(arena, thumbnail);
        }
    }

    imgui.getIO().WantSaveIniSettings = false;
    imgui.getIO().IniSavingRate = 0;

    var render_sdf_raymarched: bool = false;

    while (!window.shouldClose()) {
        glfw.pollEvents();

        imgui.impl.glfw.newFrame();

        gpu_context.beginFrame();

        if (imgui.cimgui.ImGui_IsKeyPressed(imgui.cimgui.ImGuiKey_T)) {
            enable_transform_gizmo = !enable_transform_gizmo;
        }

        if (@import("builtin").os.tag == .macos) {
            imgui.getIO().DisplaySize.x *= 0.5;
            imgui.getIO().DisplaySize.y *= 0.5;
            imgui.getIO().MousePos.x *= 0.5;
            imgui.getIO().MousePos.y *= 0.5;
            imgui.getIO().MouseDelta.x *= 0.5;
            imgui.getIO().MouseDelta.y *= 0.5;

            imgui.getIO().FontGlobalScale = 0.25;
            imgui.getStyle().FontScaleDpi = 0.5;
        }

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

            if (window.getMouseButton(.right) != .release and !imgui.isAnyItemActive() and !imguizmo.ImGuizmo_IsUsing()) {
                camera.eye = .{ new_eye[0], new_eye[1], new_eye[2] };
            }

            const zoom_factor: @Vector(3, f32) = @splat(std.math.clamp(mouse_scroll, -1, 1));

            var eye: @Vector(3, f32) = camera.eye;
            const target: @Vector(3, f32) = camera.target;

            eye += zoom_factor * (eye - target);
            mouse_scroll = 0;

            camera.eye = eye;

            last_mouse_pos = cursor_pos;

            simulation.camera = camera;
        }

        //Thumbnail gen
        {
            if (thumbnail_gen_queue.pop()) |scene_path| {
                const scene_file = try std.Io.Dir.cwd().openFile(init.io, scene_path, .{});
                defer scene_file.close(init.io);

                var scene: CSGTree = try .initFromFile(init.io, scene_file, gpa);
                defer scene.nodes.deinit(gpa);
                csg_program.clear();

                const scene_root = try scene.compile(gpa, &csg_program);

                try simulation.updateCSGProgram(csg_program);

                _ = try simulation.gpu_sim.renderSceneThumbnail(
                    gpu_context,
                    &simulation,
                    scene_root,
                    scene_path,
                    arena,
                );
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

        csg_program.clear();

        const scene_2d_root_index = try csg_tree_2d.compile(arena, &csg_program);
        const scene_root_index = try csg_tree_3d.compile(arena, &csg_program);

        try simulation.updateCSGProgram(csg_program);

        simulation.update(scene_root_index);

        const previous_enthalpy = heat_measurement_values[(simulation.timestep_index -| 1) % (heat_measurement_values.len)];

        heat_measurement_values[simulation.timestep_index % (heat_measurement_values.len)] = @floatFromInt(simulation.measured_heat);
        heat_measurement_values[simulation.timestep_index % (heat_measurement_values.len)] /= @floatFromInt(1);

        enthalpy_change_values[simulation.timestep_index % (enthalpy_change_values.len)] = @as(f32, @floatFromInt(simulation.measured_heat)) - previous_enthalpy;

        simulation.render(
            gpu_context,
            null,
            scene_root_index,
            .{
                .render_sdf_raymarched = render_sdf_raymarched,
            },
        );

        const scene_2d_texture = try simulation.gpu_sim.render2DScene(
            gpu_context,
            &simulation,
            scene_2d_root_index,
            gpa,
            512,
            512,
        );

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

            imguizmo.enable(enable_transform_gizmo);

            if (imgui.isKeyPressed(imgui.cimgui.ImGuiKey_F)) {
                if (selected_node_handles.items.len != 0) {
                    camera.target = csg_tree.getNode(selected_node_handles.items[0]).transform.position;
                }
            }

            if (selected_node_handles.items.len != 0 and !imgui.isAnyItemActive()) blk: {
                var pressed: bool = false;

                var name: [:0]const u8 = "";
                var op: CSGTreeNode.Data = .@"union";

                if (imgui.isKeyPressed(imgui.cimgui.ImGuiKey_E)) {
                    pressed = true;
                    name = "Extrude";
                    op = .extrude;
                }

                if (imgui.isKeyPressed(imgui.cimgui.ImGuiKey_R) and imgui.isKeyDown(imgui.cimgui.ImGuiKey_LeftCtrl)) {
                    pressed = true;
                    name = "Revolve";
                    op = .revolve;
                }

                if (imgui.isKeyPressed(imgui.cimgui.ImGuiKey_U)) {
                    pressed = true;

                    op = .@"union";
                    name = "Union";

                    if (imgui.isKeyDown(imgui.cimgui.ImGuiKey_S)) {
                        name = "Smooth Union";
                    }
                }
                if (imgui.isKeyPressed(imgui.cimgui.ImGuiKey_I)) {
                    pressed = true;

                    op = .intersection;
                    name = "Intersection";

                    if (imgui.isKeyDown(imgui.cimgui.ImGuiKey_S)) {
                        name = "Smooth Intersection";
                    }
                }
                if (imgui.isKeyPressed(imgui.cimgui.ImGuiKey_D)) {
                    pressed = true;

                    op = .difference;
                    name = "Difference";

                    if (imgui.isKeyDown(imgui.cimgui.ImGuiKey_S)) {
                        name = "Smooth Difference";
                    }
                }

                if (!pressed) break :blk;

                const union_node_handle = try csg_tree.addNode(arena, .root);

                const union_node = csg_tree.getNode(union_node_handle);
                union_node.* = .{};
                union_node.data = op;
                union_node.name = name;

                var midpoint: @Vector(3, f32) = @splat(0);

                for (selected_node_handles.items) |selected_node_handle| {
                    const selected_node = csg_tree.getNode(selected_node_handle);

                    midpoint += selected_node.transform.position;

                    try csg_tree.moveNode(
                        arena,
                        selected_node_handle,
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

            const enable_nfd = @import("options").enable_nfd;

            if (imgui.begin("Texture Editor", .{})) {
                imgui.image(scene_2d_texture, .{ 512, 512 }, .{});
            }
            imgui.end();

            if (imgui.begin("CSG Editor", .{})) {
                csg_editor_window_pos[0] = imgui.cimgui.ImGui_GetWindowPos().x;
                csg_editor_window_pos[1] = imgui.cimgui.ImGui_GetWindowPos().y;

                if (imgui.button("Switch Scene (2D/3D)", .{})) {
                    if (csg_tree == &csg_tree_3d) {
                        csg_tree = &csg_tree_2d;
                    } else {
                        csg_tree = &csg_tree_3d;
                    }
                    selected_node_handles.clearRetainingCapacity();
                }

                if (true or imgui.beginMenuBar()) {
                    if (imgui.beginMenu("File", .{})) {
                        defer imgui.endMenu();
                        if (imgui.menuItem("New", .{})) {
                            csg_tree.nodes.deinit(arena);
                            selected_node_handles.clearRetainingCapacity();
                            csg_tree_3d = try .init(arena);
                            csg_program.clear();
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

                                    csg_tree_3d = try .initFromFile(init.io, file, arena);

                                    sim_file_path = try std.Io.Dir.cwd().realPathFileAlloc(init.io, path, arena);
                                    maybe_sim_file = file;
                                    simulation.csg_dirty = true;
                                    simulation.enable_simulation = false;
                                }
                            }
                        }
                        if (imgui.menuItem("Save", .{ .shortcut = "Ctrl+S" })) {
                            if (maybe_sim_file) |sim_file| {
                                try csg_tree.saveToFile(init.io, gpa, sim_file);

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

                                    try csg_tree.saveToFile(init.io, gpa, file);
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

                    simulation.csg_dirty |= imgui.dragFloat(
                        "Rounding",
                        "{}",
                        &selected_node.modifiers.rounding.rounding,
                        .{},
                    );

                    simulation.csg_dirty |= imgui.dragFloat(
                        "Extrusion",
                        "{}",
                        &selected_node.modifiers.extrusion,
                        .{},
                    );

                    simulation.csg_dirty |= imgui.dragFloat(
                        "Revolution",
                        "{}",
                        &selected_node.modifiers.revolution,
                        .{},
                    );

                    if (selected_node.material != .air) {
                        var material: usize = @backingInt(selected_node.material);

                        //simulation.csg_dirty |= imgui.combo("Material", &material, voxel_material_names_ptrs);

                        var input_buffer: [1024]u8 = @splat(0);

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

                        selected_node.material = @fromBackingInt(@intCast(material));
                    }
                }

                if (imgui.button("Add Node", .{})) {
                    _ = imgui.openPopup("node_type_popup");
                }

                if (imgui.beginPopup("node_type_popup")) {
                    inline for (comptime std.meta.fieldNames(CSGTreeNode.Data), comptime std.meta.tags(std.meta.Tag(CSGTreeNode.Data))) |field_name, tag| {
                        if (imgui.selectable(field_name)) {
                            const node_handle = try csg_tree.addNode(arena, .root);

                            const node = csg_tree.getNode(node_handle);

                            node.* = .{};
                            node.data = .editorDefault(tag);
                            node.transform = .identity;
                            node.transform.position = .{
                                @floatFromInt(simulation.width / 2),
                                @floatFromInt(simulation.height / 2),
                                @floatFromInt(simulation.depth / 2),
                            };
                            node.material = @fromBackingInt(@intCast(1));

                            node.name = field_name;
                            simulation.csg_dirty = true;

                            selected_node_handles.clearRetainingCapacity();
                            try selected_node_handles.append(arena, node_handle);
                        }
                    }

                    imgui.endPopup();
                }

                const root_node = csg_tree.getNode(.root);

                for (root_node.children.items) |child| {
                    const selected = try imGuiCSGTreeNode(
                        csg_tree,
                        arena,
                        .root,
                        child,
                        &selected_node_handles,
                        &csg_reparent_commands,
                    );

                    if (selected) {
                        try selected_node_handles.append(arena, child);
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
                _ = imgui.checkbox("Render Continous SDF", &render_sdf_raymarched);

                imgui.text("Performance Stats", .{});

                imgui.separator(.{});

                const total_primary_rays: f32 = @floatFromInt(simulation.ray_stats.total_primary_rays);
                const total_primary_ray_steps: f32 = @floatFromInt(simulation.ray_stats.total_primary_ray_steps);
                const total_primary_ray_hits: f32 = @floatFromInt(simulation.ray_stats.total_primary_ray_hits);

                var mean_steps_per_ray = total_primary_ray_steps / total_primary_rays;

                if (std.math.isNan(mean_steps_per_ray)) {
                    mean_steps_per_ray = 1;
                }

                var fmt_buf: [1024]u8 = undefined;

                var fba_instance = std.heap.FixedBufferAllocator.init(&fmt_buf);
                const fba = fba_instance.allocator();

                imgui.text("Primary Rays {s}", .{try formatNumberWithUnits(fba, total_primary_rays)});
                imgui.text("Primary Ray Hits {s}", .{try formatNumberWithUnits(fba, total_primary_ray_hits)});
                imgui.text("Primary Ray Misses {s}", .{try formatNumberWithUnits(fba, total_primary_rays - total_primary_ray_hits)});
                imgui.text("Primary Ray Steps {s}", .{try formatNumberWithUnits(fba, total_primary_ray_steps)});
                imgui.text("Primary Ray Steps (Max) {s}", .{try formatNumberWithUnits(fba, @floatFromInt(simulation.ray_stats.max_primary_ray_steps))});
                imgui.text("Primary Ray Steps (Min) {s}", .{try formatNumberWithUnits(fba, @floatFromInt(simulation.ray_stats.min_primary_ray_steps))});

                imgui.text("Mean Ray Steps Per Primary Ray", .{});

                const colors: [3][4]f32 = .{
                    .{ 0, 1, 0, 1 },
                    .{ 0.5, 0.4, 0, 1 },
                    .{ 0.9, 0.1, 0, 1 },
                };

                imgui.sameLine(.{});
                imgui.pushStyleColor(.Text, colors[@intFromFloat(@floor(@log10(mean_steps_per_ray)))]);
                imgui.text("{d:.2}", .{mean_steps_per_ray});
                imgui.popStyleColor();
            }
            imgui.end();

            if (imgui.begin("File Browser", .{})) {
                var dir_iter = dir_to_browse.iterate();

                while (try dir_iter.next(init.io)) |entry| {
                    if (std.mem.containsAtLeast(u8, entry.name, 1, ".chemc.zon")) {
                        imgui.text("{s}", .{entry.name});
                        if (imgui.imageButton(
                            .fromFmt("{s}", .{entry.name}),
                            simulation.gpu_sim.scene_thumbnails.get(entry.name) orelse null,
                            .{ 100, 100 },
                            .{},
                        )) {
                            maybe_sim_file = try dir_to_browse.openFile(init.io, entry.name, .{ .mode = .read_write });
                            sim_file_path = try dir_to_browse.realPathFileAlloc(init.io, entry.name, arena);

                            csg_tree_3d = try .initFromFile(init.io, maybe_sim_file.?, arena);
                            selected_node_handles.clearRetainingCapacity();
                            simulation.csg_dirty = true;
                        }
                    }
                }

                imgui.separator(.{});
                imgui.text("Sample Scenes", .{});

                imgui.pushId("samples");

                if (sample_scenes_thumbnails.items.len != 0) {
                    for (sample_scenes_thumbnails.items, sample_scenes.items, sample_scenes_zon_paths) |thumbnail, sample_scene, path| {
                        const name = std.fs.path.basename(path);
                        imgui.text("{s}", .{name});
                        if (imgui.imageButton(
                            .fromFmt("{s}", .{name}),
                            thumbnail,
                            .{ 100, 100 },
                            .{},
                        )) {
                            //TODO: make a deep copy
                            csg_tree_3d = sample_scene;
                            selected_node_handles.clearRetainingCapacity();
                            simulation.csg_dirty = true;
                            simulation.enable_simulation = false;
                        }
                    }
                }

                imgui.popId();
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
            }

            if (imgui.isKeyDown(imgui.cimgui.ImGuiKey_LeftCtrl) and imgui.isKeyPressed(imgui.cimgui.ImGuiKey_V)) {
                for (copied_node_handles.items) |copied_node| {
                    _ = try csg_tree.copyNode(arena, copied_node, csg_tree.getNode(copied_node).parent);
                    simulation.csg_dirty = true;
                }
            }

            {
                const mouse_pos_f64 = window.getCursorPos();
                const mouse_pos: [2]f32 = .{ @floatCast(mouse_pos_f64[0]), @floatCast(mouse_pos_f64[1]) };

                var inv_proj = zmath.inverse(@as([4]@Vector(4, f32), @bitCast(camera.projection)));
                inv_proj = zmath.transpose(inv_proj);
                var inv_view = zmath.inverse(@as([4]@Vector(4, f32), @bitCast(camera.view)));
                inv_view = zmath.transpose(inv_view);
                const view: [4]@Vector(4, f32) = @bitCast(simulation.view_matrix);
                const projection: [4]@Vector(4, f32) = @bitCast(simulation.projection_matrix);
                var proj_view = zmath.mul(view, projection);
                proj_view = zmath.transpose(proj_view);

                const window_size_int = window.getSize();
                const window_size: [2]f32 = .{ @floatFromInt(window_size_int[0]), @floatFromInt(window_size_int[1]) };

                var ndc = @Vector(4, f32){
                    (2.0 * mouse_pos[0]) / window_size[0] - 1,
                    1.0 - 2.0 * (mouse_pos[1] / window_size[1]),
                    1,
                    1,
                };

                imgui.drawLine(proj_view, imgui.cimgui.ImGui_GetMainViewport(), .{
                    .{ 0.5, 0.5, 0.5 },
                    .{ 10, 10, 10 },
                });

                imgui.setSpatialMatrix(proj_view);

                //try imGuiCSGTreeNodeGizmos(csg_tree, .root);

                if (imgui.beginSpatial("Spatial Log", .{}, .{ 1, @floatCast(@sin(glfw.getTime()) * 100), 1 })) {
                    imgui.text("Bum", .{});

                    imgui.text("{:.2}", .{@sin(glfw.getTime())});
                }
                imgui.end();

                if (imgui.beginSpatial("Spatial Log 2", .{}, .{ 1, 2, 1 })) {
                    imgui.text("Bum", .{});
                }

                imgui.end();

                var ray_direction: @Vector(4, f32) = zmath.mul(
                    inv_proj,
                    ndc,
                );

                ndc[2] = -1;
                ndc[3] = 0;
                ray_direction = zmath.mul(inv_view, ray_direction);

                ray_direction = zmath.normalize3(ray_direction);

                const ray_origin: @Vector(4, f32) = .{ camera.eye[0], camera.eye[1], camera.eye[2], 0 };

                if (imgui.cimgui.ImGui_IsMouseClicked(imgui.cimgui.ImGuiMouseButton_Left) and
                    !imgui.isAnyItemActive() and
                    !imgui.cimgui.ImGui_IsAnyItemFocused() and
                    !imgui.cimgui.ImGui_IsAnyItemHovered() and
                    !imguizmo.ImGuizmo_IsUsing() and
                    !imguizmo.ImGuizmo_IsOver() and !enable_transform_gizmo)
                {
                    const maybe_inst = csg_program.rayMarchSDF(
                        .{ ray_origin[0], ray_origin[1], ray_origin[2] },
                        .{ ray_direction[0], ray_direction[1], ray_direction[2] },
                    );

                    if (maybe_inst) |inst| {
                        if (csg_program.elements_to_nodes.get(inst)) |node| {
                            if (!imgui.cimgui.ImGui_IsKeyDown(imgui.cimgui.ImGuiKey_LeftShift)) {
                                selected_node_handles.clearRetainingCapacity();
                            }
                            try selected_node_handles.append(
                                arena,
                                node,
                            );
                        }
                        std.log.info("ray hit: inst {}", .{inst});
                    }
                }
            }

            if (selected_node_handles.items.len != 0) {
                const selected_node = csg_tree.getNode(selected_node_handles.items[0]);

                var matrix: [4]@Vector(4, f32) = zmath.identity();

                var local_bounds: [2][3]f32 = undefined;

                const resultant_transform = csg_tree.resolveNodeTransform(selected_node_handles.items[0]);

                var rotation: @Vector(4, f32) = selected_node.transform.rotation;

                rotation = math.mulQuat(resultant_transform.rotation, rotation);

                matrix = zmath.mul(zmath.matFromQuat(rotation), matrix);

                switch (selected_node.data) {
                    .box => {
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
                    },
                    .cylinder => |cylinder| {
                        local_bounds[0][0] = -@as(f32, cylinder.radius) * resultant_transform.uniform_scale;
                        local_bounds[0][1] = -@as(f32, cylinder.extrusion_height) * resultant_transform.uniform_scale;
                        local_bounds[0][2] = -@as(f32, cylinder.radius) * resultant_transform.uniform_scale;

                        local_bounds[1][0] = -local_bounds[0][0];
                        local_bounds[1][1] = -local_bounds[0][1];
                        local_bounds[1][2] = -local_bounds[0][2];
                        matrix = zmath.mul(matrix, zmath.scaling(
                            cylinder.radius,
                            cylinder.extrusion_height,
                            cylinder.radius,
                        ));
                    },
                    else => {
                        matrix = zmath.mul(matrix, zmath.scaling(
                            resultant_transform.uniform_scale,
                            resultant_transform.uniform_scale,
                            resultant_transform.uniform_scale,
                        ));
                    },
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

                    if (selected_node_handles.items[0] != node_handle or selected_node.data != .box or selected_node.data != .cylinder) {
                        node.transform.uniform_scale *= delta_scale[0];
                    }
                }

                switch (selected_node.data) {
                    .box => {
                        selected_node.data.box.bounds[0] = @floor(scale[0]);
                        selected_node.data.box.bounds[1] = @floor(scale[1]);
                        selected_node.data.box.bounds[2] = @floor(scale[2]);
                    },
                    .cylinder => {
                        selected_node.data.cylinder.radius = @floor(scale[0]);
                        selected_node.data.cylinder.extrusion_height = @floor(scale[1]);
                        selected_node.data.cylinder.radius = @floor(scale[2]);
                    },
                    else => {},
                }

                if (selected_node_handles.items[0] != .root and selected_node.data != .box and selected_node.data != .cylinder) {
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

        if (@import("builtin").os.tag != .macos) {
            imgui.impl.opengl3.renderDrawData(imgui.getDrawData());
        } else {
            imgui.impl.metal.renderDrawData(
                imgui.getDrawData(),
                simulation.gpu_sim.command_buffer,
                simulation.gpu_sim.render_encoder,
            );
        }

        gpu_context.endFrame();

        glfw.swapBuffers(window);
    }
}

const CSGReparentCommand = struct {
    source: CSGTreeNodeHandle,
    source_parent: CSGTreeNodeHandle,
    destination: CSGTreeNodeHandle = .null,
};

fn imGuiCSGTreeNodeGizmos(
    tree: CSGTree,
    node_handle: CSGTreeNodeHandle,
) !void {
    const node = tree.getNode(node_handle);
    var fmt_buffer: [64]u8 = [_]u8{0} * *64;

    var name: [:0]const u8 = try std.fmt.bufPrintZ(&fmt_buffer, "{s}:{x}", .{ node.name, @backingInt(node_handle) });

    if (name[0] == 0) {
        name = "Root";
    }

    if (imgui.beginSpatial(name, .{}, node.transform.position)) {
        imgui.text("Hi!! {any}", .{node.transform.position});
    }
    imgui.end();

    for (node.children.items) |child| {
        try imGuiCSGTreeNodeGizmos(tree, child);
    }
}

fn imGuiCSGTreeNode(
    tree: *CSGTree,
    gpa: std.mem.Allocator,
    parent_handle: CSGTreeNodeHandle,
    node_handle: CSGTreeNodeHandle,
    selected_nodes: *std.ArrayList(CSGTreeNodeHandle),
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

        if (imgui.beginSpatial("Sus", .{}, node.transform.position / @as(@Vector(3, f32), @splat(128)))) {
            imgui.text("Hi!!", .{});
        }
        imgui.end();

        if (imgui.isItemClicked()) {
            if (selected_nodes.items.len == 0) {
                selected = true;
            } else {
                if (imgui.isKeyDown(imgui.cimgui.ImGuiKey_LeftShift)) {
                    selected = true;
                } else {
                    selected = true;
                    selected_nodes.clearRetainingCapacity();
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

        for (node.children.items) |child| {
            const child_selected = try imGuiCSGTreeNode(
                tree,
                gpa,
                node_handle,
                child,
                selected_nodes,
                reparent_commands,
            );

            if (child_selected) {
                try selected_nodes.append(gpa, child);
            }
        }
    }

    return selected;
}

pub const Camera = struct {
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

pub const CSGTree = struct {
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
        const sim_file_source_z = try arena.dupeSentinel(u8, sim_file_source, 0);

        return try .initFromZonMemory(sim_file_source_z, arena);
    }

    pub fn initFromZonMemory(zon: [:0]const u8, arena: std.mem.Allocator) !CSGTree {
        var diag: std.zon.parse.Diagnostics = .{};

        const serialized_tree = std.zon.parse.fromSliceAlloc(
            CSGTreeZonSerializable,
            arena,
            zon,
            &diag,
            .{},
        ) catch |e| {
            switch (e) {
                error.ParseZon => {
                    var error_iter = diag.iterateErrors();

                    while (error_iter.next()) |err| {
                        std.debug.print("zon error: {f}\n", .{err.fmtMessage(&diag)});
                    }

                    return try .init(arena);
                },
                else => return e,
            }
        };

        const tree = @as(*const CSGTree, @ptrCast(&serialized_tree)).*;

        return tree;
    }

    pub fn saveToFile(self: *@This(), io: std.Io, gpa: std.mem.Allocator, file: std.Io.File) !void {
        self.trimArrayLists();

        try file.setLength(io, 0);

        var buffer: [1024]u8 = undefined;
        var sim_file_writer = file.writer(io, &buffer);
        var serializer: std.zon.Serializer = .{
            .writer = &sim_file_writer.interface,
        };

        const serialized_node = try self.serializeNodeZon(gpa, .root, &serializer);

        try serializer.valueArbitraryDepth(serialized_node, .{
            .emit_default_optional_fields = false,
        });

        try sim_file_writer.flush();
    }

    pub fn serializeNodeZon(
        self: *@This(),
        gpa: std.mem.Allocator,
        node_handle: CSGTreeNodeHandle,
        serializer: *std.zon.Serializer,
    ) !CSGTreeNodeZonSerializable {
        const node = self.getNode(node_handle);
        const children = try gpa.alloc(CSGTreeNodeZonSerializable, node.children.items.len);
        const out_node: CSGTreeNodeZonSerializable = .{
            .name = node.name,
            .children = children,
            .modifiers = node.modifiers,
            .material = @backingInt(node.material),
        };

        for (node.children.items, children) |child, *out_child| {
            out_child.* = try self.serializeNodeZon(
                gpa,
                child,
                serializer,
            );
        }

        return out_node;
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
        return &self.nodes.items[@backingInt(handle)];
    }

    pub fn addNode(self: *@This(), gpa: std.mem.Allocator, parent: CSGTreeNodeHandle) !CSGTreeNodeHandle {
        const handle_int: u32 = @intCast(self.nodes.items.len);
        const handle: CSGTreeNodeHandle = @fromBackingInt(@intCast(handle_int));
        try self.nodes.append(gpa, .{
            .parent = parent,
        });

        try self.nodes.items[@backingInt(parent)].children.append(gpa, handle);

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

    pub fn resolveNodeTransform(
        self: *@This(),
        node_handle: CSGTreeNodeHandle,
    ) Simulation.AffineTransform3D {
        if (node_handle == .root) {
            return .identity;
        }

        const node = self.getNode(node_handle);
        const parent_transform = self.resolveNodeTransform(node.parent);

        return .compose(parent_transform, node.transform);
    }

    pub fn moveNode(
        self: *@This(),
        gpa: std.mem.Allocator,
        handle: CSGTreeNodeHandle,
        new_parent: CSGTreeNodeHandle,
    ) !void {
        const previous_parent = self.getNode(handle).parent;
        const previous_parent_node = self.getNode(previous_parent);
        const new_parent_node = self.getNode(new_parent);

        self.deleteNode(
            gpa,
            previous_parent,
            std.mem.find(CSGTreeNodeHandle, previous_parent_node.children.items, &.{handle}).?,
        );

        const node = self.getNode(handle);
        node.parent = new_parent;
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
    ) !u32 {
        const element_index: u16 = @intCast(program.elements.items.len);
        _ = try program.elements.addOne(gpa);

        try tree.compileNode(
            .root,
            gpa,
            program,
            element_index,
            .null,
            .identity,
        );

        return element_index;
    }

    pub fn compileNode(
        tree: *@This(),
        node_handle: CSGTreeNodeHandle,
        gpa: std.mem.Allocator,
        program: *Simulation.CSGProgram,
        element_index: u16,
        parent_handle: CSGTreeNodeHandle,
        parent_transform: Simulation.AffineTransform3D,
    ) !void {
        _ = parent_handle; // autofix
        const node = tree.getNode(node_handle);

        if (node.modifiers.revolution != 0) {
            try program.element_params.append(gpa, node.modifiers.revolution);
        }

        if (node.modifiers.extrusion != 0) {
            try program.element_params.append(gpa, node.modifiers.extrusion);
        }

        if (node.modifiers.rounding.rounding != 0) {
            try program.element_params.append(gpa, node.modifiers.rounding.rounding);
        }

        std.debug.print("{}\n", .{node.children.items.len});

        program.elements.items[element_index] = .{
            .type = .{
                .type = node.data,
                .modifiers = .{
                    .rounding = node.modifiers.rounding.rounding != 0,
                    .extrusion = node.modifiers.extrusion != 0,
                    .revolution = node.modifiers.revolution != 0,
                },
            },
            .params_start = @intCast(program.element_params.items.len),
            .children_start = @intCast(program.elements.items.len),
            .children_count = @intCast(node.children.items.len),
        };

        const resolved_transform: Simulation.AffineTransform3D = .compose(parent_transform, node.transform);

        try program.transforms.append(gpa, resolved_transform);
        const element_bounds = try program.element_bounds.addOne(gpa);
        //TODO: compute bounds
        element_bounds.* = .{ 128, 128, 128, 0 };

        const children = try program.elements.addManyAsSlice(gpa, program.elements.items[element_index].children_count);
        _ = children; // autofix

        switch (node.data) {
            .box => |box| {
                try program.element_params.appendSlice(gpa, &box.bounds);
            },
            .cylinder => |cylinder| {
                try program.element_params.append(gpa, cylinder.extrusion_height);
                try program.element_params.append(gpa, cylinder.radius);
            },
            .sphere => |sphere| {
                try program.element_params.append(gpa, sphere.radius);
            },
            .n_gon => |n_gon| {
                try program.element_params.append(gpa, n_gon.radius);
                try program.element_params.append(gpa, n_gon.sides);
            },
            .@"union" => {},
            .intersection => {},
            .difference => {},
            .extrude => {},
            .revolve => {},
        }

        for (node.children.items, 0..) |child, i| {
            const child_element_index: u16 = @intCast(program.elements.items[element_index].children_start + i);

            try tree.compileNode(
                child,
                gpa,
                program,
                child_element_index,
                node_handle,
                resolved_transform,
            );

            try program.elements_to_nodes.put(gpa, child_element_index, child);
        }
    }
};

const CSGTreeZonSerializable = struct {
    nodes: std.ArrayList(CSGTreeNodeZonSerializable) = .empty,
};

const CSGTreeNode = struct {
    transform: Simulation.AffineTransform3D = .identity,
    data: Data = .@"union",
    modifiers: Modifiers = .{},
    material: Simulation.VoxelMaterialHandle = .air,
    parent: CSGTreeNodeHandle = .root,
    children: std.ArrayList(CSGTreeNodeHandle) = .empty,
    name: [:0]const u8 = "",

    pub const Modifiers = struct {
        rounding: ModifierRounding = .{},
        extrusion: f32 = 0,
        revolution: f32 = 0,
    };

    pub const Data = union(Simulation.SdfElementType) {
        @"union",
        intersection,
        difference,
        box: struct {
            bounds: [3]f32,
        },
        cylinder: struct {
            extrusion_height: f32,
            radius: f32,
        },
        sphere: struct {
            radius: f32,
        },
        extrude,
        revolve,
        n_gon: struct {
            radius: f32,
            sides: f32,
        },

        pub fn editorDefault(comptime tag: Simulation.SdfElementType) Data {
            return switch (tag) {
                .@"union",
                .intersection,
                .difference,
                .extrude,
                .revolve,
                => tag,
                .sphere => .{
                    .sphere = .{
                        .radius = 10,
                    },
                },
                .box => .{
                    .box = .{
                        .bounds = .{ 10, 10, 10 },
                    },
                },
                .cylinder => .{
                    .cylinder = .{
                        .extrusion_height = 10,
                        .radius = 10,
                    },
                },
                .n_gon => .{
                    .n_gon = .{
                        .radius = 10,
                        .sides = 10,
                    },
                },
            };
        }
    };

    pub const ModifierRounding = struct {
        rounding: f32 = 0,
    };
};

const CSGTreeNodeZonSerializable = struct {
    transform: Simulation.AffineTransform3D = .identity,
    data: CSGTreeNode.Data = .@"union",
    modifiers: CSGTreeNode.Modifiers = .{},
    material: u32 = 0,
    children: []CSGTreeNodeZonSerializable = &.{},
    name: [:0]const u8 = "",
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

pub fn formatNumberWithUnits(allocator: std.mem.Allocator, x: f32) ![]const u8 {
    var unit: []const u8 = "";

    var value: f32 = x;

    if (x > 1000 and x < 1000_000) {
        value /= 1000;
        unit = "K";
    }

    if (x > 1000_000) {
        value /= 1000_000;
        unit = "M";
    }

    return try std.fmt.allocPrint(allocator, "{:.2}{s}", .{ value, unit });
}

test {
    _ = std.testing.refAllDecls(@This());
}

pub const math = @import("lib").math;
pub const zmath = @import("lib").zmath;
pub const shaders = @import("shaders/shaders.zig");

const imgui = @import("imgui.zig");
const Simulation = @import("Simulation.zig");
const glfw = @import("zglfw");
const zigimg = @import("zigimg");
const std = @import("std");
const stb_image = @import("stb_image.zig");
const imguizmo = @import("imguizmo.zig");
const gpu = @import("gpu.zig");
