pub const Context = struct {
    device: metal.MetalDevice = undefined,
    swapchain: objc.Object = undefined,

    pub fn init(arena: std.mem.Allocator, window: *glfw.Window) !Context {
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

        try imgui.impl.metal.init(context.device);
        try imgui.impl.glfw.initForMetal(window, .{});

        return .{};
    }

    pub fn deinit(context: Context) void {
        _ = context; // autofix
    }

    pub fn beginFrame(context: Context) void {
        const surface = context.swapchain.msgSend(objc.Object, objc.Sel.registerName("nextDrawable"), .{});

        const surface_tex_obj = surface.getProperty(objc.c.id, "texture");
        var surface_tex: metal.MetalTexture = .{ .handle = .{ .value = surface_tex_obj } };

        context.render_pass = metal.MetalRenderPassDescriptor.init();
        context.render_pass.setClearColor(1, 0, 0, 0, 0);
        context.render_pass.setColorTexture(&surface_tex, 0);

        context.render_encoder = try context.command_buffer.createRenderEncoder(
            &context.render_pass,
        );

        imgui.impl.metal.newFrame(context.render_pass);
    }

    pub fn endFrame(context: Context) void {
        context.command_buffer.present(context.surface.value);

        context.render_encoder.end();

        context.command_buffer.commit();
        context.command_buffer.waitForCompletion();

        context.render_encoder.deinit();
        context.command_buffer.deinit();
        context.command_buffer = try context.queue.createCommandBuffer();
        context.render_pass.deinit();
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

    pub fn init(arena: std.mem.Allocator) !Simulation {
        _ = arena; // autofix
        var sim: Simulation = undefined;

        sim.queue = try sim.device.createCommandQueue();
        sim.command_buffer = try sim.queue.createCommandBuffer();
        sim.render_pass = metal.MetalRenderPassDescriptor.init();
        sim.output_texture = try sim.device.createTexture(1920, 1080, true);
        sim.render_pass.setColorTexture(&sim.output_texture, 0);
        sim.render_pass.setClearColor(1, 0, 0, 0, 0);

        return sim;
    }

    pub fn deinit() void {}

    pub fn update(sim: Simulation, shader_uniforms: ShaderUniforms) void {
        _ = sim;
        _ = shader_uniforms;
    }
};

const metal = @import("metal");
const ShaderUniforms = @import("../Simulation.zig").ShaderUniforms;
const std = @import("std");
const glfw = @import("zglfw");
const imgui = @import("../imgui.zig");
const objc = @import("objc");
const Texture = @import("../gpu.zig").Texture;
