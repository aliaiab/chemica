pub const Context = struct {
    device: metal.MetalDevice = undefined,
    command_buffer: metal.MetalCommandBuffer = undefined,
    render_encoder: metal.MetalRenderEncoder = undefined,
    swapchain: objc.Object = undefined,
    render_pass: metal.MetalRenderPassDescriptor = undefined,
    surface: objc.Object = undefined,
    queue: metal.MetalCommandQueue = undefined,

    pub fn init(
        arena: std.mem.Allocator,
        window: *glfw.Window,
        io: std.Io,
    ) !Context {
        _ = io;
        var context: Context = undefined;

        context.device = (try metal.getAllDevices(arena))[0];

        const CAMetalLayer = objc.getClass("CAMetalLayer").?;
        const swapchain = CAMetalLayer.msgSend(objc.Object, objc.Sel.registerName("layer"), .{});
        context.swapchain = swapchain;

        swapchain.setProperty("device", context.device.handle.value);
        swapchain.setProperty("opaque", true);

        const ns_window: objc.Object = .{ .value = @ptrCast(@alignCast(glfw.getCocoaWindow(window))) };

        const content_view = ns_window.getProperty(objc.Object, "contentView");

        content_view.setProperty("layer", swapchain);
        content_view.setProperty("wantsLayer", true);

        context.queue = try context.device.createCommandQueue();
        //context.command_buffer = try context.queue.createCommandBuffer();

        try imgui.impl.metal.init(context.device);
        try imgui.impl.glfw.initForMetal(window, .{});

        return .{};
    }

    pub fn deinit(context: Context) void {
        _ = context; // autofix
    }

    pub fn beginFrame(context: *Context) void {
        const surface = context.swapchain.msgSend(objc.Object, objc.Sel.registerName("nextDrawable"), .{});
        context.surface = surface;

        const surface_tex_obj = surface.getProperty(objc.c.id, "texture");
        var surface_tex: metal.MetalTexture = .{ .handle = .{ .value = surface_tex_obj } };

        context.render_pass = metal.MetalRenderPassDescriptor.init();
        context.render_pass.setClearColor(1, 0, 0, 0, 0);
        context.render_pass.setColorTexture(&surface_tex, 0);

        context.render_encoder = context.command_buffer.createRenderEncoder(
            &context.render_pass,
        ) catch @panic("oom");

        imgui.impl.metal.newFrame(context.render_pass);
    }

    pub fn endFrame(context: *Context) void {
        context.command_buffer.present(context.surface.value);

        context.render_encoder.end();

        context.command_buffer.commit();
        context.command_buffer.waitForCompletion();

        context.render_encoder.deinit();
        context.command_buffer.deinit();
        context.command_buffer = context.queue.createCommandBuffer() catch return;
        context.render_pass.deinit();
    }

    pub fn renderGizmos(
        context: *Context,
        scene: *const asym.geo.Scene,
        gizmo_views: []const asym.geo.Scene.View,
    ) void {
        _ = context;
        _ = scene;
        _ = gizmo_views;
    }
};

pub const Simulation = struct {
    device: metal.MetalDevice,
    queue: metal.MetalCommandQueue,
    command_buffer: metal.MetalCommandBuffer,
    render_encoder: metal.MetalRenderEncoder,
    render_pass: metal.MetalRenderPassDescriptor,
    output_texture: metal.MetalTexture,
    scene_thumbnails: std.StringHashMapUnmanaged(*Texture),

    pub fn init(context: *Context, _sim: @import("../Simulation.zig"), arena: std.mem.Allocator) !Simulation {
        _ = _sim;
        _ = arena;
        var sim: Simulation = undefined;

        sim.device = context.device;
        sim.queue = context.queue;
        sim.command_buffer = context.command_buffer;
        sim.render_pass = metal.MetalRenderPassDescriptor.init();
        //sim.output_texture = try sim.device.createTexture(1920, 1080, true);
        sim.render_pass.setColorTexture(&sim.output_texture, 0);
        sim.render_pass.setClearColor(1, 0, 0, 0, 0);

        return sim;
    }

    pub fn deinit() void {}

    pub fn updateCSGProgram(
        gpu_sim: *Simulation,
        sim: @import("../Simulation.zig"),
        program: CSGProgram,
    ) !void {
        _ = gpu_sim;
        _ = sim;
        _ = program;
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
        _ = sim;
        _ = context;
        _ = shader_uniforms;
        _ = render_texture;
        _ = scene_root_index;
        _ = options;
    }

    pub fn renderSceneThumbnail(
        gpu_sim: *Simulation,
        context: Context,
        sim: *@import("../Simulation.zig"),
        scene_root_index: u32,
        scene_path: []const u8,
        gpa: std.mem.Allocator,
    ) !u32 {
        _ = gpu_sim;
        _ = context;
        _ = sim;
        _ = scene_root_index;
        _ = scene_path;
        _ = gpa;
        return 0;
    }

    pub fn update(sim: Simulation, _sim: *@import("../Simulation.zig"), shader_uniforms: ShaderUniforms) void {
        _ = sim;
        _ = _sim;
        _ = shader_uniforms;
    }

    pub fn render2DScene(
        gpu_sim: *Simulation,
        context: Context,
        sim: *@import("../Simulation.zig"),
        scene_root_index: u32,
        gpa: std.mem.Allocator,
        width: u32,
        height: u32,
    ) !*Texture {
        _ = gpu_sim; // autofix
        _ = context; // autofix
        _ = sim; // autofix
        _ = scene_root_index; // autofix
        _ = gpa; // autofix
        _ = width; // autofix
        _ = height; // autofix
        return undefined;
    }
};

const metal = @import("metal");
const ShaderUniforms = @import("../Simulation.zig").ShaderUniforms;
const std = @import("std");
const glfw = @import("zglfw");
const imgui = @import("../imgui.zig");
const objc = @import("objc");
const Texture = @import("../gpu.zig").Texture;
const CSGProgram = @import("../Simulation.zig").CSGProgram;
const asym = @import("../asym.zig");
