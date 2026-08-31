//! An opengl 4.6 implementation

var context: struct {
    proc_table: ?gl.ProcTable = null,
    pipeline_descriptor_mappings: std.ArrayList(DescriptorHeapMapping) = .empty,
    arena: std.mem.Allocator = undefined,
    texture_handles: std.ArrayList(u32) = .empty,
    buffer_handles: std.ArrayList(u32) = .empty,
    next_buffer_handle: u32 = 0,
    next_texture_handle: u32 = 0,
    buffers: std.ArrayList(BufferView) = .empty,
    unmapped_buffers: std.AutoArrayHashMapUnmanaged(u32, void) = .empty,
    ///Since we don't support the fixed function vertex input assembly stage, we just use a global empty vertex array
    ///We need to do this because even if your shader does not have fixed function vertex inputs, a vertex array must be bound
    global_vertex_array: u32 = 0,
    framebuffers: std.AutoArrayHashMapUnmanaged(*gpu.Texture, u32) = .empty,
    pending_command_buffer_count: usize = 0,
} = .{};

const CommandBufferData = struct {
    ///The set descriptor heap
    descriptor_heap: ?*DescriptorHeap = null,
    sampler_descriptor_heap: ?*DescriptorHeap = null,
    ///The set pipeline
    pipeline: ?*Pipeline = null,
    depth_stencil_state: ?DepthStencilState = null,
    blend_state: ?BlendState = null,
    viewport: ?[4]f32 = null,
    scissor: ?[4]u32 = null,
    ///True if the command buffer is the first in a series of queueStartCommandRecording calls
    ///if true then commands don't have to be buffered, instead we can just lower to gl* commands immediately and flush on queueSubmit
    is_primary: bool,
    commands: std.ArrayList(Command),

    pub const Command = union(enum) {
        set_state_descriptor_heap: struct { descriptor_heap: *DescriptorHeap },
        set_state_pipeline: struct { pipeline: *Pipeline },
        set_state_depth_stencil: struct { state: DepthStencilState },
        set_state_blend: struct { state: BlendState },
        set_state_viewport: struct { viewport: [4]f32 },
        set_state_scissor: struct { scissor: [4]u32 },
    };
};

const Descriptor = packed struct(u256) {
    api_handle: u32,
    tag: Tag,
    slice_offset: u64 = 0,
    slice_length: u64 = 0,
    format: gpu.ImageFormat,
    pad1: u61 = 0,

    pub const Tag = enum(u32) {
        buffer,
        image_sampled,
        image_read_write,
    };
};

pub const PipelineHandle = packed struct(u64) {
    program: u32,
    data_index: u30,
    topology: gpu.RasterPipelineDescription.Topology,
};

pub const TextureHandle = packed struct(u64) {
    ///The opengl texture handle
    api_handle: u32,
    format: gpu.ImageFormat,
    type: gpu.TextureDescription.Type,
    _: u26 = 0,

    ///Refers to the default backbuffer texture(s)
    pub const backbuffer_texture: TextureHandle = .{
        .api_handle = 0,
        .format = undefined,
        .type = .@"2d",
        ._ = 1,
    };
};

pub const GpuPointer = packed struct(u64) {
    address: u48,
    allocation_index: u16,
};

pub fn memAlloc(
    size: usize,
    alignment: std.mem.Alignment,
    memory_type: mem.Allocator.MemoryType,
) std.mem.Allocator.Error![]u8 {
    switch (memory_type) {
        .gpu => {

            //const underlying_size: u32 = @intCast(size + (alignment.toByteUnits() - 1));
            const underlying_size: u32 = @intCast(size);
            std.debug.assert(size != 0);

            if (context.next_buffer_handle >= context.buffer_handles.items.len) {
                try context.buffer_handles.appendNTimes(context.arena, 0, 20);
                const buffers = context.buffer_handles.items[context.next_buffer_handle..].ptr;
                gl.CreateBuffers(
                    @intCast(context.buffer_handles.items[context.next_buffer_handle..].len),
                    buffers,
                );
            }
            defer context.next_buffer_handle += 1;
            const buffer: u32 = context.buffer_handles.items[context.next_buffer_handle];

            gl.NamedBufferStorage(
                buffer,
                underlying_size,
                null,
                gl.DYNAMIC_STORAGE_BIT,
            );

            const allocation_index: u32 = @intCast(context.buffers.items.len);

            const ptr: [*]u8 = @ptrFromInt(@backingInt(GpuPointer{
                .address = 0,
                .allocation_index = @intCast(1 + allocation_index),
            }));

            //ptr = @ptrFromInt(std.mem.alignForward(usize, @intFromPtr(ptr), alignment.toByteUnits()))

            try context.buffers.append(context.arena, .{
                .api_handle = buffer,
                .offset = 0,
                .len = underlying_size,
            });

            return ptr[0..size];
        },
        .cpu => return (std.heap.page_allocator.rawAlloc(
            size,
            alignment,
            @returnAddress(),
        ) orelse return error.OutOfMemory)[0..size],
        .readback => @panic(""),
    }
}

pub fn memFree(
    memory: []u8,
) void {
    const ptr: GpuPointer = @bitCast(@intFromPtr(memory.ptr));

    if (ptr.allocation_index != 0) {
        const buffer = context.buffers.items[ptr.allocation_index - 1];

        gl.DeleteBuffers(1, @ptrCast(&buffer.api_handle));
        return;
    }

    std.heap.page_allocator.free(memory);
}

pub fn memCopy(
    command_buffer: *CommandBuffer,
    dest_gpu: []u8,
    src_gpu: []const u8,
) void {
    _ = command_buffer; // autofix
    const buffer_view = translateSliceToBufferView(dest_gpu);
    const src_buffer_view = translateSliceToBufferView(src_gpu);

    if (buffer_view.api_handle != 0) {
        if (src_buffer_view.api_handle != 0) {
            gl.CopyNamedBufferSubData(
                src_buffer_view.api_handle,
                buffer_view.api_handle,
                @intCast(src_buffer_view.offset),
                @intCast(buffer_view.offset),
                @intCast(src_gpu.len),
            );
        } else {
            gl.NamedBufferSubData(
                buffer_view.api_handle,
                @intCast(buffer_view.offset),
                @intCast(src_gpu.len),
                src_gpu.ptr,
            );
        }
    } else {
        //TODO: readback/cpu-cpu memcopy
        @panic("TODO: unimplemened");
    }
}

pub fn memSet(
    command_buffer: *CommandBuffer,
    dest_gpu: []u8,
    src_gpu: []const u8,
) void {
    _ = command_buffer; // autofix
    const buffer_view = translateSliceToBufferView(dest_gpu);

    const internal_format: u32 = switch (src_gpu.len) {
        1 => gl.R8,
        2 => gl.R16,
        4 => gl.R32UI,
        8 => gl.RG32UI,
        else => unreachable,
    };

    const format: u32 = switch (src_gpu.len) {
        1 => gl.RED_INTEGER,
        2 => gl.RED_INTEGER,
        4 => gl.RED_INTEGER,
        8 => gl.RG_INTEGER,
        else => unreachable,
    };

    const data_type: u32 = switch (src_gpu.len) {
        1 => gl.UNSIGNED_BYTE,
        2 => gl.UNSIGNED_SHORT,
        4 => gl.UNSIGNED_INT,
        8 => gl.UNSIGNED_INT,
        else => unreachable,
    };

    if (buffer_view.api_handle != 0) {
        gl.ClearNamedBufferSubData(
            buffer_view.api_handle,
            internal_format,
            @intCast(buffer_view.offset),
            @intCast(src_gpu.len),
            format,
            data_type,
            src_gpu.ptr,
        );
    } else {
        //TODO: glCopyBufferSubData
    }
}

pub fn memCopyToTexture(
    command_buffer: *CommandBuffer,
    dest_texture: *Texture,
    dest_slice: gpu.TextureSliceDescription,
    dest_gpu: []u8,
    src_gpu: []const u8,
) void {
    _ = command_buffer; // autofix
    _ = dest_gpu; // autofix

    const texture_handle: TextureHandle = @bitCast(@intFromPtr(dest_texture));

    const format: u32 = switch (texture_handle.format) {
        .rgba8_unorm32 => gl.RGBA,
        .rgb8_unorm24 => gl.RGB,
        .r16_u16 => gl.RED,
        .r32_u32 => gl.RED,
        else => unreachable,
    };

    const pixel_type: u32 = switch (texture_handle.format) {
        .rgba8_unorm32 => gl.UNSIGNED_BYTE,
        .rgb8_unorm24 => gl.UNSIGNED_BYTE,
        .r16_u16 => gl.UNSIGNED_SHORT,
        .r32_u32 => gl.UNSIGNED_INT,
        else => unreachable,
    };

    switch (texture_handle.type) {
        .@"1d" => {
            gl.TextureSubImage1D(
                texture_handle.api_handle,
                @intCast(dest_slice.layer_start),
                @intCast(dest_slice.offset[0]),
                @intCast(dest_slice.dimensions[0]),
                format,
                pixel_type,
                src_gpu.ptr,
            );
        },
        .@"2d" => {
            gl.TextureSubImage2D(
                texture_handle.api_handle,
                @intCast(dest_slice.layer_start),
                @intCast(dest_slice.offset[0]),
                @intCast(dest_slice.offset[1]),
                @intCast(dest_slice.dimensions[0]),
                @intCast(dest_slice.dimensions[1]),
                format,
                pixel_type,
                src_gpu.ptr,
            );
        },
        .@"3d",
        .array_2d,
        .array_cube,
        .cube,
        => {
            if (true) return;
            gl.TextureSubImage3D(
                texture_handle.api_handle,
                @intCast(dest_slice.layer_start),
                @intCast(dest_slice.offset[0]),
                @intCast(dest_slice.offset[1]),
                @intCast(dest_slice.offset[2]),
                @intCast(dest_slice.dimensions[0]),
                @intCast(dest_slice.dimensions[1]),
                @intCast(dest_slice.dimensions[2]),
                format,
                pixel_type,
                src_gpu.ptr,
            );
        },
    }
}

pub fn selectDevice(
    options: DeviceSelectionOptions,
    arena: std.mem.Allocator,
) DeviceSelectionError!*Device {
    if (context.proc_table == null) {
        _ = options; // autofix
        context.proc_table = undefined;

        if (!context.proc_table.?.init(glfw.getProcAddress))
            return error.FailedToFindSuitableDevice;

        gl.makeProcTableCurrent(&context.proc_table.?);

        if (@import("builtin").mode == .debug) {
            gl.DebugMessageCallback(debugCallback, null);
        }

        gl.CreateVertexArrays(1, @ptrCast(&context.global_vertex_array));
    }

    context.arena = arena;

    return @ptrFromInt(0xff);
}

pub fn freeDevice(_: Device) void {}

pub fn setFunctionDebugInfo(
    src: std.lang.SourceLocation,
    info: gpu.debug.Info,
) void {
    _ = info; // autofix
    _ = src; // autofix
}

pub fn setStateDevice(
    _: *Device,
) void {}

pub fn createRasterVertexPipeline(
    vertex_ir: []const u8,
    fragment_ir: []const u8,
    descriptor_mapping: DescriptorHeapMapping,
    description: RasterPipelineDescription,
) *Pipeline {
    const program: u32 = gl.CreateProgram();
    const data_index: u32 = @intCast(context.pipeline_descriptor_mappings.items.len);

    _ = context.pipeline_descriptor_mappings.append(
        context.arena,
        descriptor_mapping,
    ) catch @panic("oom");

    const vertex_module = createShaderModule(
        vertex_ir,
        gl.VERTEX_SHADER,
    );
    defer gl.DeleteShader(vertex_module);

    const fragment_module = createShaderModule(
        fragment_ir,
        gl.FRAGMENT_SHADER,
    );
    defer gl.DeleteShader(fragment_module);

    gl.AttachShader(program, vertex_module);
    gl.AttachShader(program, fragment_module);
    gl.LinkProgram(program);

    return @ptrFromInt(@as(u64, @bitCast(PipelineHandle{
        .program = program,
        .data_index = @intCast(data_index),
        .topology = description.topology,
    })));
}

pub fn createRasterMeshPipeline(
    mesh_ir: []const u8,
    fragment_ir: []const u8,
    descriptor_mapping: DescriptorHeapMapping,
    description: RasterPipelineDescription,
) *Pipeline {
    _ = description; // autofix
    const program: u32 = gl.CreateProgram();
    const data_index: u32 = @intCast(context.pipeline_descriptor_mappings.items.len);

    _ = context.pipeline_descriptor_mappings.append(
        context.arena,
        descriptor_mapping,
    ) catch @panic("oom");

    const vertex_module = createShaderModule(
        mesh_ir,
        gl.MESH_SHADER_EXT,
    );
    defer gl.DeleteShader(vertex_module);

    const fragment_module = createShaderModule(
        fragment_ir,
        gl.FRAGMENT_SHADER,
    );
    defer gl.DeleteShader(fragment_module);

    gl.AttachShader(program, vertex_module);
    gl.AttachShader(program, fragment_module);
    gl.LinkProgram(program);

    return @ptrFromInt(@as(u64, @bitCast(PipelineHandle{
        .program = program,
        .data_index = data_index,
    })));
}

pub fn createComputePipeline(
    compute_ir: []const u8,
    descriptor_mapping: DescriptorHeapMapping,
) *Pipeline {
    const program: u32 = gl.CreateProgram();
    const data_index: u32 = @intCast(context.pipeline_descriptor_mappings.items.len);

    _ = context.pipeline_descriptor_mappings.append(
        context.arena,
        descriptor_mapping,
    ) catch @panic("oom");

    const module = createShaderModule(
        compute_ir,
        gl.COMPUTE_SHADER,
    );
    defer gl.DeleteShader(module);

    gl.AttachShader(program, module);
    gl.LinkProgram(program);

    return @ptrFromInt(@as(u64, @bitCast(PipelineHandle{
        .program = program,
        .data_index = @intCast(data_index),
        .topology = undefined,
    })));
}

pub fn freePipeline(
    pipeline: *Pipeline,
) void {
    const handle: PipelineHandle = @bitCast(@intFromPtr(pipeline));
    gl.DeleteProgram(handle.program);
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

pub fn descriptorHeapMemoryDescription(
    size: usize,
) ResourceMemoryDescription {
    return .{
        .size = size,
        .alignment = .of(TextureDescriptor),
        .memory_type = .cpu,
    };
}

pub fn textureMemoryDescription(
    description: TextureDescription,
) ResourceMemoryDescription {
    const pixel_size: usize = switch (description.format) {
        .none => @sizeOf(u0), //TODO: should this be an error?
        .rgba8_unorm32 => @sizeOf(u32),
        .rgb8_unorm24 => @sizeOf([3]u8),
        .r32_u32 => @sizeOf(u32),
        .r16_u16 => @sizeOf(u16),
        .depth_f32 => @sizeOf(f32),
        .depth_stencil_u24_u8 => @sizeOf(u32),
    };

    const size: usize = description.dimensions[0] * description.dimensions[1] * description.dimensions[2] * pixel_size;

    return .{
        .size = size,
        .alignment = .of(u32),
        .memory_type = .cpu,
    };
}

pub fn createTexture(
    description: TextureDescription,
    memory: []const u8,
) *Texture {
    var texture_handle: u32 = 0;

    gl.CreateTextures(switch (description.type) {
        .@"1d" => gl.TEXTURE_1D,
        .@"2d" => gl.TEXTURE_2D,
        .@"3d" => gl.TEXTURE_3D,
        .array_2d => gl.TEXTURE_2D_ARRAY,
        .array_cube => gl.TEXTURE_CUBE_MAP_ARRAY,
        .cube => gl.TEXTURE_CUBE_MAP,
    }, 1, @ptrCast(&texture_handle));

    const gl_format: u32 = switch (description.format) {
        .none => @panic("Format not supported!"),
        .rgba8_unorm32 => gl.RGBA8,
        .rgb8_unorm24 => gl.RGB8,
        .r32_u32 => gl.R32UI,
        .r16_u16 => gl.R16UI,
        .depth_f32 => gl.DEPTH_COMPONENT32F,
        .depth_stencil_u24_u8 => gl.DEPTH24_STENCIL8,
    };

    const default_sampler_filter: i32 = switch (description.format) {
        .r32_u32, .r16_u16 => gl.NEAREST,
        else => gl.LINEAR,
    };

    switch (description.type) {
        .@"1d" => {
            gl.TextureStorage1D(
                texture_handle,
                @intCast(description.mip_count),
                gl_format,
                @intCast(description.dimensions[0]),
            );
        },
        .@"2d" => {
            gl.TextureStorage2D(
                texture_handle,
                @intCast(description.mip_count),
                gl_format,
                @intCast(description.dimensions[0]),
                @intCast(description.dimensions[1]),
            );
        },
        .@"3d",
        .array_2d,
        .cube,
        .array_cube,
        => {
            gl.TextureStorage3D(
                texture_handle,
                @intCast(description.mip_count),
                gl_format,
                @intCast(description.dimensions[0]),
                @intCast(description.dimensions[1]),
                @intCast(description.dimensions[2]),
            );
        },
    }

    gl.TextureParameteri(texture_handle, gl.TEXTURE_MAG_FILTER, default_sampler_filter);
    gl.TextureParameteri(texture_handle, gl.TEXTURE_MIN_FILTER, default_sampler_filter);

    const texture: *Texture = @ptrFromInt(@backingInt(
        TextureHandle{
            .api_handle = texture_handle,
            .format = description.format,
            .type = description.type,
        },
    ));

    const cmds = queueStartCommandRecording(undefined);

    memCopyToTexture(
        cmds,
        texture,
        .{ .dimensions = description.dimensions },
        undefined,
        memory,
    );

    queueSubmit(undefined, &.{cmds}, &.{});

    return texture;
}

pub fn destroyTexture(
    texture: *Texture,
) void {
    const handle: TextureHandle = @bitCast(@intFromPtr(texture));

    gl.DeleteTextures(1, @ptrCast(&handle.api_handle));
}

pub fn readDescriptorTexture(
    texture: *Texture,
) TextureDescriptor {
    const handle: TextureHandle = @bitCast(@intFromPtr(texture));

    return @bitCast(Descriptor{
        .api_handle = handle.api_handle,
        .tag = .image_sampled,
        .format = handle.format,
    });
}

pub fn readDescriptorTextureIntoHeap(
    texture: *Texture,
    heap: *DescriptorHeap,
    offset: usize,
) usize {
    const heap_memory: [*]Descriptor = @ptrCast(@alignCast(heap));

    heap_memory[offset / @sizeOf(Descriptor)] = @bitCast(readDescriptorTexture(texture));

    return offset + 1;
}

pub fn readTextureSliceDescriptorIntoHeap(
    texture: *Texture,
    slice: gpu.TextureSliceDescription,
    heap: *DescriptorHeap,
    offset: usize,
) usize {
    _ = slice; // autofix
    const heap_memory: [*]Descriptor = @ptrCast(@alignCast(heap));

    const descriptor = &heap_memory[offset / @sizeOf(Descriptor)];

    descriptor.* = @bitCast(readDescriptorTexture(texture));
    descriptor.tag = .image_read_write;

    return offset + 1;
}

pub fn readSliceBytesDescriptorIntoHeap(
    memory: []const u8,
    heap: *DescriptorHeap,
    offset: usize,
) usize {
    if (memory.len == 0) {
        return offset + 1;
    }

    const buffer_view = translateSliceToBufferView(memory);

    const descriptor: Descriptor = .{
        .api_handle = buffer_view.api_handle,
        .tag = .buffer,
        .slice_offset = buffer_view.offset,
        .slice_length = buffer_view.len,
        .format = undefined,
    };

    const heap_memory: [*]Descriptor = @ptrCast(@alignCast(heap));

    heap_memory[offset / @sizeOf(Descriptor)] = descriptor;

    return offset + 1;
}

pub fn createDescriptorHeap(
    memory: []u8,
) !*DescriptorHeap {
    return @ptrCast(memory.ptr);
}

pub fn setStateDescriptorHeap(
    command_buffer: *CommandBuffer,
    heap: *DescriptorHeap,
) void {
    const cmd_buffer_data: *CommandBufferData = @ptrCast(@alignCast(command_buffer));

    if (!cmd_buffer_data.is_primary) {
        cmd_buffer_data.commands.append(context.arena, .{ .set_state_descriptor_heap = .{ .descriptor_heap = heap } }) catch @panic("oom");
        //return;
    }

    cmd_buffer_data.descriptor_heap = heap;
}

pub fn setStateSamplerDescriptorHeap(
    command_buffer: *CommandBuffer,
    heap: *DescriptorHeap,
) void {
    const cmd_buffer_data: *CommandBufferData = @ptrCast(@alignCast(command_buffer));

    if (!cmd_buffer_data.is_primary) {
        cmd_buffer_data.commands.append(context.arena, .{ .set_state_descriptor_heap = .{ .descriptor_heap = heap } }) catch @panic("oom");
        //return;
    }

    cmd_buffer_data.sampler_descriptor_heap = heap;
}

pub fn setStatePipeline(
    command_buffer: *CommandBuffer,
    pipeline: *Pipeline,
) void {
    const cmd_buffer_data: *CommandBufferData = @ptrCast(@alignCast(command_buffer));

    if (!cmd_buffer_data.is_primary) {
        cmd_buffer_data.commands.append(context.arena, .{ .set_state_pipeline = .{ .pipeline = pipeline } }) catch @panic("oom");
        //TODO: return
    }

    if (cmd_buffer_data.pipeline == pipeline) {}

    const pipeline_handle: PipelineHandle = @bitCast(@intFromPtr(pipeline));
    const old_pipeline_handle: PipelineHandle = @bitCast(@intFromPtr(cmd_buffer_data.pipeline));

    gl.UseProgram(pipeline_handle.program);

    const old_mapping = context.pipeline_descriptor_mappings.items[old_pipeline_handle.data_index];
    const heap_mapping = context.pipeline_descriptor_mappings.items[pipeline_handle.data_index];

    if (cmd_buffer_data.pipeline != null and old_mapping == heap_mapping) {
        return;
    }

    cmd_buffer_data.pipeline = pipeline;

    var heap_start: usize = heap_mapping.heap_offset;

    for (heap_mapping.binding_first..heap_mapping.binding_count) |binding_index| {
        var descriptor_ptr_many: [*]Descriptor = @ptrCast(@alignCast(cmd_buffer_data.descriptor_heap));
        descriptor_ptr_many += heap_start;
        const descriptor_ptr = &descriptor_ptr_many[0];

        if (descriptor_ptr.api_handle != 0) {
            gl.BindBufferRange(
                gl.SHADER_STORAGE_BUFFER,
                @intCast(binding_index),
                descriptor_ptr.api_handle,
                @intCast(descriptor_ptr.slice_offset),
                @intCast(descriptor_ptr.slice_length),
            );
        }

        heap_start += heap_mapping.heap_array_stride / @sizeOf(Descriptor);
    }

    heap_start = heap_mapping.sampler_heap_offset;

    for (heap_mapping.sampler_binding_first..heap_mapping.sampler_binding_count) |binding_index| {
        var descriptor_ptr_many: [*]Descriptor = @ptrCast(@alignCast(cmd_buffer_data.sampler_descriptor_heap));
        descriptor_ptr_many += heap_start;
        const descriptor_ptr = &descriptor_ptr_many[0];

        if (descriptor_ptr.api_handle != 0) {
            const descriptor_type = descriptor_ptr.tag;

            switch (descriptor_type) {
                .image_sampled => {
                    gl.BindTextureUnit(
                        @intCast(binding_index),
                        descriptor_ptr.api_handle,
                    );
                },
                .image_read_write => {
                    gl.BindImageTexture(
                        @intCast(binding_index),
                        descriptor_ptr.api_handle,
                        0,
                        @intFromBool(false),
                        0,
                        gl.READ_WRITE,
                        switch (descriptor_ptr.format) {
                            .rgba8_unorm32 => gl.RGBA32F,
                            .rgb8_unorm24 => gl.RGBA32F,
                            .r32_u32 => gl.R32UI,
                            .r16_u16 => gl.R16UI,
                            else => @panic(""),
                        },
                    );
                },
                else => @panic(""),
            }
        }

        heap_start += heap_mapping.sampler_heap_array_stride / @sizeOf(Descriptor);
    }
}

pub fn setStateDepthStencil(
    command_buffer: *CommandBuffer,
    state: DepthStencilState,
) void {
    const command_buffer_data: *CommandBufferData = @ptrCast(@alignCast(command_buffer));

    if (!command_buffer_data.is_primary) {
        command_buffer_data.commands.append(context.arena, .{ .set_state_depth_stencil = .{ .state = state } }) catch @panic("oom");
        //return;
    }

    const previous_state: DepthStencilState = command_buffer_data.depth_stencil_state orelse @bitCast(~@backingInt(state));
    defer command_buffer_data.depth_stencil_state = state;

    if (command_buffer_data.depth_stencil_state == state) {
        return;
    }

    //Depth state
    if (state.depth_test != previous_state.depth_test) {
        if (state.depth_test == .always) {
            gl.Disable(gl.DEPTH_TEST);
        } else {
            gl.Enable(gl.DEPTH_TEST);
        }
    }

    if (state.depth_test != previous_state.depth_test) {
        gl.DepthFunc(compareOpToGlEnum(state.depth_test));
    }

    if (state.depth_mode.write != previous_state.depth_mode.write) {
        gl.DepthMask(@intFromBool(state.depth_mode.write));
    }

    if (state.depth_bias != previous_state.depth_bias or state.depth_bias_clamp != previous_state.depth_bias_clamp) {
        if (state.depth_bias != 0) {
            gl.Enable(gl.POLYGON_OFFSET_FILL);

            if (state.depth_bias_clamp != 0) {
                gl.Enable(gl.DEPTH_CLAMP);
                gl.PolygonOffsetClamp(state.depth_bias_clamp, state.depth_bias_clamp, state.depth_bias);
            } else {
                gl.Disable(gl.DEPTH_CLAMP);
                gl.PolygonOffset(state.depth_bias, 1);
            }
        }
    }

    //Stencil state
    if (state.stencil_write_mask != previous_state.stencil_write_mask) {
        gl.StencilMask(state.stencil_write_mask);
    }

    if (state.stencil_front != previous_state.stencil_front) {
        const stencil = state.stencil_front;
        const previous_stencil = previous_state.stencil_front;
        const face = gl.FRONT;

        if (stencil.fail_op != previous_stencil.fail_op or
            stencil.depth_fail_op != previous_stencil.depth_fail_op or
            stencil.pass_op != previous_stencil.pass_op)
        {
            gl.StencilOpSeparate(
                face,
                compareOpToGlEnum(stencil.fail_op),
                compareOpToGlEnum(stencil.depth_fail_op),
                compareOpToGlEnum(stencil.pass_op),
            );
        }

        if (stencil.testing != previous_stencil.testing or
            stencil.reference != previous_stencil.reference or
            state.stencil_read_mask != previous_state.stencil_read_mask)
        {
            gl.StencilFuncSeparate(
                face,
                compareOpToGlEnum(stencil.testing),
                stencil.reference,
                state.stencil_read_mask,
            );
        }
    }

    if (state.stencil_back != previous_state.stencil_back) {
        const stencil = state.stencil_back;
        const previous_stencil = previous_state.stencil_back;
        const face = gl.BACK;

        if (stencil.fail_op != previous_stencil.fail_op or
            stencil.depth_fail_op != previous_stencil.depth_fail_op or
            stencil.pass_op != previous_stencil.pass_op)
        {
            gl.StencilOpSeparate(
                face,
                compareOpToGlEnum(stencil.fail_op),
                compareOpToGlEnum(stencil.depth_fail_op),
                compareOpToGlEnum(stencil.pass_op),
            );
        }

        if (stencil.testing != previous_stencil.testing or
            stencil.reference != previous_stencil.reference or
            state.stencil_read_mask != previous_state.stencil_read_mask)
        {
            gl.StencilFuncSeparate(
                face,
                compareOpToGlEnum(stencil.testing),
                stencil.reference,
                state.stencil_read_mask,
            );
        }
    }
}

pub fn setStateBlend(
    command_buffer: *CommandBuffer,
    state: BlendState,
) void {
    const command_buffer_data: *CommandBufferData = @ptrCast(@alignCast(command_buffer));

    if (!command_buffer_data.is_primary) {
        command_buffer_data.commands.append(context.arena, .{ .set_state_blend = .{ .state = state } }) catch @panic("oom");
        //return;
    }

    const previous_state: BlendState = command_buffer_data.blend_state orelse @bitCast(~@backingInt(state));
    defer command_buffer_data.blend_state = state;

    if (state == previous_state) {
        return;
    }

    if (state.colour_write_mask == 0) {
        gl.Disable(gl.BLEND);
    } else {
        gl.Enable(gl.BLEND);
    }

    if (state.color_op != previous_state.color_op) {
        gl.BlendEquation(switch (state.color_op) {
            .add => gl.FUNC_ADD,
            .subtract => gl.FUNC_SUBTRACT,
            .rev_subtract => gl.FUNC_REVERSE_SUBTRACT,
            .min => gl.MIN,
            .max => gl.MAX,
        });
    }

    if (state.src_color != previous_state.src_color or state.dst_color != previous_state.dst_color) {
        gl.BlendFunc(blendFactorToGlEnum(state.src_color), blendFactorToGlEnum(state.dst_color));
    }
}

pub fn setStateCull(
    command_buffer: *CommandBuffer,
    cull: gpu.RasterPipelineDescription.Cull,
) void {
    _ = command_buffer; // autofix
    gl.CullFace(switch (cull) {
        .clockwise => gl.FRONT,
        .anticlockwise => gl.BACK,
        .all => gl.FRONT_AND_BACK,
        .none => gl.NONE,
    });
}

pub fn setStatePolygonMode(
    command_buffer: *CommandBuffer,
    mode: gpu.PolygonMode,
) void {
    _ = command_buffer; // autofix
    gl.PolygonMode(gl.FRONT_AND_BACK, switch (mode) {
        .fill => gl.FILL,
        .line => gl.LINE,
        .point => gl.POINT,
    });
}

pub fn setStateViewport(
    command_buffer: *CommandBuffer,
    viewport: [4]f32,
) void {
    const command_buffer_data: *CommandBufferData = @ptrCast(@alignCast(command_buffer));

    if (!command_buffer_data.is_primary) {
        command_buffer_data.commands.append(context.arena, .{ .set_state_viewport = .{ .viewport = viewport } }) catch @panic("oom");
        //return;
    }
    defer command_buffer_data.viewport = viewport;

    if (command_buffer_data.viewport == null or !std.mem.eql(f32, &command_buffer_data.viewport.?, &viewport)) {
        gl.Viewport(
            @intFromFloat(viewport[0]),
            @intFromFloat(viewport[1]),
            @intFromFloat(viewport[2]),
            @intFromFloat(viewport[3]),
        );
    }
}

pub fn setStateScissor(
    command_buffer: *CommandBuffer,
    scissor: [4]u32,
) void {
    const command_buffer_data: *CommandBufferData = @ptrCast(@alignCast(command_buffer));

    if (!command_buffer_data.is_primary) {
        command_buffer_data.commands.append(context.arena, .{ .set_state_scissor = .{ .scissor = scissor } }) catch @panic("oom");
        //return;
    }
    defer command_buffer_data.scissor = scissor;

    if (command_buffer_data.scissor == null or !std.mem.eql(u32, command_buffer_data.scissor.?[0..], &scissor)) {
        gl.Scissor(
            @intCast(scissor[0]),
            @intCast(scissor[1]),
            @intCast(scissor[2]),
            @intCast(scissor[3]),
        );
    }
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
    ///No need to supply stages to opengl barriers
    _: ExecutionStage,
    _: ExecutionStage,
    hazards: HazardFlags,
) void {
    _ = command_buffer; // autofix
    var barrier_bits: u32 = 0;

    if (hazards.draw_commands) {
        barrier_bits |= gl.COMMAND_BARRIER_BIT;
    }

    if (hazards.depth_stencil) {
        barrier_bits |= gl.FRAMEBUFFER_BARRIER_BIT;
    }

    if (hazards.images) {
        barrier_bits |= gl.SHADER_IMAGE_ACCESS_BARRIER_BIT;
        barrier_bits |= gl.TEXTURE_UPDATE_BARRIER_BIT;
    }

    if (barrier_bits != 0) {
        gl.MemoryBarrier(barrier_bits);
    }
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

    const framebuffer_query = context.framebuffers.getOrPut(context.arena, description.color_attachments[0].texture) catch @panic("oom");

    if (!framebuffer_query.found_existing) blk: {
        var is_backbuffer: bool = false;
        for (description.color_attachments) |attachment| {
            if (@as(TextureHandle, @bitCast(@intFromPtr(attachment.texture))) == TextureHandle.backbuffer_texture) {
                is_backbuffer = true;
                framebuffer_query.value_ptr.* = 0;
                break :blk;
            }
        }

        gl.CreateFramebuffers(1, @ptrCast(framebuffer_query.value_ptr));

        const framebuffer = framebuffer_query.value_ptr.*;

        for (description.color_attachments, 0..) |attachment, index| {
            const attachment_texture_handle: TextureHandle = @bitCast(@intFromPtr(attachment.texture));
            const attachment_index: u32 = @intCast(gl.COLOR_ATTACHMENT0 + index);

            gl.NamedFramebufferTexture(
                framebuffer,
                attachment_index,
                attachment_texture_handle.api_handle,
                0,
            );
        }

        if (description.depth_attachment) |attachment| {
            const attachment_texture_handle: TextureHandle = @bitCast(@intFromPtr(attachment.texture));
            const attachment_index: u32 = @intCast(gl.DEPTH_ATTACHMENT);

            gl.NamedFramebufferTexture(
                framebuffer,
                attachment_index,
                attachment_texture_handle.api_handle,
                0,
            );
        }

        if (description.stencil_attachment) |attachment| {
            const attachment_texture_handle: TextureHandle = @bitCast(@intFromPtr(attachment.texture));
            const attachment_index: u32 = @intCast(gl.STENCIL_ATTACHMENT);

            gl.NamedFramebufferTexture(
                framebuffer,
                attachment_index,
                attachment_texture_handle.api_handle,
                0,
            );
        }
    }

    const framebuffer = framebuffer_query.value_ptr.*;

    gl.BindFramebuffer(gl.FRAMEBUFFER, framebuffer);

    for (description.color_attachments, 0..) |color_attachment, index| {
        gl.ClearNamedFramebufferfv(
            framebuffer,
            gl.COLOR,
            @intCast(index),
            @ptrCast(&color_attachment.clear),
        );
    }

    if (description.depth_attachment != null and
        description.stencil_attachment != null and
        description.depth_attachment.?.texture == description.stencil_attachment.?.texture)
    {
        gl.ClearNamedFramebufferfi(
            framebuffer,
            gl.DEPTH_STENCIL,
            0,
            description.depth_attachment.?.clear,
            description.stencil_attachment.?.clear,
        );
    } else {
        if (description.depth_attachment) |attachment| {
            gl.ClearNamedFramebufferfv(
                framebuffer,
                gl.DEPTH,
                0,
                @ptrCast(&attachment.clear),
            );
        }

        if (description.stencil_attachment) |attachment| {
            const clear: u32 = attachment.clear;

            gl.ClearNamedFramebufferfv(
                framebuffer,
                gl.STENCIL,
                0,
                @ptrCast(&clear),
            );
        }
    }
}

pub fn rasterPassEnd(
    _: *CommandBuffer,
) void {}

pub fn dispatchCompute(
    command_buffer: *CommandBuffer,
    commands: []const ComputeCommand,
) void {
    _ = command_buffer; // autofix

    for (commands) |command| {
        gl.DispatchCompute(
            command.workgroup_count_x,
            command.workgroup_count_y,
            command.workgroup_count_z,
        );
    }
}

pub fn dispatchRasterDraw(
    command_buffer: *CommandBuffer,
    commands: []const RasterDrawCommand,
    options: gpu.DispatchRasterDrawOptions,
) void {
    const command_buffer_data: *CommandBufferData = @ptrCast(@alignCast(command_buffer));
    const buffer_view = translateSliceToBufferView(std.mem.sliceAsBytes(commands));
    const pipeline_handle: PipelineHandle = @bitCast(@intFromPtr(command_buffer_data.pipeline));

    const draw_mode: u32 = switch (pipeline_handle.topology) {
        .triangle_list => gl.TRIANGLES,
        .triangle_fan => gl.TRIANGLE_FAN,
        .triangle_strip => gl.TRIANGLE_STRIP,
        .line_list => gl.LINES,
    };

    if (buffer_view.api_handle != 0) {
        gl.BindBuffer(gl.DRAW_INDIRECT_BUFFER, buffer_view.api_handle);
        gl.MultiDrawArraysIndirect(
            draw_mode,
            buffer_view.offset + options.command_offset,
            @intCast(commands.len),
            @intCast(options.command_stride),
        );
    } else {
        for (commands) |command| {
            gl.DrawArraysInstanced(
                draw_mode,
                @intCast(command.first),
                @intCast(command.count),
                @intCast(command.instance_count),
            );
        }
    }
}

pub fn dispatchRasterDrawIndexed(
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
    const buffer_view = translateSliceToBufferView(commands);

    if (buffer_view.api_handle != 0) {
        gl.BindBuffer(gl.DRAW_INDIRECT_BUFFER, buffer_view.api_handle);
        gl.MultiDrawMeshTasksIndirectEXT(
            buffer_view.offset,
            @intCast(commands.len),
            @sizeOf(ComputeCommand),
        );
    }
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
    _: *Device,
    _: QueueCapabilities,
) *Queue {
    //There is no concept of a queue in opengl so we just return 0xaa for every call of createQueue
    return @ptrFromInt(0xaa);
}

pub fn destroyQueue(
    _: *Queue,
) void {}

pub fn queueStartCommandRecording(
    _: *Queue,
) *CommandBuffer {
    const is_primary = context.pending_command_buffer_count == 0;
    defer context.pending_command_buffer_count += 1;

    if (is_primary) {
        gl.BindVertexArray(context.global_vertex_array);
    }

    const cmd_buffer = std.heap.smp_allocator.create(CommandBufferData) catch @panic("oom");
    cmd_buffer.* = .{
        .is_primary = is_primary,
        .commands = .empty,
    };

    return @ptrCast(cmd_buffer);
}

pub fn queueEndCommandRecording(
    command_buffer: *CommandBuffer,
) void {
    const command_buffer_data: *CommandBufferData = @ptrCast(@alignCast(command_buffer));
    _ = command_buffer_data; // autofix
}

pub fn queueSubmit(
    _: *Queue,
    command_buffers: []const *CommandBuffer,
    signal_semaphores: []const *Semaphore,
) void {
    _ = signal_semaphores; // autofix
    var bound_vertex_array: bool = false;

    for (command_buffers) |cmd_buffer| {
        const command_buffer_data: *CommandBufferData = @ptrCast(@alignCast(cmd_buffer));
        defer std.heap.smp_allocator.destroy(command_buffer_data);

        context.pending_command_buffer_count -|= 1;

        if (command_buffer_data.is_primary) {
            gl.Flush();
            continue;
        }

        if (!bound_vertex_array) {
            gl.BindVertexArray(context.global_vertex_array);
            bound_vertex_array = true;
        }

        //TODO: execute deferred commands
    }
}

///Creates a swapchain from a platform-specific window handle
pub fn createSwapchain(
    _: *anyopaque,
) *gpu.Swapchain {
    return @ptrFromInt(0xffff);
}

pub fn destroySwapchain(_: *gpu.Swapchain) void {}

///Obtain a texture from the swapchain which can be presented
pub fn swapchainObtainTexture(
    _: *anyopaque,
) *Texture {
    return @ptrFromInt(@as(usize, @bitCast(TextureHandle.backbuffer_texture)));
}

///Encodes a swapchain presentation command into command_buffer
pub fn swapchainPresent(
    _: *CommandBuffer,
    _: *gpu.Swapchain,
) void {}

inline fn blendFactorToGlEnum(
    factor: gpu.BlendState.Factor,
) u32 {
    return switch (factor) {
        .zero => gl.ZERO,
        .one => gl.ONE,
        .src_color => gl.SRC_COLOR,
        .dst_color => gl.DST_COLOR,
        .src_alpha => gl.SRC_ALPHA,
        .one_minus_src_alpha => gl.ONE_MINUS_SRC_ALPHA,
    };
}

inline fn compareOpToGlEnum(
    compare_op: gpu.CompareOp,
) u32 {
    return switch (compare_op) {
        .always => gl.ALWAYS,
        .never => gl.NEVER,
        .less => gl.LESS,
        .greater => gl.GREATER,
        .greater_equal => gl.GEQUAL,
        .equal => gl.EQUAL,
        .not_equal => gl.NOTEQUAL,
        .keep => gl.KEEP,
        .replace => gl.REPLACE,
    };
}

fn createShaderModule(
    ir: []const u8,
    stage: u32,
) u32 {
    const shader = gl.CreateShader(stage);

    //TOOD: check if shader exists in the machine code entry table
    if (std.mem.startsWith(
        u8,
        std.mem.trimStart(u8, ir, " \n"),
        "#version",
    )) {
        gl.ShaderSource(shader, 1, &.{ir.ptr}, null);
        gl.CompileShader(shader);
    } else {
        gl.ShaderBinary(
            1,
            @ptrCast(&shader),
            gl.SHADER_BINARY_FORMAT_SPIR_V,
            ir.ptr,
            @intCast(ir.len),
        );

        gl.SpecializeShader(
            shader,
            "main",
            0,
            undefined,
            undefined,
        );
    }

    return shader;
}

fn debugCallback(
    source: u32,
    @"type": u32,
    id: u32,
    severity: u32,
    length: i32,
    message: [*:0]const u8,
    userParam: ?*const anyopaque,
) callconv(.c) void {
    _ = source; // autofix
    _ = id; // autofix
    _ = length; // autofix
    _ = userParam; // autofix
    if (severity == gl.DEBUG_SEVERITY_HIGH or severity == gl.DEBUG_SEVERITY_MEDIUM) {
        std.debug.print("[OpenGL]: {s}\n", .{message});

        if (@"type" != gl.DEBUG_TYPE_PERFORMANCE) {
            @panic("");
        }
    }
}

const BufferView = packed struct {
    api_handle: u32,
    offset: u32,
    len: u32,
};

fn translateSliceToBufferView(slice: []const u8) BufferView {
    const ptr: GpuPointer = @bitCast(@intFromPtr(slice.ptr));

    if (ptr.allocation_index != 0) {
        const buffer = context.buffers.items[ptr.allocation_index - 1];

        return .{
            .api_handle = buffer.api_handle,
            .offset = @intCast(buffer.offset + ptr.address),
            .len = @intCast(slice.len),
        };
    } else {
        return .{
            .api_handle = 0,
            .len = 0,
            .offset = 0,
        };
    }
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
const ResourceMemoryDescription = gpu.ResourceMemoryDescription;
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
const gl = @import("gl");
const glfw = @import("zglfw");
