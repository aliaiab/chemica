extern fn cppMain(argc: c_int, argv: [*][*]const u8) void;

export const embedded_environment_map = @embedFile("Assets/vintage_measuring_lab_2k.png");
export const embedded_environment_map_length = embedded_environment_map.len;

const use_cpp = false;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(arena);

    const argv = try arena.alloc([*]const u8, args.len);

    for (argv, args) |*argv_arg, arg| {
        argv_arg.* = arg.ptr;
    }

    if (use_cpp) {
        cppMain(@intCast(args.len), argv.ptr);
        return;
    }

    if (@import("builtin").os.tag == .linux) {
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

    try simulation.voxel_materials.append(gpa, .{});
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
    });
    try simulation.voxel_materials_visual.append(gpa, .{
        .albedo = packUnorm4x8(.{ 0.17, 0.56, 0.82, 0.19 }),
    });

    try simulation.voxel_materials.append(gpa, .{
        .heat_conductivity = 3,
        .melting_point = 3000,
    });
    try simulation.voxel_materials_visual.append(gpa, .{
        .albedo = 0xff1d2971,
    });

    try simulation.csg_invocations.append(gpa, .{
        .transform = .identity,
        .bound_min = undefined,
        .bound_max = undefined,
    });

    _ = cimgui.ImGui_CreateContext(null);

    _ = cimgui.cImGui_ImplGlfw_InitForOpenGL(@ptrCast(window), true);
    _ = cimgui.cImGui_ImplOpenGL3_Init();

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

    const env_map_data = stb_image.stbi_load_from_memory(
        embedded_environment_map,
        @intCast(embedded_environment_map_length),
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
        .{ .type = gl.VERTEX_SHADER, .binary = @embedFile("Shaders/Include/EnvMapVertex.spv") },
        .{ .type = gl.FRAGMENT_SHADER, .binary = @embedFile("Shaders/Include/EnvMapFragment.spv") },
    });
    defer gl.DeleteProgram(env_map_shader);

    _ = window.setScrollCallback(glfwScrollCallback);
    var mouse_scroll: f32 = 0;

    window.setUserPointer(&mouse_scroll);

    while (!window.shouldClose()) {
        glfw.pollEvents();

        gl.ClearColor(0, 0, 0, 1);
        gl.ClearDepthf(1);
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        cimgui.cImGui_ImplOpenGL3_NewFrame();
        cimgui.cImGui_ImplGlfw_NewFrame();

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

            if (window.getMouseButton(.left) != .release and !cimgui.ImGui_IsAnyItemActive()) {
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

        simulation.update();

        gl.UseProgram(env_map_shader);
        gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, simulation.uniform_buffer);
        gl.BindTexture(gl.TEXTURE_2D, env_map_texture);
        gl.BindTextureUnit(2, env_map_texture);

        gl.BindVertexArray(simulation.vertex_array);
        gl.Disable(gl.CULL_FACE);
        gl.DrawArrays(gl.TRIANGLES, 0, 36);

        simulation.render();

        cimgui.ImGui_NewFrame();

        cimgui.ImGui_ShowDemoWindow(null);

        {
            if (imgui.begin("CSG Editor", .{})) {
                imgui.text("Transform", .{});

                if (imgui.button("Add Node", .{})) {
                    imgui.openPopup("node_type_popup");
                }

                if (imgui.beginPopup("node_type_popup")) {
                    if (imgui.selectable("Box")) {}
                    if (imgui.selectable("Sphere")) {}

                    imgui.endPopup();
                }
            }
            imgui.end();
        }

        cimgui.ImGui_Render();

        cimgui.cImGui_ImplOpenGL3_RenderDrawData(cimgui.ImGui_GetDrawData());

        glfw.swapBuffers(window);
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

const math = struct {
    pub fn mulQuat(a: @Vector(4, f32), b: @Vector(4, f32)) @Vector(4, f32) {
        var result: @Vector(4, f32) = undefined;

        const lhs_w: @Vector(4, f32) = @splat(a[3]);
        const rhs_w: @Vector(4, f32) = @splat(b[3]);

        result = lhs_w * b + rhs_w * a - zmath.cross3(a, b);

        result[3] = a[3] * b[3] - zmath.dot3(a, b)[0];

        return result;
    }
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

fn glfwScrollCallback(window: *glfw.Window, x: f64, y: f64) callconv(.c) void {
    _ = x; // autofix
    const scroll = window.getUserPointer(f32);

    scroll.?.* = @floatCast(-y * 0.1);
}

const imgui = @import("imgui.zig");
const Simulation = @import("Simulation.zig");
const zmath = @import("zmath");
const cimgui = @import("cimgui");
const glfw = @import("zglfw");
const gl = @import("gl");
const zigimg = @import("zigimg");
const std = @import("std");
const stb_image = @import("stb_image.zig");
