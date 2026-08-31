///Selects a physical device which can support the api
pub fn selectDevice(
    options: DeviceSelectionOptions,
    arena: std.mem.Allocator,
) DeviceSelectionError!*Device {
    return backendCall(@src(), .{
        options,
        arena,
    });
}

///Frees device and all the resources associated with it
pub fn freeDevice(device: Device) void {
    return backendCall(@src(), .{device});
}

///Allocate memory from the device
pub fn memAlloc(
    size: usize,
    alignment: std.mem.Alignment,
    memory_type: mem.Allocator.MemoryType,
) std.mem.Allocator.Error![]u8 {
    return backendCall(@src(), .{
        size,
        alignment,
        memory_type,
    });
}

///Free device memory
pub fn memFree(memory: []u8) void {
    return backendCall(@src(), .{memory});
}

///Copy device memory from src to dst
pub fn memCopy(
    command_buffer: *CommandBuffer,
    dest_gpu: []u8,
    src_gpu: []const u8,
) void {
    return backendCall(@src(), .{
        command_buffer,
        dest_gpu,
        src_gpu,
    });
}

///Set the memory to the contents of src_gpu
///dest_gpu.len must be an integer multiple of src_gpu.len
pub fn memSet(
    command_buffer: *CommandBuffer,
    dest_gpu: []u8,
    src_gpu: []const u8,
) void {
    return backendCall(@src(), .{
        command_buffer,
        dest_gpu,
        src_gpu,
    });
}

///Copy device memory from source memory to a destination texture
pub fn memCopyToTexture(
    command_buffer: *CommandBuffer,
    dest_texture: *Texture,
    dest_slice: TextureSliceDescription,
    dest_gpu: []u8,
    src_gpu: []const u8,
) void {
    return backendCall(@src(), .{
        command_buffer,
        dest_texture,
        dest_slice,
        dest_gpu,
        src_gpu,
    });
}

///Set each texel of a texture to the contents src_gpu
pub fn memClearTexture(
    command_buffer: *CommandBuffer,
    dest_texture: *Texture,
    dest_gpu: []u8,
    src_gpu: []const u8,
) void {
    _ = command_buffer; // autofix
    _ = dest_texture; // autofix
    _ = dest_gpu; // autofix
    _ = src_gpu; // autofix
}

///Sets the function level debug information
pub fn setFunctionDebugInfo(
    src: std.lang.SourceLocation,
    debug_info: debug.Info,
) void {
    return backendCall(@src(), .{
        src,
        debug_info,
    });
}

///Sets the current device to be used by subsequent procedure calls
pub fn setStateDevice(
    device: *Device,
) void {
    return backendCall(@src(), .{device});
}

///Create a raster pipeline that uses vertex and fragment stages
pub fn createRasterVertexPipeline(
    vertex_ir: []const u8,
    fragment_ir: []const u8,
    descriptor_mapping: DescriptorHeapMapping,
    description: RasterPipelineDescription,
) *Pipeline {
    return backendCall(@src(), .{
        vertex_ir,
        fragment_ir,
        descriptor_mapping,
        description,
    });
}

///Create a raster pipeline that uses mesh and fragment stages
pub fn createRasterMeshPipeline(
    mesh_ir: []const u8,
    fragment_ir: []const u8,
    descriptor_mapping: DescriptorHeapMapping,
    description: RasterPipelineDescription,
) *Pipeline {
    return backendCall(@src(), .{
        mesh_ir,
        fragment_ir,
        descriptor_mapping,
        description,
    });
}

///Create a compute pipeline
pub fn createComputePipeline(
    compute_ir: []const u8,
    descriptor_mapping: DescriptorHeapMapping,
) *Pipeline {
    return backendCall(@src(), .{
        compute_ir,
        descriptor_mapping,
    });
}

///Free the pipeline memory
pub fn freePipeline(
    pipeline: *Pipeline,
) void {
    return backendCall(@src(), .{pipeline});
}

///Return the gpu-specific machine code blob for a pipeline
pub fn getPipelineMachineCode(
    pipeline: *Pipeline,
    allocator: std.mem.Allocator,
) []const u8 {
    return backendCall(@src(), .{
        pipeline,
        allocator,
    });
}

pub fn setPipelineMachineCodeEntries(
    entries: []const PipelineMachineCodeEntry,
    data: []const u8,
) void {
    return backendCall(@src(), .{
        entries,
        data,
    });
}

pub fn getPipelineMachineCodeEntries(
    allocator: std.mem.Allocator,
    entries: []PipelineMachineCodeEntry,
    data: []u8,
) void {
    return backendCall(@src(), .{
        allocator,
        entries,
        data,
    });
}

pub fn textureMemoryDescription(
    description: TextureDescription,
) ResourceMemoryDescription {
    return backendCall(@src(), .{description});
}

pub fn createTexture(
    description: TextureDescription,
    memory: []const u8,
) *Texture {
    return backendCall(@src(), .{
        description,
        memory,
    });
}

pub fn destroyTexture(
    texture: *Texture,
) void {
    return backendCall(@src(), .{
        texture,
    });
}

pub fn readDescriptorTexture(
    texture: *Texture,
) TextureDescriptor {
    return backendCall(@src(), .{
        texture,
    });
}

///Copies the texture descriptor into the descriptor heap at offset
///Returns the offset end (offset + sizeof(descriptor))
pub fn readDescriptorTextureIntoHeap(
    texture: *Texture,
    descriptor_heap: *DescriptorHeap,
    offset: usize,
) usize {
    return backendCall(@src(), .{
        texture,
        descriptor_heap,
        offset,
    });
}

///Copies the texture slice descriptor into the descriptor heap at offset
///Returns the offset end (offset + sizeof(descriptor))
pub fn readTextureSliceDescriptorIntoHeap(
    texture: *Texture,
    slice: TextureSliceDescription,
    descriptor_heap: *DescriptorHeap,
    offset: usize,
) usize {
    return backendCall(@src(), .{
        texture,
        slice,
        descriptor_heap,
        offset,
    });
}

///Copies the memory descriptor into the descriptor heap at offset
///Returns the offset end (offset + sizeof(descriptor))
pub fn readSliceBytesDescriptorIntoHeap(
    memory: []const u8,
    descriptor_heap: *DescriptorHeap,
    offset: usize,
) usize {
    return backendCall(@src(), .{
        memory,
        descriptor_heap,
        offset,
    });
}

pub fn readSliceDescriptorIntoHeap(
    memory: anytype,
    descriptor_heap: *DescriptorHeap,
    offset: usize,
) usize {
    return readSliceBytesDescriptorIntoHeap(
        switch (@typeInfo(@TypeOf(memory))) {
            .pointer => |ptr_info| switch (ptr_info.size) {
                .slice => std.mem.sliceAsBytes(memory),
                .one, .many, .c => std.mem.asBytes(memory),
            },
            else => @compileError("Type unsupported!"),
        },
        descriptor_heap,
        offset,
    );
}

pub fn descriptorHeapMemoryDescription(
    size: usize,
) ResourceMemoryDescription {
    return backendCall(@src(), .{size});
}

pub fn createDescriptorHeap(
    memory: []u8,
) !*DescriptorHeap {
    return backendCall(@src(), .{memory});
}

///Sets the current descriptor heap to be used by subsequent commands
pub fn setStateDescriptorHeap(
    command_buffer: *CommandBuffer,
    descriptor_heap: *DescriptorHeap,
) void {
    return backendCall(@src(), .{
        command_buffer,
        descriptor_heap,
    });
}

///Sets the current sampler descriptor heap to be used by subsequent commands
pub fn setStateSamplerDescriptorHeap(
    command_buffer: *CommandBuffer,
    descriptor_heap: *DescriptorHeap,
) void {
    return backendCall(@src(), .{
        command_buffer,
        descriptor_heap,
    });
}

///Sets the pipeline to be used by subsequent commands
pub fn setStatePipeline(
    command_buffer: *CommandBuffer,
    pipeline: *Pipeline,
) void {
    return backendCall(@src(), .{
        command_buffer,
        pipeline,
    });
}

///Sets the rasterizer depth and stencil state
pub fn setStateDepthStencil(
    command_buffer: *CommandBuffer,
    state: DepthStencilState,
) void {
    return backendCall(@src(), .{
        command_buffer,
        state,
    });
}

///Sets the rasterizer blending state
pub fn setStateBlend(
    command_buffer: *CommandBuffer,
    state: BlendState,
) void {
    return backendCall(@src(), .{
        command_buffer,
        state,
    });
}

///Sets the culling for the current/following raster pass
pub fn setStateCull(
    command_buffer: *CommandBuffer,
    cull: RasterPipelineDescription.Cull,
) void {
    return backendCall(@src(), .{
        command_buffer,
        cull,
    });
}

///Sets the polygon mode for the current/following raster pass
pub fn setStatePolygonMode(
    command_buffer: *CommandBuffer,
    mode: PolygonMode,
) void {
    return backendCall(@src(), .{
        command_buffer,
        mode,
    });
}

///Sets the viewport transforms
pub fn setStateViewport(
    command_buffer: *CommandBuffer,
    viewport: [4]f32,
) void {
    return backendCall(@src(), .{
        command_buffer,
        viewport,
    });
}

///Set the scissor rectangles
pub fn setStateScissor(
    command_buffer: *CommandBuffer,
    scissor: [4]u32,
) void {
    return backendCall(@src(), .{
        command_buffer,
        scissor,
    });
}

///Sets the push data for the current pipeline
pub fn setStatePushData(
    command_buffer: *CommandBuffer,
    comptime T: type,
    push_data: T,
) void {
    return backendCall(@src(), .{
        command_buffer,
        T,
        push_data,
    });
}

///Place a synchronisation barrier
pub fn barrier(
    command_buffer: *CommandBuffer,
    before: ExecutionStage,
    after: ExecutionStage,
    hazards: HazardFlags,
) void {
    return backendCall(@src(), .{
        command_buffer,
        before,
        after,
        hazards,
    });
}

pub fn signalAfter(
    command_buffer: *CommandBuffer,
) void {
    return backendCall(@src(), .{command_buffer});
}

pub fn signalBefore(
    command_buffer: *CommandBuffer,
) void {
    return backendCall(@src(), .{command_buffer});
}

///Begin a raster pass
pub fn rasterPassBegin(
    command_buffer: *CommandBuffer,
    description: RasterPassDescription,
) void {
    return backendCall(@src(), .{
        command_buffer,
        description,
    });
}

///End a raster pass
pub fn rasterPassEnd(
    command_buffer: *CommandBuffer,
) void {
    return backendCall(@src(), .{command_buffer});
}

///Dispatch a set of compute commands
pub fn dispatchCompute(
    command_buffer: *CommandBuffer,
    commands: []const ComputeCommand,
) void {
    return backendCall(@src(), .{
        command_buffer,
        commands,
    });
}

pub const DispatchRasterDrawOptions = struct {
    command_stride: usize,
    command_offset: usize,
};

///Dispatch a set of raster draw commands
pub fn dispatchRasterDraw(
    command_buffer: *CommandBuffer,
    commands: []const RasterDrawCommand,
    options: DispatchRasterDrawOptions,
) void {
    return backendCall(@src(), .{
        command_buffer,
        commands,
        options,
    });
}

///Dispatch a set of raster draw commands
pub fn dispatchRasterDrawIndexed(
    command_buffer: *CommandBuffer,
    commands: []const RasterDrawCommand,
    comptime IndexType: type,
    indices: []IndexType,
) void {
    return backendCall(@src(), .{
        command_buffer,
        commands,
        IndexType,
        indices,
    });
}

///Dispatch a set of raster mesh draw commands
pub fn dispatchRasterDrawMeshes(
    command_buffer: *CommandBuffer,
    commands: []const RasterDrawMeshesCommand,
) void {
    return backendCall(@src(), .{
        command_buffer,
        commands,
    });
}

///Dispatch a set of trace rays commands
pub fn dispatchTraceRays(
    command_buffer: *CommandBuffer,
) void {
    return backendCall(@src(), .{command_buffer});
}

///Build a ray tracing acceleration structure
pub fn buildAccelerationStructures(
    command_buffer: *CommandBuffer,
    description: AccelerationStructureBuildDescription,
) void {
    return backendCall(@src(), .{
        command_buffer,
        description,
    });
}

///Create a queue with the specified capabilities
pub fn createQueue(
    device: *Device,
    capabilities: QueueCapabilities,
) *Queue {
    return backendCall(@src(), .{
        device,
        capabilities,
    });
}

pub fn destroyQueue(
    queue: *Queue,
) void {
    return backendCall(@src(), .{queue});
}

///Returns a fresh, transient command buffer from the queue, ready to have command encoded into it
pub fn queueStartCommandRecording(
    queue: *Queue,
) *CommandBuffer {
    return backendCall(@src(), .{queue});
}

///End command encoding for command_buffer
pub fn queueEndCommandRecording(
    command_buffer: *CommandBuffer,
) void {
    return backendCall(@src(), .{command_buffer});
}

///Submit command buffers to a queue for execution
pub fn queueSubmit(
    queue: *Queue,
    command_buffers: []const *CommandBuffer,
    ///Semaphores to signal when each respective command buffer completes
    signal_semaphores: []const *Semaphore,
) void {
    return backendCall(@src(), .{
        queue,
        command_buffers,
        signal_semaphores,
    });
}

///Creates a swapchain from a platform-specific window handle
pub fn createSwapchain(
    window_handle: *anyopaque,
) *Swapchain {
    return backendCall(@src(), .{window_handle});
}

///Destroy a swapchain and its associated memory
pub fn destroySwapchain(swapchain: *Swapchain) void {
    return backendCall(@src(), .{swapchain});
}

///Obtain a texture from the swapchain which can be presented
pub fn swapchainObtainTexture(
    swapchain: *Swapchain,
) *Texture {
    return backendCall(@src(), .{swapchain});
}

///Encodes a swapchain presentation command into command_buffer
pub fn swapchainPresent(
    command_buffer: *CommandBuffer,
    swapchain: *Swapchain,
) void {
    return backendCall(@src(), .{
        command_buffer,
        swapchain,
    });
}

pub const Device = opaque {};
pub const Texture = opaque {};
pub const Pipeline = opaque {};
pub const Queue = opaque {};
pub const CommandBuffer = opaque {};
pub const Semaphore = opaque {};
pub const DescriptorHeap = opaque {};
pub const DescriptorTextureHeap = opaque {};
pub const Swapchain = opaque {};

pub const BufferDescriptor = packed struct(u64) {
    value: u64,
};

pub const TextureDescriptor = packed struct(u256) {
    value: u256,
};

pub const PolygonMode = enum(u2) {
    fill,
    line,
    point,
};

pub const Stencil = packed struct {
    testing: CompareOp = .always,
    fail_op: CompareOp = .keep,
    pass_op: CompareOp = .keep,
    depth_fail_op: CompareOp = .keep,
    reference: u8 = 0,
};

///A rasterizer depth stencil state packet
pub const DepthStencilState = packed struct(u166) {
    depth_mode: DepthFlags = .{},
    depth_test: CompareOp = .always,
    depth_bias: f32 = 0,
    depth_bias_slope_factor: f32 = 0,
    depth_bias_clamp: f32 = 0,
    stencil_read_mask: u8 = 0xff,
    stencil_write_mask: u8 = 0xff,
    stencil_front: Stencil = .{},
    stencil_back: Stencil = .{},

    pub const DepthFlags = packed struct(u2) {
        read: bool = false,
        write: bool = false,
    };
};

///A rasterizer blend state packet
pub const BlendState = packed struct(u26) {
    color_op: Blend = .add,
    src_color: Factor = .one,
    dst_color: Factor = .zero,
    alpha_op: Blend = .add,
    src_alpha: Factor = .one,
    dst_alpha: Factor = .zero,
    colour_write_mask: u8 = 0xf,

    pub const Blend = enum(u3) {
        add,
        subtract,
        rev_subtract,
        min,
        max,
    };

    pub const Factor = enum(u3) {
        zero,
        one,
        src_color,
        dst_color,
        src_alpha,
        one_minus_src_alpha,
    };
};

pub const CompareOp = enum(u4) {
    never,
    less,
    equal,
    greater,
    not_equal,
    greater_equal,
    always,
    keep,
    replace,
};

///Describes a hint to the implementation on how much the pipeline should be optimized
pub const PipelineOptimization = enum {
    fast,
    debug,
};

pub const RasterPipelineDescription = struct {
    topology: Topology = .triangle_list,
    cull: Cull = .none,
    alpha_to_coverage: bool = false,
    support_dual_source_blending: bool = false,
    sample_count: u32 = 1,
    depth_format: ImageFormat = .none,
    stencil_format: ImageFormat = .none,
    color_targets: []const ColorTarget = &.{},
    blend_state: ?*BlendState = null,
    optimize_mode: PipelineOptimization = .fast,

    pub const Topology = enum(u2) {
        triangle_list,
        triangle_strip,
        triangle_fan,
        line_list,
    };

    pub const Cull = enum {
        none,
        clockwise,
        anticlockwise,
        all,
    };
};

pub const ImageFormat = enum(u3) {
    none,
    rgba8_unorm32,
    rgb8_unorm24,
    r32_u32,
    r16_u16,
    depth_f32,
    depth_stencil_u24_u8,
};

pub const ExecutionStage = enum {
    transfer,
    compute,
    raster_color_out,
    raster_fragment,
    raster_vertex,
};

pub const HazardFlags = packed struct {
    draw_commands: bool = false,
    descriptors: bool = false,
    depth_stencil: bool = false,
    images: bool = false,
    shader_storage_memory: bool = false,
};

pub const ColorTarget = struct {
    format: ImageFormat = .none,
    write_mask: u32 = 0,
};

pub const RasterPassDescription = struct {
    color_attachments: []const ColorAttachment,
    depth_attachment: ?DepthAttachment = null,
    stencil_attachment: ?StencilAttachment = null,

    pub const ColorAttachment = struct {
        texture: *Texture,
        clear: [4]f32,
        load_op: MemoryLoadOp = .load,
        store_op: MemoryStoreOp = .store,
    };

    pub const DepthAttachment = struct {
        texture: *Texture,
        clear: f32,
        load_op: MemoryLoadOp = .load,
        store_op: MemoryStoreOp = .discard,
    };

    pub const StencilAttachment = struct {
        texture: *Texture,
        clear: u8,
        load_op: MemoryLoadOp = .load,
        store_op: MemoryStoreOp = .discard,
    };

    pub const MemoryLoadOp = enum {
        load,
    };

    pub const MemoryStoreOp = enum {
        store,
        ///The stores to the respective attachment are ignored
        discard,
    };
};

///Defines the mapping between binding locations in the pipeline interface and locations in a descriptor heap
pub const DescriptorHeapMapping = packed struct {
    binding_first: u32,
    binding_count: u32,
    heap_offset: u32,
    heap_array_stride: u32,
    sampler_binding_first: u32,
    sampler_binding_count: u32,
    sampler_heap_offset: u32,
    sampler_heap_array_stride: u32,
};

pub const TextureDescription = struct {
    type: Type = .@"2d",
    dimensions: [3]u32,
    mip_count: u32 = 1,
    layer_count: u32 = 1,
    sample_count: u32 = 1,
    format: ImageFormat = .rgba8_unorm32,

    pub const Usage = enum {
        sampled,
        storage,
        colour_attachment,
        depth_stencil_attachment,
        depth_attachment,
    };

    pub const Type = enum(u3) {
        @"1d",
        @"2d",
        @"3d",
        array_2d,
        array_cube,
        cube,
    };
};

///Represents a logical slice of a texture's memory
pub const TextureSliceDescription = struct {
    offset: [3]u32 = @splat(0),
    dimensions: [3]u32,
    mip_start: u32 = 0,
    layer_start: u32 = 0,
    ///The mode which determines how the texture can be used by a pipeline
    mode: Mode = .sampled,

    pub const Mode = enum {
        sampled,
        read,
        read_write,
    };
};

pub const ResourceMemoryDescription = struct {
    size: usize,
    alignment: std.mem.Alignment,
    memory_type: mem.Allocator.MemoryType,
};

pub const RasterDrawCommand = extern struct {
    count: u32,
    instance_count: u32,
    first: u32,
    first_instance: u32,
};

pub const RasterDrawIndexedCommand = extern struct {
    index_count: u32,
    instance_count: u32,
    index_start: u32,
    vertex_offset: u32,
    first_instance: u32,
};

pub const RasterDrawMeshesCommand = extern struct {
    index_count: u32,
    instance_count: u32,
    index_start: u32,
    vertex_offset: u32,
    first_instance: u32,
};

pub const ComputeCommand = extern struct {
    workgroup_count_x: u32,
    workgroup_count_y: u32 = 1,
    workgroup_count_z: u32 = 1,
};

pub const QueueCapabilities = packed struct {
    transfer: bool = true,
    compute: bool = true,
    raster: bool = true,
};

pub const AccelerationStructureBuildDescription = struct {};

pub const PipelineMachineCodeEntry = extern struct {
    ///Hash of the input contents to createPipeline*
    hash: u64,
    offset: u64,
    size: u64,
};

pub const DeviceSelectionOptions = packed struct {
    ///Prefer a discrete gpu device
    prefer_discrete: bool = true,
};

pub const DeviceSelectionError = error{
    FailedToFindSuitableDevice,
};

pub const mem = struct {
    pub const GpuPointerData = packed struct(u64) {
        ///The actual device address
        address: u48,
        ///Implementation specific allocation index
        allocation_index: u16,
    };

    ///Converts a gpu pointer to a host pointer
    pub fn toHostPointer(pointer: anytype) @TypeOf(pointer) {
        var gpu_ptr: GpuPointerData = @bitCast(@intFromPtr(pointer));
        gpu_ptr.allocation_index = 0;
        return @ptrFromInt(@backingInt(gpu_ptr));
    }

    ///Converts a gpu slice to a host writable slice
    pub fn toHostSlice(slice: anytype) @TypeOf(slice) {
        return toHostPointer(slice.ptr)[0..slice.len];
    }

    pub inline fn copySingle(
        command_buffer: *CommandBuffer,
        comptime T: type,
        dest_gpu: *T,
        src_gpu: *const T,
    ) void {
        copy(
            command_buffer,
            T,
            @ptrCast(dest_gpu),
            @ptrCast(src_gpu),
        );
    }

    pub inline fn copy(
        command_buffer: *CommandBuffer,
        comptime T: type,
        dest_gpu: []T,
        src_gpu: []const T,
    ) void {
        memCopy(
            command_buffer,
            std.mem.sliceAsBytes(dest_gpu),
            std.mem.sliceAsBytes(src_gpu),
        );
    }

    pub inline fn set(
        command_buffer: *CommandBuffer,
        comptime T: type,
        dest_gpu: []T,
        value: T,
    ) void {
        memSet(
            command_buffer,
            std.mem.sliceAsBytes(dest_gpu),
            std.mem.asBytes(&value),
        );
    }

    pub inline fn copyToTexture(
        command_buffer: *CommandBuffer,
        comptime T: type,
        dest_texture: *Texture,
        dest_slice: TextureSliceDescription,
        dest_gpu: []T,
        src_gpu: []const T,
    ) void {
        _ = dest_texture; // autofix
        _ = dest_slice; // autofix
        _ = command_buffer; // autofix
        _ = dest_gpu; // autofix
        _ = src_gpu; // autofix
    }

    ///Represents a gpu allocator
    pub const Allocator = struct {
        ptr: *anyopaque,
        vtable: *const VTable,
        free_groups: std.ArrayList(FreeGroup) = .empty,

        pub const FreeGroup = struct {
            commands: std.ArrayList(FreeCommand) = .empty,
            texture_commands: std.ArrayList(FreeTextureCommand) = .empty,
            semaphores: []const *Semaphore = &.{},
        };

        pub const FreeCommand = struct {
            memory: []u8,
        };

        pub const FreeTextureCommand = struct {
            texture: *Texture,
        };

        pub fn create(
            allocator: Allocator,
            comptime T: type,
            memory_type: MemoryType,
        ) !*T {
            return &(try allocator.alloc(T, 1, memory_type))[0];
        }

        ///Creates a texture handle and allocates memory for it
        pub fn allocTexture(
            allocator: Allocator,
            texture_description: TextureDescription,
        ) !struct { *Texture, []u8 } {
            const texture_mem_description = gpu.textureMemoryDescription(texture_description);

            const memory = try allocator.alloc(
                u8,
                texture_mem_description.size,
                texture_mem_description.memory_type,
            );

            const texture = gpu.createTexture(
                texture_description,
                memory,
            );

            return .{ texture, memory };
        }

        pub fn alloc(
            allocator: Allocator,
            comptime T: type,
            size: usize,
            memory_type: MemoryType,
        ) ![]T {
            return @as([*]T, @ptrCast(@alignCast(allocator.vtable.alloc(
                allocator.ptr,
                size * @sizeOf(T),
                .of(T),
                memory_type,
                @returnAddress(),
            ))))[0..size];
        }

        ///Defer a free memory command
        pub fn free(
            allocator: Allocator,
            memory: anytype,
        ) void {
            allocator.vtable.free(
                allocator.ptr,
                std.mem.asBytes(memory),
                .@"1",
                .gpu,
                @returnAddress(),
            );
        }

        ///Defer a free texture command
        pub fn freeTexture(
            allocator: Allocator,
            texture: *Texture,
            memory: []u8,
        ) void {
            _ = texture; // autofix
            _ = memory; // autofix
            _ = allocator; // autofix
        }

        pub fn beginFreeGroup(
            allocator: Allocator,
            semaphores: []*const Semaphore,
        ) void {
            _ = semaphores; // autofix
            _ = allocator; // autofix
        }

        pub fn endFreeGroup(
            allocator: Allocator,
        ) void {
            _ = allocator; // autofix
        }

        ///Attempts to execute free commands which are able to be executed
        pub fn flushFrees(
            allocator: Allocator,
        ) void {
            _ = allocator; // autofix
        }

        pub const MemoryType = enum {
            gpu,
            cpu,
            readback,
        };

        pub const VTable = struct {
            alloc: *const fn (
                *anyopaque,
                len: usize,
                alignment: std.mem.Alignment,
                memory_type: MemoryType,
                ret_addr: usize,
            ) ?[*]u8,
            resize: *const fn (
                *anyopaque,
                memory: []u8,
                alignment: std.mem.Alignment,
                memory_type: MemoryType,
                new_len: usize,
                ret_addr: usize,
            ) bool,
            remap: *const fn (
                *anyopaque,
                memory: []u8,
                alignment: std.mem.Alignment,
                memory_type: MemoryType,
                new_len: usize,
                ret_addr: usize,
            ) ?[*]u8,
            free: *const fn (
                *anyopaque,
                memory: []u8,
                alignment: std.mem.Alignment,
                memory_type: MemoryType,
                ret_addr: usize,
            ) void,
        };
    };

    ///A gpu array list
    pub fn ArrayList(comptime T: type) type {
        return struct {
            data: []T,
            capacity: usize,

            pub fn append(
                self: *Self,
                ///Command buffer to encode copy commands into
                command_buffer: *CommandBuffer,
                ///Descriptor heap to write new descriptors into
                descriptor_heap: *DescriptorHeap,
                ///Location of the array list descriptor
                descriptor_heap_offset: usize,
                element: T,
            ) !void {
                _ = self; // autofix
                _ = command_buffer; // autofix
                _ = descriptor_heap; // autofix
                _ = descriptor_heap_offset; // autofix
                _ = element; // autofix
            }

            const Self = @This();
        };
    }
};

///The gpu memory heap module
///Defines some backend-independent allocators
pub const heap = struct {
    ///Allocator interface that wraps gpu.memAlloc and gpu.memFree
    pub const page_allocator: mem.Allocator = .{
        .ptr = undefined,
        .vtable = &.{
            .alloc = &PageAllocator.alloc,
            .resize = undefined,
            .remap = undefined,
            .free = &PageAllocator.free,
        },
    };

    pub const PageAllocator = struct {
        pub fn alloc(
            _: *anyopaque,
            len: usize,
            alignment: std.mem.Alignment,
            memory_type: mem.Allocator.MemoryType,
            _: usize,
        ) ?[*]u8 {
            return (memAlloc(len, alignment, memory_type) catch return null).ptr;
        }

        pub fn resize(
            _: *anyopaque,
            memory: []u8,
            alignment: std.mem.Alignment,
            memory_type: mem.Allocator.MemoryType,
            new_len: usize,
            _: usize,
        ) bool {
            _ = memory; // autofix
            _ = alignment; // autofix
            _ = memory_type; // autofix
            _ = new_len; // autofix
        }

        pub fn remap(
            _: *anyopaque,
            memory: []u8,
            alignment: std.mem.Alignment,
            memory_type: mem.Allocator.MemoryType,
            new_len: usize,
            _: usize,
        ) ?[*]u8 {
            _ = memory; // autofix
            _ = alignment; // autofix
            _ = memory_type; // autofix
            _ = new_len; // autofix
        }

        pub fn free(
            _: *anyopaque,
            memory: []u8,
            _: std.mem.Alignment,
            _: mem.Allocator.MemoryType,
            _: usize,
        ) void {
            return memFree(memory);
        }
    };

    ///A gpu memory arena
    pub const ArenaAllocator = struct {};

    ///A gpu debug allocator
    pub const DebugAllocator = struct {};

    ///A gpu smp allocator
    pub const SmpAllocator = struct {};
};

pub const pipelines = struct {
    ///Performs hot reloading functionality
    pub fn Compiler(
        options: struct {
            enable_hot_reload: bool = @import("builtin").mode == .debug,
            ///If true, ir modules will be loaded through @embedFile (only available through moduleFromFileComptime)
            enable_embed_file: bool = @import("builtin").mode != .debug,
        },
    ) type {
        return struct {
            ///Directory from which shaders are loaded
            directory: []const u8,
            io: std.Io,

            pub const Module = union(enum) {
                ir: []const u8,
                file_path: []const u8,
            };

            pub fn moduleFromFile(
                file_path: []const u8,
            ) !Module {
                _ = file_path; // autofix
            }

            pub fn moduleFromFileComptime(
                comptime file_path: []const u8,
            ) !Module {
                if (options.enable_embed_file) {
                    return .{ .ir = @embedFile(file_path) };
                }

                return moduleFromFile(file_path);
            }

            pub fn createRasterVertexPipeline(
                compiler: *Compiler,
                vertex_module: Module,
                fragment_module: Module,
                out_pipeline: **Pipeline,
            ) void {
                _ = compiler; // autofix
                _ = out_pipeline; // autofix
                _ = vertex_module; // autofix
                _ = fragment_module; // autofix
            }
        };
    }
};

///The texturing module (contains mipmapping and compression code)
pub const texturing = struct {
    ///Generates a mip chain for a texture
    pub fn generateMipChain(
        command_buffer: *CommandBuffer,
        texture: *Texture,
    ) void {
        _ = texture; // autofix
        _ = command_buffer; // autofix
    }
};

///Debugging and debug info module
pub const debug = struct {
    ///Represents debug info for a file
    pub const Info = struct {
        source_bytes: [:0]const u8,
        descriptor_names: std.AutoArrayHashMapUnmanaged(*DescriptorHeap, DescriptorNames) = .empty,
        raster_pass_names: std.AutoArrayHashMapUnmanaged(std.lang.SourceLocation, [:0]const u8) = .empty,
        pipeline_names: std.AutoArrayHashMapUnmanaged(*Pipeline, [:0]const u8) = .empty,

        ///Parses the source file defined by source_bytes into a debug info structure
        pub fn fromSource(
            comptime source_bytes: [:0]const u8,
        ) Info {
            if (@import("builtin").optimize != .debug) {
                return .{ .source_bytes = &.{} };
            }

            return .{ .source_bytes = source_bytes };
        }

        pub const DescriptorNames = struct {
            ///Names indexed by descriptor location
            names: [][:0]const u8,
        };
    };
};

inline fn backendCall(
    comptime src: std.lang.SourceLocation,
    args: anytype,
) (@typeInfo(@TypeOf(@field(backend, src.fn_name))).@"fn".return_type orelse void) {
    _ = layerCall(layer, src.fn_name, args);

    return @call(
        .always_inline,
        @field(backend, src.fn_name),
        args,
    );
}

inline fn layerCall(comptime call_layer: type, comptime function_name: []const u8, args: anytype) void {
    if (call_layer == layer_none) {
        return;
    }

    comptime var actual_layer = call_layer;

    comptime var i: usize = 0;

    inline while (i == 0 or @hasDecl(call_layer, "next_layer")) {
        const maybe_function = if (@hasDecl(call_layer, function_name)) @field(call_layer, function_name) else null;

        if (maybe_function) |function| {
            _ = @call(.always_inline, function, args);
        }

        if (@hasDecl(call_layer, "next_layer")) {
            actual_layer = call_layer.next_layer;
        }

        i += 1;
    }
}

///A function layer between the api calls and the backend calls
const layer: type = layer_none;
const layer_none = struct {};

const backend = switch (@import("builtin").os.tag) {
    .macos => @compileError("metal api not yet supported!"),
    .linux, .windows => @import("gpu/gpu_opengl.zig"),
    else => @compileError("Os not supported!"),
};

pub const Simulation = switch (@import("builtin").os.tag) {
    .macos => @import("gpu/metal.zig").Simulation,
    else => if (!use_vulkan) @import("renderer.zig").Simulation else @import("gpu/vulkan.zig").Simulation,
};

pub const Context = switch (@import("builtin").os.tag) {
    .macos => @import("gpu/metal.zig").Context,
    else => if (!use_vulkan) @import("renderer.zig").Context else @import("gpu/vulkan.zig").Context,
};

test {
    _ = std.testing.refAllDecls(@This());
}

pub const use_vulkan = false;

const gpu = @This();
const std = @import("std");
