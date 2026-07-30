pub const Simulation = struct {
    device: metal.MetalDevice,
    queue: metal.MetalCommandQueue,
    command_buffer: metal.MetalCommandBuffer,
    render_encoder: metal.MetalRenderEncoder,
    render_pass: metal.MetalRenderPassDescriptor,
    output_texture: metal.MetalTexture,

    pub fn init(arena: std.mem.Allocator) !Simulation {
        var sim: Simulation = undefined;

        sim.device = (try metal.getAllDevices(arena))[0];
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
