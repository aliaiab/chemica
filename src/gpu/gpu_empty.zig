//! Empty or stub implementation of the gpu api, copy this to start implementing the api for a backend or layer
//! To implement a layer, remove all the panics and set all the return types to void (layers don't return anything)

var context: struct {} = .{};

pub fn memCopy(
    command_buffer: *CommandBuffer,
    comptime T: type,
    dest_gpu: []const T,
    src_gpu: []const T,
) void {
    _ = command_buffer; // autofix
    _ = dest_gpu; // autofix
    _ = src_gpu; // autofix
    @panic("");
}

pub fn selectDevice(
    options: DeviceSelectionOptions,
    arena: std.mem.Allocator,
) DeviceSelectionError!*Device {
    _ = arena; // autofix
    _ = options; // autofix
    @panic("");
}

pub fn freeDevice(device: Device) void {
    _ = device; // autofix
    @panic("");
}

pub fn getDefaultAllocator(
    device: *Device,
) mem.Allocator {
    _ = device; // autofix
    @panic("");
}

pub fn setDebugSrc(
    src: std.lang.SourceLocation,
    source_file: []const u8,
) void {
    _ = src; // autofix
    _ = source_file; // autofix
}

pub fn setStateDevice(
    device: *Device,
) void {
    _ = device; // autofix
    @panic("");
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
    @panic("");
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

    @panic("");
}

pub fn createComputePipeline(
    compute_ir: []const u8,
    descriptor_mapping: DescriptorHeapMapping,
) *Pipeline {
    _ = compute_ir; // autofix
    _ = descriptor_mapping; // autofix

    @panic("");
}

pub fn freePipeline(
    pipeline: *Pipeline,
) void {
    _ = pipeline; // autofix
    @panic("");
}

pub fn getPipelineMachineCode(
    pipeline: *Pipeline,
    allocator: std.mem.Allocator,
) []const u8 {
    _ = pipeline; // autofix
    _ = allocator; // autofix

    @panic("");
}

pub fn setPipelineMachineCodeEntries(
    entries: []const PipelineMachineCodeEntry,
    data: []const u8,
) void {
    _ = entries; // autofix
    _ = data; // autofix

    @panic("");
}

pub fn getPipelineMachineCodeEntries(
    allocator: std.mem.Allocator,
    entries: []PipelineMachineCodeEntry,
    data: []u8,
) void {
    _ = allocator; // autofix
    _ = entries; // autofix
    _ = data; // autofix

    @panic("");
}

pub fn textureMemoryDescription(
    description: TextureDescription,
) TextureMemoryDescription {
    _ = description; // autofix

    @panic("");
}

pub fn createTexture(
    description: TextureDescription,
    memory: []const u8,
) *Texture {
    _ = description; // autofix
    _ = memory; // autofix

    @panic("");
}

pub fn readDescriptorTexture(
    texture: *Texture,
) TextureDescriptor {
    _ = texture; // autofix

    @panic("");
}

pub fn readDescriptorTextureIntoHeap(
    texture: *Texture,
    heap: *DescriptorHeap,
    offset: usize,
) usize {
    _ = texture; // autofix
    _ = heap; // autofix
    _ = offset; // autofix

    @panic("");
}

pub fn createDescriptorHeap(
    size: usize,
) !*DescriptorHeap {
    _ = size; // autofix

    @panic("");
}

pub fn setStateDescriptorHeap(
    command_buffer: *CommandBuffer,
    heap: *DescriptorHeap,
) void {
    _ = command_buffer; // autofix
    _ = heap; // autofix

    @panic("");
}

pub fn setStatePipeline(
    command_buffer: *CommandBuffer,
    pipeline: *Pipeline,
) void {
    _ = command_buffer; // autofix
    _ = pipeline; // autofix

    @panic("");
}

pub fn setStateDepthStencil(
    command_buffer: *CommandBuffer,
    state: DepthStencilState,
) void {
    _ = command_buffer; // autofix
    _ = state; // autofix

    @panic("");
}

pub fn setStateBlend(
    command_buffer: *CommandBuffer,
    state: BlendState,
) void {
    _ = command_buffer; // autofix
    _ = state; // autofix

    @panic("");
}

pub fn setStateViewportScissor(
    viewport: [4]f32,
    scissor: [4]f32,
) void {
    _ = viewport; // autofix
    _ = scissor; // autofix

    @panic("");
}

pub fn setStatePushData(
    command_buffer: *CommandBuffer,
    comptime T: type,
    push_data: T,
) void {
    _ = command_buffer; // autofix
    _ = push_data; // autofix

    @panic("");
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

    @panic("");
}

pub fn signalAfter(
    command_buffer: *CommandBuffer,
) void {
    _ = command_buffer; // autofix

    @panic("");
}

pub fn signalBefore(
    command_buffer: *CommandBuffer,
) void {
    _ = command_buffer; // autofix

    @panic("");
}

pub fn rasterPassBegin(
    command_buffer: *CommandBuffer,
    description: RasterPassDescription,
) void {
    _ = command_buffer; // autofix
    _ = description; // autofix

    @panic("");
}

pub fn rasterPassEnd(
    command_buffer: *CommandBuffer,
) void {
    _ = command_buffer; // autofix

    @panic("");
}

pub fn dispatchCompute(
    command_buffer: *CommandBuffer,
    commands: []const ComputeCommand,
) void {
    _ = command_buffer; // autofix
    _ = commands; // autofix

    @panic("");
}

pub fn dispatchRasterDraw(
    command_buffer: *CommandBuffer,
    commands: []const RasterDrawCommand,
    comptime IndexType: type,
    indices: []IndexType,
) void {
    _ = command_buffer; // autofix
    _ = commands; // autofix
    _ = indices; // autofix

    @panic("");
}

pub fn dispatchRasterDrawMeshes(
    command_buffer: *CommandBuffer,
    commands: []const RasterDrawMeshesCommand,
) void {
    _ = command_buffer; // autofix
    _ = commands; // autofix
    @panic("");
}

pub fn dispatchTraceRays(
    command_buffer: *CommandBuffer,
) void {
    _ = command_buffer; // autofix
    @panic("");
}

pub fn buildAccelerationStructures(
    command_buffer: *CommandBuffer,
    description: AccelerationStructureBuildDescription,
) void {
    _ = command_buffer; // autofix
    _ = description; // autofix
    @panic("");
}

pub fn createQueue(
    device: *Device,
    capabilities: QueueCapabilities,
) *Queue {
    _ = device; // autofix
    _ = capabilities; // autofix
    @panic("");
}

pub fn destroyQueue() void {
    @panic("");
}

pub fn queueStartCommandRecording(
    queue: *Queue,
) *CommandBuffer {
    _ = queue; // autofix
    @panic("");
}

pub fn queueEndCommandRecording(
    command_buffer: *CommandBuffer,
) void {
    _ = command_buffer; // autofix
    @panic("");
}

pub fn queueSubmit(
    queue: *Queue,
    command_buffers: []*CommandBuffer,
) void {
    _ = queue; // autofix
    _ = command_buffers; // autofix
    @panic("");
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
