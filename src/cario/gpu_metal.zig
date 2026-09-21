var context: struct {
    device: metal.MetalDevice = undefined,
    queue: metal.MetalCommandQueue = undefined,
    memory_heap: metal.Heap = undefined,
    gpa: std.mem.Allocator = undefined,
    allocations: std.MultiArrayList(AllocationData) = .empty,
} = .{};

pub const AllocationData = struct {
    buffer: metal.MetalBuffer,
};

pub fn selectDevice(
    options: DeviceSelectionOptions,
    arena: std.mem.Allocator,
    gpa: std.mem.Allocator,
) !void {
    _ = options; // autofix
    _ = arena; // autofix
    context.gpa = gpa;
    context.device = try .init();
    context.queue = try context.device.createCommandQueue();
    context.memory_heap = try context.device.createHeap();
}

pub fn freeDevice() !void {}

pub fn memAlloc(
    size: usize,
    alignment: std.mem.Alignment,
    memory_type: mem.Allocator.MemoryType,
) std.mem.Allocator.Error![*]u8 {
    _ = alignment; // autofix
    var buffer = context.device.createBufferWithOptions(@intCast(size), switch (memory_type) {
        .gpu => .private,
        .gpu_cpu_writable, .readback => .shared,
        else => unreachable,
    }) catch return std.mem.Allocator.Error.OutOfMemory;

    try context.allocations.append(context.gpa, .{
        .buffer = buffer,
    });
    return buffer.getContents().?.ptr;
}

pub fn memFree(memory: [*]u8) void {
    _ = memory; // autofix
}

pub fn memToAccessiblePointer(pointer: *anyopaque, access: mem.AccessDomain) *anyopaque {
    _ = pointer; // autofix
    _ = access; // autofix
    @panic("");
}

pub fn memCopy(
    command_buffer: *CommandBuffer,
    dest_gpu: []u8,
    src_gpu: []const u8,
) void {
    _ = command_buffer; // autofix
    _ = dest_gpu; // autofix
    _ = src_gpu; // autofix
    @panic("");
}

pub fn memCopyToTexture(
    command_buffer: *CommandBuffer,
    dest_slice: gpu.TextureSliceDescription,
    dest_gpu: []gpu.TextureByte,
    src_gpu: []const u8,
) void {
    _ = command_buffer; // autofix
    _ = dest_slice; // autofix
    _ = dest_gpu; // autofix
    _ = src_gpu; // autofix
    @panic("");
}

pub fn memSet(
    command_buffer: *CommandBuffer,
    dest_gpu: []u8,
    src_gpu: []const u8,
) void {
    _ = command_buffer; // autofix
    _ = dest_gpu; // autofix
    _ = src_gpu; // autofix
    @panic("");
}

pub fn createRasterVertexPipeline(
    vertex_ir: []const u8,
    fragment_ir: []const u8,
    description: RasterPipelineDescription,
) *Pipeline {
    _ = vertex_ir; // autofix
    _ = fragment_ir; // autofix
    _ = description; // autofix
    @panic("");
}

pub fn createRasterMeshPipeline(
    mesh_ir: []const u8,
    fragment_ir: []const u8,
) *Pipeline {
    _ = mesh_ir; // autofix
    _ = fragment_ir; // autofix

    @panic("");
}

pub fn createComputePipeline(
    compute_ir: []const u8,
) *Pipeline {
    _ = compute_ir; // autofix
    @panic("");
}

pub fn freePipeline(
    pipeline: *Pipeline,
) void {
    _ = pipeline; // autofix
}

pub fn textureMemoryDescription(
    description: gpu.TextureDescription,
) gpu.ResourceMemoryDescription {
    _ = description; // autofix
    return .{
        .size = 0,
        .alignment = .@"1",
        .memory_type = .gpu,
    };
}

pub fn formatTextureMemory(
    memory: []gpu.TextureByte,
    description: gpu.TextureDescription,
) void {
    _ = memory; // autofix
    _ = description; // autofix
}

pub fn unformatTextureMemory(
    texture: []const gpu.TextureByte,
) void {
    _ = texture; // autofix
    @panic("");
}

pub fn createTextureDescriptor(
    texture: []const gpu.TextureByte,
) gpu.TextureDescriptor {
    _ = texture; // autofix
    @panic("");
}

pub fn samplerHeapMemoryDescription(
    size: usize,
) gpu.ResourceMemoryDescription {
    _ = size; // autofix
    @panic("");
}

pub fn setStateDepthStencil(
    command_buffer: *CommandBuffer,
    state: gpu.DepthStencilState,
) void {
    _ = command_buffer; // autofix
    _ = state; // autofix
    @panic("");
}

pub fn setStateBlend(
    command_buffer: *CommandBuffer,
    state: gpu.BlendState,
) void {
    _ = command_buffer; // autofix
    _ = state; // autofix
    @panic("");
}

pub fn setStateCull(
    command_buffer: *CommandBuffer,
    cull: gpu.RasterPipelineDescription.Cull,
) void {
    _ = command_buffer; // autofix
    _ = cull; // autofix
    @panic("");
}

pub fn setStatePolygonMode(
    command_buffer: *CommandBuffer,
    mode: gpu.PolygonMode,
) void {
    _ = command_buffer; // autofix
    _ = mode; // autofix
    @panic("");
}

pub fn setStateViewport(
    command_buffer: *CommandBuffer,
    viewport: [4]f32,
) void {
    _ = command_buffer; // autofix
    _ = viewport; // autofix
    @panic("");
}

pub fn setStateScissor(
    command_buffer: *CommandBuffer,
    scissor: [4]u32,
) void {
    _ = command_buffer; // autofix
    _ = scissor; // autofix
    @panic("");
}

pub fn barrier(
    command_buffer: *CommandBuffer,
    before: gpu.ExecutionStage,
    after: gpu.ExecutionStage,
    hazards: gpu.HazardFlags,
) void {
    _ = command_buffer; // autofix
    _ = before; // autofix
    _ = after; // autofix
    _ = hazards; // autofix
    @panic("");
}

pub fn rasterPassBegin(
    command_buffer: *CommandBuffer,
    description: gpu.RasterPassDescription,
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

pub fn launchCompute(
    command_buffer: *CommandBuffer,
    pipeline: *Pipeline,
    root_data: []const *anyopaque,
    commands: []const gpu.ComputeCommand,
) void {
    _ = command_buffer; // autofix
    _ = pipeline; // autofix
    _ = root_data; // autofix
    _ = commands; // autofix
    @panic("");
}

pub fn launchRasterDraw(
    command_buffer: *CommandBuffer,
    pipeline: *Pipeline,
    root_data: []const *anyopaque,
    commands: []const gpu.RasterDrawCommand,
    options: gpu.DispatchRasterDrawOptions,
) void {
    _ = command_buffer; // autofix
    _ = pipeline; // autofix
    _ = root_data; // autofix
    _ = commands; // autofix
    _ = options; // autofix
    @panic("");
}

pub fn launchRasterDrawIndexed(
    command_buffer: *CommandBuffer,
    pipeline: *Pipeline,
    root_data: []const *anyopaque,
    commands: []const gpu.RasterDrawIndexedCommand,
    indices: []u8,
) void {
    _ = command_buffer; // autofix
    _ = pipeline; // autofix
    _ = root_data; // autofix
    _ = commands; // autofix
    _ = indices; // autofix
    @panic("");
}

const CommandBufferData = struct {
    handle: metal.MetalCommandBuffer,
};

pub fn queueStartCommandRecording(
    queue: gpu.Queue,
    initial_state: gpu.CommandBufferInitialState,
) *gpu.CommandBuffer {
    _ = queue; // autofix
    _ = initial_state; // autofix
    const handle = context.queue.createCommandBuffer() catch @panic("oom");

    const result = context.gpa.create(CommandBufferData) catch @panic("oom");

    result.* = .{
        .handle = handle,
    };

    return @ptrCast(result);
}

pub fn queueSubmit(
    queue: gpu.Queue,
    command_buffers: []const *CommandBuffer,
    semaphores: []const gpu.SemaphoreSignalDescription,
) void {
    _ = queue; // autofix
    _ = command_buffers; // autofix
    _ = semaphores; // autofix
    @panic("");
}

pub fn createSwapchain(
    window: *anyopaque,
) *gpu.Swapchain {
    _ = window; // autofix
    @panic("");
}

pub fn destroySwapchain(swapchain: *gpu.Swapchain) void {
    _ = swapchain; // autofix
    @panic("");
}

pub fn swapchainObtainTexture(
    swapchain: *gpu.Swapchain,
) []gpu.TextureByte {
    _ = swapchain; // autofix
    @panic("");
}

pub fn swapchainPresent(
    swapchain: *gpu.Swapchain,
    semaphore: gpu.SemaphoreSignalDescription,
) void {
    _ = swapchain; // autofix
    _ = semaphore; // autofix
}
pub fn placeCommandTimestampQuery(
    command_buffer: *CommandBuffer,
) *gpu.debug.TimestampQuery {
    _ = command_buffer; // autofix
    return undefined;
}

pub fn queryTimestampValue(
    query: *gpu.debug.TimestampQuery,
) ?u64 {
    _ = query;
    @panic("");
}

pub fn waitIdle() void {
    @panic("");
}

pub fn queueWaitIdle(queue: gpu.Queue) void {
    _ = queue; // autofix
    @panic("");
}

pub fn createSemaphore(initial_value: u64) *gpu.Semaphore {
    _ = initial_value; // autofix
    @panic("");
}

pub fn destroySemaphore(semaphore: *gpu.Semaphore) void {
    _ = semaphore; // autofix
    @panic("");
}

pub fn semaphoreWait(semaphore: *gpu.Semaphore, wait_value: u64) void {
    _ = semaphore; // autofix
    _ = wait_value; // autofix
    @panic("");
}

const RasterPipelineDescription = gpu.RasterPipelineDescription;
const DeviceSelectionOptions = gpu.DeviceSelectionOptions;
const Pipeline = gpu.Pipeline;
const CommandBuffer = gpu.CommandBuffer;
const mem = gpu.mem;
const gpu = @import("../gpu.zig");
const metal = @import("bindings/metal.zig");
const std = @import("std");
