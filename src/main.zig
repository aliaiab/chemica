pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(arena);
    _ = args; // autofix

    if (@import("builtin").os.tag == .linux and @import("builtin").mode == .Debug) {
        //We do this in debug mode so that we can do renderdoc captures
        try glfw.initHint(.platform, glfw.Platform.x11);
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
    defer simulation.deinit(gpa);

    try simulation.voxel_materials.append(gpa, .{
        .heat_conductivity = 0,
    });
    try simulation.voxel_materials_visual.append(gpa, .{});

    try simulation.voxel_materials.append(gpa, .{
        .heat_conductivity = 0.5,
    });
    try simulation.voxel_materials_visual.append(gpa, .{
        .albedo = packUnorm4x8(.{ 0.89, 0.79, 0.55, 1.0 }),
    });

    try simulation.voxel_materials.append(gpa, .{
        .heat_conductivity = 1,
        .melting_point = 1000,
    });
    try simulation.voxel_materials_visual.append(gpa, .{
        .albedo = packUnorm4x8(.{ 0.29, 0.29, 0.29, 1.0 }),
    });

    try simulation.voxel_materials.append(gpa, .{
        .heat_conductivity = 0.9,
        .melting_point = 0,
        .density = 0.5,
    });
    try simulation.voxel_materials_visual.append(gpa, .{
        .albedo = packUnorm4x8(.{ 0.17, 0.56, 0.82, 0.19 }),
    });

    try simulation.voxel_materials.append(gpa, .{
        .heat_conductivity = 3,
        .melting_point = 3000,
        .boiling_point = 4000,
    });
    try simulation.voxel_materials_visual.append(gpa, .{
        .albedo = 0xff1d2971,
    });

    try simulation.csg_invocations.append(gpa, .{
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

    var csg_tree: CSGTree = try .init(gpa);

    var selected_node_handle: CSGTreeNodeHandle = .null;
    selected_node_handle = selected_node_handle;

    var csg_program: Simulation.CSGProgram = .{};

    try simulation.point_lights.append(gpa, .{
        .position = .{ 128, 128, 64 },
        .radiance = 1,
        .colour = packUnorm4x8(.{ 0.5, 0.3, 0.3, 1 }),
    });

    camera.target = .{
        @floatFromInt(simulation.width / 2),
        @floatFromInt(simulation.height / 2),
        @floatFromInt(simulation.depth / 2),
    };

    simulation.enable_simulation = false;

    imgui.getIO().ConfigFlags |= imgui.cimgui.ImGuiConfigFlags_DockingEnable;

    while (!window.shouldClose()) {
        glfw.pollEvents();

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

        try csg_tree.compile(gpa, &csg_program);

        try simulation.updateCSGProgram(csg_program);

        simulation.update();

        gl.UseProgram(env_map_shader);
        gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, simulation.uniform_buffer);
        gl.BindTexture(gl.TEXTURE_2D, env_map_texture);
        gl.BindTextureUnit(2, env_map_texture);

        gl.BindVertexArray(simulation.vertex_array);
        gl.Disable(gl.CULL_FACE);
        gl.DrawArrays(gl.TRIANGLES, 0, 36);

        gl.BindTextureUnit(22, env_map_texture);

        simulation.render();

        if (window.getKey(.space) == .press) {
            simulation.enable_simulation = !simulation.enable_simulation;
        }

        if (window.getKey(.r) == .press) {
            simulation.csg_dirty = true;
            simulation.enable_simulation = false;
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

            if (selected_node_handle != .null) {
                const selected_node = csg_tree.getNode(selected_node_handle);

                var matrix: [4]@Vector(4, f32) = zmath.identity();
                matrix = zmath.mul(matrix, zmath.scaling(
                    selected_node.transform.uniform_scale,
                    selected_node.transform.uniform_scale,
                    selected_node.transform.uniform_scale,
                ));
                matrix = zmath.mul(matrix, zmath.translation(
                    selected_node.transform.position[0],
                    selected_node.transform.position[1],
                    selected_node.transform.position[2],
                ));

                selected_node.transform.rotation[3] = -selected_node.transform.rotation[3];
                matrix = zmath.mul(matrix, zmath.matFromQuat(selected_node.transform.rotation));
                selected_node.transform.rotation[3] = -selected_node.transform.rotation[3];

                const snap: [3]f32 = .{ 1, 1, 1 };
                _ = snap; // autofix
                var local_bounds: [2][3]f32 = .{
                    .{ -100, -100, -100 }, .{ 100, 100, 100 },
                };

                if (imguizmo.manipulate(
                    @ptrCast(&camera.view),
                    @ptrCast(&camera.projection),
                    .universal,
                    .local,
                    @ptrCast(&matrix),
                    .{
                        .local_bounds = @ptrCast(&local_bounds),
                    },
                )) {
                    simulation.csg_dirty = true;
                }

                const translation: [3]f32 = .{
                    @floor(matrix[3][0]),
                    @floor(matrix[3][1]),
                    @floor(matrix[3][2]),
                };

                const scale: [3]f32 = .{
                    (matrix[0][0]),
                    (matrix[1][1]),
                    (matrix[2][2]),
                };

                selected_node.transform.position = translation;
                selected_node.transform.uniform_scale = scale[0];
            }
        }

        {
            if (imgui.begin("CSG Editor", .{})) {
                imgui.text("Transform", .{});

                if (selected_node_handle != .null) {
                    const selected_node = csg_tree.getNode(selected_node_handle);
                    _ = imgui.dragFloat(
                        "Scale",
                        "{}",
                        &selected_node.transform.uniform_scale,
                        .{},
                    );

                    _ = imgui.dragFloat3(
                        "Translation",
                        "{}",
                        &selected_node.transform.position,
                        .{},
                    );

                    const material_names = [_][*]const u8{
                        "Sand",
                        "Stone",
                        "Water",
                        "Copper",
                        "Glass",
                    };

                    var material: usize = @intFromEnum(selected_node.material) - 1;

                    simulation.csg_dirty |= imgui.combo("Material", &material, &material_names);

                    selected_node.material = @enumFromInt(material + 1);
                }

                if (imgui.button("Add Node", .{})) {
                    imgui.openPopup("node_type_popup");
                }

                if (imgui.beginPopup("node_type_popup")) {
                    if (imgui.selectable("Box")) {
                        const node_handle = try csg_tree.addNode(gpa, .root);

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

                        std.mem.copyForwards(u8, &node.name, "Box");
                        simulation.csg_dirty = true;

                        selected_node_handle = node_handle;
                    }

                    if (imgui.selectable("Sphere")) {
                        const node_handle = try csg_tree.addNode(gpa, .root);

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
                        std.mem.copyForwards(u8, &node.name, "Sphere");
                        simulation.csg_dirty = true;

                        selected_node_handle = node_handle;
                    }

                    imgui.endPopup();
                }

                const root_node = csg_tree.getNode(.root);

                for (root_node.children.items) |child| {
                    imGuiCSGTreeNode(
                        csg_tree,
                        .root,
                        child,
                        &selected_node_handle,
                    );
                }
            }
            imgui.end();
        }

        imgui.render();

        imgui.impl.opengl3.renderDrawData(imgui.getDrawData());

        glfw.swapBuffers(window);
    }
}

fn imGuiCSGTreeNode(
    tree: CSGTree,
    parent_handle: CSGTreeNodeHandle,
    node_handle: CSGTreeNodeHandle,
    selected_node: *CSGTreeNodeHandle,
) void {
    _ = parent_handle; // autofix
    imgui.pushId(node_handle);
    defer imgui.popId();

    const node = tree.getNode(node_handle);

    if (imgui.treeNode(@ptrCast(&node.name), .{
        .flags = .{
            .selected = selected_node.* == node_handle,
        },
    })) {
        defer imgui.treePop();

        if (imgui.isItemClicked()) {
            selected_node.* = node_handle;
        }

        for (node.children.items) |child| {
            imGuiCSGTreeNode(
                tree,
                node_handle,
                child,
                selected_node,
            );
        }
    }
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

fn packUnorm4x8(v: [4]f32) u32 {
    const Rgba = packed struct(u32) {
        x: u8,
        y: u8,
        z: u8,
        w: u8,
    };

    const rgba: Rgba = .{
        .x = @intFromFloat(v[0] * 255),
        .y = @intFromFloat(v[1] * 255),
        .z = @intFromFloat(v[2] * 255),
        .w = @intFromFloat(v[3] * 255),
    };

    return @bitCast(rgba);
}

const CSGTreeNodeHandle = enum(u32) {
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
        const node = self.getNode(handle);

        const new_handle = try self.addNode(gpa, parent);

        self.getNode(new_handle).* = node.*;

        self.getNode(new_handle).children = try node.children.clone(gpa);

        for (self.getNode(new_handle).children.items) |*child| {
            child.* = try self.copyNode(gpa, child.*, new_handle);
        }
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
        program.transforms.clearRetainingCapacity();

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

        if (node.unary_op != .identity) {
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

        const identity_transform_index: ?u32 = null;

        if (node.unary_op == .unary_op_extrude_pre) {
            //TODO: fill in
        }

        const instruction = try program.instructions.addOne(gpa);

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
            .empty => {},
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
    }
};

const CSGTreeNode = struct {
    transform: Simulation.CSGRigidTransform = .identity,
    data: Data = .empty,
    material: Simulation.VoxelMaterialHandle = .air,
    children: std.ArrayList(CSGTreeNodeHandle) = .empty,
    name: [16]u8 = [1]u8{0} ** 16,
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
    };
};

fn glfwScrollCallback(window: *glfw.Window, x: f64, y: f64) callconv(.c) void {
    _ = x; // autofix
    const scroll = window.getUserPointer(f32);

    scroll.?.* = @floatCast(-y * 0.1);
}

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
