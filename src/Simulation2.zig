render_pipeline: *gpu.Pipeline,
fill_pipeline: *gpu.Pipeline,

pub fn init(
    gpa: gpu.mem.Allocator,
) !Simulation {
    _ = gpa; // autofix
    const self: Simulation = .{};

    return self;
}

pub fn update(
    self: Simulation,
    commands: *gpu.CommandBuffer,
    transient_arena: gpu.mem.Allocator,
    timestep: f32,
) !void {
    _ = timestep; // autofix
    _ = transient_arena; // autofix
    _ = commands; // autofix
    _ = self; // autofix
}

pub fn render(
    self: Simulation,
    commands: *gpu.CommandBuffer,
    transient_arena: gpu.mem.Allocator,
) !void {
    _ = transient_arena; // autofix
    _ = commands; // autofix
    _ = self; // autofix
}

pub fn vertexKernel(
    vertex_positions: [*]addrspace(gpu.kernel.address_space) const [3]f32,
) struct { @Vector(4, f32), RendererKernelPacket } {
    _ = vertex_positions; // autofix
    return .{
        @splat(0),
        undefined,
    };
}

pub fn fragmentKernel(
    input_packet: RendererKernelPacket,
) [4]f32 {
    _ = input_packet; // autofix
    return @splat(0);
}

pub const RendererKernelPacket = extern struct {
    pad: u32,
};

pub fn fillComputeKernel(
    params: gpu.kernel.ComputeCommandParameters,
) void {
    _ = params; // autofix
}

pub const VoxelHeapIndex = enum(u32) {
    null = 0xffff,
    _,
};

pub const SimulationState = extern struct {
    voxel_material_ids: gpu.kernel.Pointer(VoxelMaterialId),
    voxel_temperatures: gpu.kernel.Pointer(f16),
};

pub const VoxelMaterialId = enum(u16) {
    air = 0,
    _,
};

pub const VoxelMaterial = extern struct {
    molar_mass: f32,
    density: f32,
    heat_conductivity: f32,
    thermal_emissivity: f32,
    heat_capacity: f32,
    melting_point: f32,
    boiling_point: f32,
};

pub const VoxelMaterialVisual = extern struct {
    albedo: u32,
    roughness_metalness: u32,
    reflectivity: f32,
    refractive_index: f32,
};

pub const renderer_pipeline_exported = gpu.kernel.exportRasterVertexPipeline(@This(), "vertexKernel", "fragmentKernel", .{});

pub const fill_pipeline_exported = gpu.kernel.exportComputePipeline(
    @This(),
    "fillComputeKernel",
    .{
        .x = 8,
        .y = 8,
        .z = 8,
    },
);

comptime {
    _ = renderer_pipeline_exported;
    _ = fill_pipeline_exported;
}

const Simulation = @This();
const gpu = @import("gpu.zig");
