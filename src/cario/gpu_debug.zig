//! The debugging layer for validation and command buffer replay

var context: struct {
    arena: std.mem.Allocator = undefined,
    allocations: std.ArrayList(Allocation) = .empty,
    command_buffers: std.AutoArrayHashMapUnmanaged(*CommandBuffer, CommandBufferData) = .empty,
} = .{};

const Allocation = struct {
    base: usize,
    size: usize,
    memory_type: gpu.mem.Allocator.MemoryType,
};

const CommandBufferData = struct {
    descriptor_heap: ?*DescriptorHeap = null,
    sampler_descriptor_heap: ?*DescriptorHeap = null,
    pipeline: ?*Pipeline = null,
    depth_stencil_state: ?DepthStencilState = null,
    blend_state: ?BlendState = null,
    viewport: ?[4]f32 = null,
    scissor: ?[4]u32 = null,
    commands: std.ArrayList(Command) = .empty,
    command_timestamps: std.ArrayList(*gpu.debug.TimestampQuery) = .empty,
    obtain_profile: bool = true,

    pub const Command = union(enum) {
        set_state_descriptor_heap: struct { descriptor_heap: *DescriptorHeap },
        set_state_pipeline: struct { pipeline: *Pipeline },
        set_state_depth_stencil: struct { state: DepthStencilState },
        set_state_blend: struct { state: BlendState },
        set_state_viewport: struct { viewport: [4]f32 },
        set_state_scissor: struct { scissor: [4]u32 },
    };
};

pub fn memAlloc(
    size: usize,
    alignment: std.mem.Alignment,
    memory_type: mem.Allocator.MemoryType,
) std.mem.Allocator.Error!void {
    _ = size; // autofix
    _ = alignment; // autofix
    _ = memory_type; // autofix
}

pub fn memFree(memory: []u8) void {
    _ = memory; // autofix
}

pub fn memCopy(
    command_buffer: *CommandBuffer,
    dest_gpu: []u8,
    src_gpu: []const u8,
) void {
    _ = command_buffer; // autofix
    _ = dest_gpu; // autofix
    _ = src_gpu; // autofix
}

pub fn selectDevice(
    options: DeviceSelectionOptions,
    arena: std.mem.Allocator,
) DeviceSelectionError!*Device {
    _ = arena; // autofix
    _ = options; // autofix
}

pub fn freeDevice(device: Device) void {
    _ = device; // autofix
}

pub fn setStateDevice(
    device: *Device,
) void {
    _ = device; // autofix
}

pub fn createRasterVertexPipeline(
    vertex_ir: []const u8,
    fragment_ir: []const u8,
    descriptor_mapping: DescriptorHeapMapping,
    description: RasterPipelineDescription,
) *Pipeline {
    _ = vertex_ir; // autofix
    _ = fragment_ir; // autofix
    _ = descriptor_mapping; // autofix
    _ = description; // autofix
}

pub fn createRasterMeshPipeline(
    mesh_ir: []const u8,
    fragment_ir: []const u8,
    descriptor_mapping: DescriptorHeapMapping,
    description: RasterPipelineDescription,
) *Pipeline {
    _ = mesh_ir; // autofix
    _ = fragment_ir; // autofix
    _ = descriptor_mapping; // autofix
    _ = description; // autofix
}

pub fn createComputePipeline(
    compute_ir: []const u8,
    descriptor_mapping: DescriptorHeapMapping,
) *Pipeline {
    _ = compute_ir; // autofix
    _ = descriptor_mapping; // autofix
}

pub fn freePipeline(
    pipeline: *Pipeline,
) void {
    _ = pipeline; // autofix
}

pub fn getPipelineMachineCode(
    pipeline: *Pipeline,
    allocator: std.mem.Allocator,
) []const u8 {
    _ = pipeline; // autofix
    _ = allocator; // autofix
}

pub fn setPipelineMachineCodeEntries(
    entries: []const PipelineMachineCodeEntry,
    data: []const u8,
) void {
    _ = entries; // autofix
    _ = data; // autofix
}

pub fn getPipelineMachineCodeEntries(
    allocator: std.mem.Allocator,
    entries: []PipelineMachineCodeEntry,
    data: []u8,
) void {
    _ = allocator; // autofix
    _ = entries; // autofix
    _ = data; // autofix
}

pub fn textureMemoryDescription(
    description: TextureDescription,
) TextureMemoryDescription {
    _ = description; // autofix

}

pub fn createTexture(
    description: TextureDescription,
    memory: []const u8,
) *Texture {
    _ = description; // autofix
    _ = memory; // autofix

}

pub fn readDescriptorTexture(
    texture: *Texture,
) TextureDescriptor {
    _ = texture; // autofix

}

pub fn readDescriptorTextureIntoHeap(
    texture: *Texture,
    heap: *DescriptorHeap,
    offset: usize,
) usize {
    _ = texture; // autofix
    _ = heap; // autofix
    _ = offset; // autofix

}

pub fn createDescriptorHeap(
    size: usize,
) !*DescriptorHeap {
    _ = size; // autofix
}

pub fn setStateDescriptorHeap(
    command_buffer: *CommandBuffer,
    heap: *DescriptorHeap,
) void {
    _ = command_buffer; // autofix
    _ = heap; // autofix
}

pub fn setStatePipeline(
    command_buffer: *CommandBuffer,
    pipeline: *Pipeline,
) void {
    _ = command_buffer; // autofix
    _ = pipeline; // autofix
}

pub fn setStateDepthStencil(
    command_buffer: *CommandBuffer,
    state: DepthStencilState,
) void {
    _ = command_buffer; // autofix
    _ = state; // autofix
}

pub fn setStateBlend(
    command_buffer: *CommandBuffer,
    state: BlendState,
) void {
    _ = command_buffer; // autofix
    _ = state; // autofix
}

pub fn setStateViewport(
    command_buffer: *CommandBuffer,
    viewport: [4]f32,
) void {
    _ = command_buffer; // autofix
    _ = viewport; // autofix
}

pub fn setStateScissor(
    command_buffer: *CommandBuffer,
    scissor: [4]u32,
) void {
    _ = command_buffer; // autofix
    _ = scissor; // autofix
}

pub fn barrier(
    command_buffer: *CommandBuffer,
    before: ExecutionStage,
    after: ExecutionStage,
    hazards: HazardFlags,
) void {
    _ = command_buffer; // autofix
    _ = before; // autofix
    _ = after; // autofix
    _ = hazards; // autofix
}

pub fn signalAfter(
    command_buffer: *CommandBuffer,
) void {
    _ = command_buffer; // autofix
}

pub fn signalBefore(
    command_buffer: *CommandBuffer,
) void {
    _ = command_buffer; // autofix
}

pub fn rasterPassBegin(
    command_buffer: *CommandBuffer,
    description: RasterPassDescription,
) void {
    _ = description; // autofix
    const command_buffer_data: *CommandBufferData = @ptrCast(@alignCast(command_buffer));
    const timestamp = gpu.placeCommandTimestampQuery(command_buffer);

    command_buffer_data.command_timestamps.append(
        context.arena,
        timestamp,
    ) catch @panic("oom");
}

pub fn rasterPassEnd(
    command_buffer: *CommandBuffer,
) void {
    const command_buffer_data: *CommandBufferData = @ptrCast(@alignCast(command_buffer));
    const timestamp = gpu.placeCommandTimestampQuery(command_buffer);

    command_buffer_data.command_timestamps.append(
        context.arena,
        timestamp,
    ) catch @panic("oom");
}

pub fn dispatchCompute(
    command_buffer: *CommandBuffer,
    commands: []const ComputeCommand,
) void {
    _ = commands; // autofix
    const command_buffer_data: *CommandBufferData = @ptrCast(@alignCast(command_buffer));
    const timestamp = gpu.placeCommandTimestampQuery(command_buffer);

    command_buffer_data.command_timestamps.append(
        context.arena,
        timestamp,
    ) catch @panic("oom");
}

pub fn dispatchRasterDraw(
    command_buffer: *CommandBuffer,
    commands: []const RasterDrawCommand,
) void {
    _ = commands; // autofix
    const command_buffer_data: *CommandBufferData = @ptrCast(@alignCast(command_buffer));
    const timestamp = gpu.placeCommandTimestampQuery(command_buffer);

    command_buffer_data.command_timestamps.append(
        context.arena,
        timestamp,
    ) catch @panic("oom");
}

pub fn dispatchRasterDrawMeshes(
    command_buffer: *CommandBuffer,
    commands: []const RasterDrawMeshesCommand,
) void {
    _ = command_buffer; // autofix
    _ = commands; // autofix
}

pub fn dispatchTraceRays(
    command_buffer: *CommandBuffer,
) void {
    _ = command_buffer; // autofix
}

pub fn buildAccelerationStructures(
    command_buffer: *CommandBuffer,
    description: AccelerationStructureBuildDescription,
) void {
    _ = command_buffer; // autofix
    _ = description; // autofix
}

pub fn createQueue(
    device: *Device,
    capabilities: QueueCapabilities,
) *Queue {
    _ = device; // autofix
    _ = capabilities; // autofix
}

pub fn destroyQueue() void {}

pub fn queueStartCommandRecording(
    queue: *Queue,
    return_value: *CommandBuffer,
) void {
    _ = return_value; // autofix
    _ = queue; // autofix
    const cmd_buffer = std.heap.smp_allocator.create(CommandBufferData) catch @panic("oom");
    cmd_buffer.* = .{
        .commands = .empty,
    };

    return @ptrCast(cmd_buffer);
}

pub fn queueEndCommandRecording(
    command_buffer: *CommandBuffer,
) void {
    _ = command_buffer; // autofix

}

pub fn queueSubmit(
    queue: *Queue,
    command_buffers: []*CommandBuffer,
) void {
    _ = queue; // autofix
    _ = command_buffers; // autofix

}

test {
    _ = std.testing.refAllDecls(@This());
}

const Device = gpu.Device;
const Texture = gpu.Texture;
const Pipeline = gpu.Pipeline;
const Queue = gpu.Queue;
const CommandBuffer = gpu.CommandBuffer;
const Semaphore = gpu.Semaphore;
const DescriptorHeap = gpu.DescriptorHeap;
const DescriptorTextureHeap = gpu.DescriptorTextureHeap;
const BufferDescriptor = gpu.BufferDescriptor;
const TextureDescriptor = gpu.TextureDescriptor;
const Stencil = gpu.Stencil;
const DepthStencilState = gpu.DepthStencilState;
const BlendState = gpu.BlendState;
const DeviceSelectionOptions = gpu.DeviceSelectionOptions;
const DeviceSelectionError = gpu.DeviceSelectionError;
const TextureDescription = gpu.TextureDescription;
const TextureMemoryDescription = gpu.TextureMemoryDescription;
const PipelineOptimization = gpu.PipelineOptimization;
const RasterPipelineDescription = gpu.RasterPipelineDescription;
const ImageFormat = gpu.ImageFormat;
const ExecutionStage = gpu.ExecutionStage;
const HazardFlags = gpu.HazardFlags;
const ColorTarget = gpu.ColorTarget;
const RasterPassDescription = gpu.RasterPassDescription;
const DescriptorHeapMapping = gpu.DescriptorHeapMapping;
const QueueCapabilities = gpu.QueueCapabilities;
const AccelerationStructureBuildDescription = gpu.AccelerationStructureBuildDescription;
const RasterDrawCommand = gpu.RasterDrawCommand;
const RasterDrawMeshesCommand = gpu.RasterDrawMeshesCommand;
const ComputeCommand = gpu.ComputeCommand;
const PipelineMachineCodeEntry = gpu.PipelineMachineCodeEntry;
const mem = gpu.mem;
const std = @import("std");
const gpu = @import("../gpu.zig");
