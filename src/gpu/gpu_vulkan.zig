var context: struct {
    arena: std.mem.Allocator,
    gpa: std.mem.Allocator,

    vulkan_loader: std.DynLib,
    vkGetInstanceProcAddr: vk.PfnGetInstanceProcAddr,

    instance: vk.InstanceProxy,
    vkb: vk.BaseWrapper,
    debug_messenger: vk.DebugUtilsMessengerEXT,
    device: vk.DeviceProxy,
    physical_device: vk.PhysicalDevice,

    graphics_queue: QueueData,
    present_queue: QueueData,

    props: vk.PhysicalDeviceProperties,
    mem_props: vk.PhysicalDeviceMemoryProperties,

    allocations: std.ArrayList(MemoryAllocation),
    descriptor_heaps: std.ArrayList(DescriptorHeapIndex),
    vma_allocator: vma.VmaAllocator,

    pipeline_pool: std.heap.MemoryPool(PipelineData),

    ///Indexed by @bitCast(queue)
    command_pools: []vk.CommandPool,
    queues: []vk.Queue,

    vk_ext_descriptor_heap_enabled: bool,

    descriptor_set_layouts: []vk.DescriptorSetLayout,

    raster_pipeline_layout: vk.PipelineLayout,
    compute_pipeline_layout: vk.PipelineLayout,
} = undefined;

const DescriptorHeapIndex = struct {
    allocation_index: u32,
    descriptor_heap_index: u32,
};

const TextureData = struct {
    allocation: []u8,
    handle: vk.Image,
    view: vk.ImageView,
    description: TextureDescription,
};

const MemoryAllocation = struct {
    buffer: vk.Buffer,
    device_address: u64,
    vma_alloc_info: vma.VmaAllocationInfo,
    vma_alloc: vma.VmaAllocation,
    textures: std.ArrayList(TextureData),
    descriptor_sets: std.ArrayList(DescriptorHeapData),
};

pub fn selectDevice(
    options: DeviceSelectionOptions,
    arena: std.mem.Allocator,
    gpa: std.mem.Allocator,
) !void {
    _ = options; // autofix
    context.arena = arena;
    context.gpa = gpa;
    context.allocations = .empty;
    context.command_pools = try arena.alloc(vk.CommandPool, 1 + std.math.maxInt(@TypeOf(@backingInt(gpu.Queue{}))));
    context.queues = try arena.alloc(vk.Queue, 1 + std.math.maxInt(@TypeOf(@backingInt(gpu.Queue{}))));
    context.vk_ext_descriptor_heap_enabled = false;
    context.descriptor_heaps = .empty;

    context.pipeline_pool = try .initCapacity(gpa, 128);

    const vulkan_loader_path: [:0]const u8 = switch (@import("builtin").os.tag) {
        .linux, .freebsd => "libvulkan.so.1",
        .windows => "vulkan-1.dll",
        .macos => "libvulkan.1.dylib",
        else => @compileError("Platform doesn't support vulkan!"),
    };

    context.vulkan_loader = try .open(vulkan_loader_path);
    errdefer context.vulkan_loader.close();

    context.vkGetInstanceProcAddr = context.vulkan_loader.lookup(
        @TypeOf(context.vkGetInstanceProcAddr),
        "vkGetInstanceProcAddr",
    ) orelse return error.LoaderProcedureNotFound;

    context.vkb = vk.BaseWrapper.load(getInstanceProcAddress);

    const allocator = arena;

    var extension_names: std.ArrayList([*:0]const u8) = .empty;
    defer extension_names.deinit(allocator);

    try extension_names.append(allocator, vk.extensions.ext_debug_utils.name);

    if (@import("builtin").os.tag == .macos) {
        // the following extensions are to support vulkan in mac os
        // see https://github.com/glfw/glfw/issues/2335
        try extension_names.append(allocator, vk.extensions.khr_portability_enumeration.name);
        try extension_names.append(allocator, vk.extensions.khr_get_physical_device_properties_2.name);
    }

    try extension_names.append(allocator, vk.extensions.khr_surface.name);

    switch (@import("builtin").os.tag) {
        .linux => {
            try extension_names.append(allocator, vk.extensions.khr_xcb_surface.name);
            //try extension_names.append(allocator, vk.extensions.khr_wayland_surface.name);
        },
        .windows => {
            try extension_names.append(allocator, vk.extensions.khr_win_32_surface.name);
        },
        .macos => {
            try extension_names.append(allocator, vk.extensions.mvk_macos_surface);
        },
        else => @compileError("Os currently not supported for vulkan!"),
    }

    _ = try context.vkb.enumerateInstanceExtensionPropertiesAlloc("", allocator);

    const instance = try context.vkb.createInstance(&.{
        .p_application_info = &.{
            .p_application_name = null,
            .application_version = vk.makeApiVersion(0, 0, 0, 0).toU32(),
            .p_engine_name = null,
            .engine_version = vk.makeApiVersion(0, 0, 0, 0).toU32(),
            .api_version = vk.API_VERSION_1_3.toU32(),
        },
        .enabled_layer_count = required_layer_names.len,
        .pp_enabled_layer_names = @ptrCast(&required_layer_names),
        .enabled_extension_count = @intCast(extension_names.items.len),
        .pp_enabled_extension_names = extension_names.items.ptr,
        .flags = .{ .enumerate_portability_khr = @import("builtin").os.tag == .macos },
    }, null);

    const vki = try allocator.create(vk.InstanceWrapper);
    errdefer allocator.destroy(vki);
    vki.* = vk.InstanceWrapper.load(instance, context.vkb.dispatch.vkGetInstanceProcAddr.?);
    context.instance = vk.InstanceProxy.init(instance, vki);
    errdefer context.instance.destroyInstance(null);

    context.debug_messenger = try context.instance.createDebugUtilsMessengerEXT(&.{
        .message_severity = .{
            .verbose_ext = true,
            .info_ext = true,
            .warning_ext = true,
            .error_ext = true,
        },
        .message_type = .{
            .general_ext = true,
            .validation_ext = true,
            .performance_ext = true,
        },
        .pfn_user_callback = &debugUtilsMessengerCallback,
        .p_user_data = null,
    }, null);

    const candidate = try pickPhysicalDevice(context.instance, allocator);
    context.physical_device = candidate.pdev;
    context.props = candidate.props;

    const dev = blk: {
        const priority = [_]f32{1};
        const qci = [_]vk.DeviceQueueCreateInfo{
            .{
                .queue_family_index = candidate.queues.graphics_family,
                .queue_count = 1,
                .p_queue_priorities = &priority,
            },
            .{
                .queue_family_index = candidate.queues.present_family,
                .queue_count = 1,
                .p_queue_priorities = &priority,
            },
        };

        const queue_count: u32 = if (candidate.queues.graphics_family == candidate.queues.present_family)
            1
        else
            2;

        var descriptor_heap_features: vk.PhysicalDeviceDescriptorHeapFeaturesEXT = .{};
        descriptor_heap_features.descriptor_heap = .true;

        var features_11: vk.PhysicalDeviceVulkan11Features = .{
            .p_next = &descriptor_heap_features,
            .shader_draw_parameters = .true,
        };

        const features_13: vk.PhysicalDeviceVulkan13Features = .{
            .p_next = &features_11,
            .synchronization_2 = .true,
            .dynamic_rendering = .true,
            .maintenance_4 = .true,
        };

        var device_extension_names: std.ArrayList([*:0]const u8) = .empty;
        defer device_extension_names.deinit(allocator);

        try device_extension_names.appendSlice(allocator, &required_device_extensions);

        if (false) {
            try device_extension_names.append(allocator, vk.extensions.ext_descriptor_heap.name);
            try device_extension_names.append(allocator, vk.extensions.khr_shader_untyped_pointers.name);
        }

        break :blk try context.instance.createDevice(candidate.pdev, &.{
            .p_next = &features_13,
            .queue_create_info_count = queue_count,
            .p_queue_create_infos = &qci,
            .enabled_extension_count = @intCast(device_extension_names.items.len),
            .pp_enabled_extension_names = @ptrCast(device_extension_names.items.ptr),
            .enabled_layer_count = 0,
            .pp_enabled_layer_names = undefined,
        }, null);
    };

    const vkd = try allocator.create(vk.DeviceWrapper);
    errdefer allocator.destroy(vkd);
    vkd.* = vk.DeviceWrapper.load(dev, context.instance.wrapper.dispatch.vkGetDeviceProcAddr.?);
    context.device = vk.DeviceProxy.init(dev, vkd);
    errdefer context.device.destroyDevice(null);

    context.graphics_queue = QueueData.init(context.device, candidate.queues.graphics_family);

    context.mem_props = context.instance.getPhysicalDeviceMemoryProperties(context.physical_device);

    const vma_vulkan_functions: vma.VmaVulkanFunctions = .{
        .vkGetInstanceProcAddr = @ptrCast(context.vkGetInstanceProcAddr),
        .vkGetDeviceProcAddr = @ptrCast(context.instance.wrapper.dispatch.vkGetDeviceProcAddr.?),
    };

    const vma_allocator_create_info: vma.VmaAllocatorCreateInfo = .{
        .flags = vma.VMA_ALLOCATOR_CREATE_EXT_MEMORY_BUDGET_BIT,
        .vulkanApiVersion = vma.VK_API_VERSION_1_3,
        .physicalDevice = @ptrFromInt(@intFromEnum(context.physical_device)),
        .device = @ptrFromInt(@intFromEnum(context.device.handle)),
        .instance = @ptrFromInt(@intFromEnum(context.instance.handle)),
        .pVulkanFunctions = &vma_vulkan_functions,
    };

    _ = vma.vmaCreateAllocator(&vma_allocator_create_info, &context.vma_allocator);

    for (context.command_pools, context.queues) |*command_pool, *queue| {
        command_pool.* = try context.device.createCommandPool(&.{
            .queue_family_index = context.graphics_queue.family,
        }, null);
        queue.* = context.graphics_queue.handle;
    }

    if (!context.vk_ext_descriptor_heap_enabled) {
        context.descriptor_set_layouts = try arena.alloc(vk.DescriptorSetLayout, 3);

        const descriptor_set_flags: vk.DescriptorSetLayoutBindingFlagsCreateInfo = .{
            .binding_count = 1,
            .p_binding_flags = &[_]vk.DescriptorBindingFlags{.{
                .update_after_bind = true,
                .partially_bound = true,
            }},
        };

        const max_textures = 1024 * 8;

        context.descriptor_set_layouts[0] = try context.device.createDescriptorSetLayout(&.{
            .p_next = &descriptor_set_flags,
            .flags = .{ .update_after_bind_pool = true },
            .binding_count = 1,
            .p_bindings = &[_]vk.DescriptorSetLayoutBinding{.{
                .binding = 0,
                .descriptor_type = .sampled_image,
                .descriptor_count = max_textures,
                .stage_flags = .{
                    .vertex = true,
                    .fragment = true,
                    .compute = true,
                },
            }},
        }, null);

        context.descriptor_set_layouts[1] = try context.device.createDescriptorSetLayout(&.{
            .p_next = &descriptor_set_flags,
            .flags = .{ .update_after_bind_pool = true },
            .binding_count = 1,
            .p_bindings = &[_]vk.DescriptorSetLayoutBinding{.{
                .binding = 0,
                .descriptor_type = .storage_image,
                .descriptor_count = max_textures,
                .stage_flags = .{
                    .vertex = true,
                    .fragment = true,
                    .compute = true,
                },
            }},
        }, null);

        context.descriptor_set_layouts[2] = try context.device.createDescriptorSetLayout(&.{
            .p_next = &descriptor_set_flags,
            .flags = .{ .update_after_bind_pool = true },
            .binding_count = 1,
            .p_bindings = &[_]vk.DescriptorSetLayoutBinding{.{
                .binding = 0,
                .descriptor_type = .sampler,
                .descriptor_count = max_textures,
                .stage_flags = .{
                    .vertex = true,
                    .fragment = true,
                    .compute = true,
                },
            }},
        }, null);

        context.raster_pipeline_layout = try context.device.createPipelineLayout(&.{
            .push_constant_range_count = 1,
            .p_push_constant_ranges = &[_]vk.PushConstantRange{
                .{
                    .stage_flags = .{ .vertex = true, .fragment = true },
                    .offset = 0,
                    .size = @sizeOf(CommonPushConstants),
                },
            },
            .p_set_layouts = context.descriptor_set_layouts.ptr,
            .set_layout_count = @intCast(context.descriptor_set_layouts.len),
        }, null);
        context.compute_pipeline_layout = try context.device.createPipelineLayout(&.{
            .push_constant_range_count = 1,
            .p_push_constant_ranges = &[_]vk.PushConstantRange{
                .{
                    .stage_flags = .{ .compute = true },
                    .offset = 0,
                    .size = @sizeOf(CommonPushConstants),
                },
            },
            .p_set_layouts = context.descriptor_set_layouts.ptr,
            .set_layout_count = @intCast(context.descriptor_set_layouts.len),
        }, null);
    }
}

pub fn freeDevice(
    gpa: std.mem.Allocator,
) void {
    _ = gpa; // autofix
}

pub fn memAlloc(
    size: usize,
    alignment: std.mem.Alignment,
    memory_type: mem.Allocator.MemoryType,
) std.mem.Allocator.Error![]u8 {
    if (size == 0) return &.{};

    var vma_usage: u32 = 0;
    var properties: vk.MemoryPropertyFlags = .{};

    switch (memory_type) {
        .gpu => {
            vma_usage = vma.VMA_MEMORY_USAGE_GPU_ONLY;
            properties = .{ .device_local = true };
        },
        .gpu_cpu_writable => {
            vma_usage = vma.VMA_MEMORY_USAGE_GPU_ONLY;
            properties = .{ .device_local = true, .host_visible = true };
        },
        .cpu => return std.heap.page_allocator.rawAlloc(size, alignment, @returnAddress()).?[0..size],
        .readback => {
            vma_usage = vma.VMA_MEMORY_USAGE_GPU_TO_CPU;
            properties = .{
                .host_visible = true,
                .host_cached = true,
                .host_coherent = true,
            };
        },
    }

    const buffer_usage: vk.BufferUsageFlags = .{
        .shader_device_address = true,
        .storage_buffer = true,
        .index_buffer = true,
        .transfer_src = true,
        .transfer_dst = true,
        .indirect_buffer = true,
    };

    const buffer_create_info: vk.BufferCreateInfo = .{
        .size = size,
        .usage = buffer_usage,
        .sharing_mode = .exclusive,
    };

    const buffer = context.device.createBuffer(
        &buffer_create_info,
        null,
    ) catch @panic("");

    var memory_requirements = context.device.getBufferMemoryRequirements(buffer);

    memory_requirements.alignment = @max(memory_requirements.alignment, alignment.toByteUnits());

    const allocation_create_info: vma.VmaAllocationCreateInfo = .{
        .flags = if (memory_type != .gpu) vma.VMA_ALLOCATION_CREATE_MAPPED_BIT else 0,
        .usage = vma_usage,
        .requiredFlags = @bitCast(properties),
    };

    var vma_alloc: vma.VmaAllocation = undefined;
    var vma_alloc_info: vma.VmaAllocationInfo = undefined;

    _ = vma.vmaAllocateMemory(
        context.vma_allocator,
        @ptrCast(&memory_requirements),
        &allocation_create_info,
        &vma_alloc,
        &vma_alloc_info,
    );

    _ = vma.vmaBindBufferMemory(
        context.vma_allocator,
        vma_alloc,
        @ptrFromInt(@intFromEnum(buffer)),
    );

    const address: u64 = context.device.getBufferDeviceAddress(&.{
        .buffer = buffer,
    });

    const allocation_index: u16 = @intCast(context.allocations.items.len);

    const allocation = try context.allocations.addOne(context.arena);

    allocation.* = .{
        .device_address = if (memory_type != .gpu) @intFromPtr(vma_alloc_info.pMappedData) else address,
        .buffer = buffer,
        .vma_alloc_info = vma_alloc_info,
        .vma_alloc = vma_alloc,
        .textures = .empty,
        .descriptor_sets = .empty,
    };

    const gpu_ptr: gpu.mem.GpuPointerData = .{
        .address = @intCast(allocation.device_address),
        .allocation_handle = @intCast(allocation_index),
        .memory_type = memory_type,
    };

    const ptr: [*]u8 = @ptrFromInt(@as(u64, @bitCast(gpu_ptr)));

    return ptr[0..size];
}

///Free device memory
pub fn memFree(memory: []u8) void {
    const allocation = getMemoryAllocation(memory);

    context.device.destroyBuffer(allocation.buffer, null);
    vma.vmaFreeMemory(context.vma_allocator, allocation.vma_alloc);
}

pub fn memGetMemoryTag(memory: *const anyopaque) u16 {
    if (@import("builtin").os.tag == .macos) {
        return getMemoryAllocationTag(memory);
    }

    return 0;
}

pub fn memCopy(
    command_buffer: *CommandBuffer,
    dest_gpu: []u8,
    src_gpu: []const u8,
) void {
    const vk_command_buffer: vk.CommandBuffer = @fromBackingInt(@intFromPtr(command_buffer));
    const dest_allocation = getMemoryAllocation(dest_gpu);
    const src_allocation = getMemoryAllocation(src_gpu);

    std.debug.assert(isGpuMemory(src_gpu));

    if (true) {
        return;
    }

    context.device.cmdCopyBuffer(
        vk_command_buffer,
        src_allocation.buffer,
        dest_allocation.buffer,
        &.{},
    );
}

pub fn memCopyToTexture(
    command_buffer: *CommandBuffer,
    dest_slice: gpu.TextureSliceDescription,
    dest_gpu: []u8,
    src_gpu: []const u8,
) void {
    const vk_command_buffer: vk.CommandBuffer = @enumFromInt(@intFromPtr(command_buffer));

    std.debug.assert(isGpuMemory(dest_gpu));
    std.debug.assert(isGpuMemory(src_gpu));

    const src_allocation = getMemoryAllocation(src_gpu);
    const src_offset = getMemoryAllocationOffset(src_gpu);

    const mip_width: u32 = @max(1, dest_slice.dimensions[0] >> @as(u5, @intCast(dest_slice.mip_start)));
    const mip_height: u32 = @max(1, dest_slice.dimensions[1] >> @as(u5, @intCast(dest_slice.mip_start)));
    const mip_depth: u32 = @max(1, dest_slice.dimensions[2] >> @as(u5, @intCast(dest_slice.mip_start)));

    const dest_texture = getMemoryAllocationTexture(dest_gpu);

    context.device.cmdCopyBufferToImage(
        vk_command_buffer,
        src_allocation.buffer,
        dest_texture.handle,
        .general,
        &.{
            .{
                .buffer_offset = src_offset,
                .buffer_row_length = mip_width,
                .buffer_image_height = mip_height,
                .image_subresource = .{
                    .aspect_mask = toVkImageAspectFlags(dest_slice.format),
                    .mip_level = dest_slice.mip_start,
                    .base_array_layer = dest_slice.layer_start,
                    .layer_count = @max(1, dest_slice.layer_count),
                },
                .image_offset = .{
                    .x = if (dest_slice.dimensions[0] != 0) @intCast(dest_slice.dimensions[0]) else @intCast(dest_slice.offset[0]),
                    .y = if (dest_slice.dimensions[1] != 0) @intCast(dest_slice.dimensions[1]) else @intCast(dest_slice.offset[1]),
                    .z = if (dest_slice.dimensions[2] != 0) @intCast(dest_slice.dimensions[2]) else @intCast(dest_slice.offset[2]),
                },
                .image_extent = .{
                    .width = @intCast(mip_width),
                    .height = @intCast(mip_depth),
                    .depth = @intCast(mip_depth),
                },
            },
        },
    );
}

pub fn memSet(
    command_buffer: *CommandBuffer,
    dest_gpu: []u8,
    src_gpu: []const u8,
) void {
    _ = command_buffer; // autofix
    _ = dest_gpu; // autofix
    _ = src_gpu; // autofix
}

const PipelineData = struct {
    handle: vk.Pipeline,
    bind_point: vk.PipelineBindPoint,
};

pub fn createRasterVertexPipeline(
    vertex_ir: []const u8,
    fragment_ir: []const u8,
    description: RasterPipelineDescription,
) *Pipeline {
    var pipelines: [1]vk.Pipeline = undefined;

    const color_formats = context.arena.alloc(vk.Format, description.color_targets.len) catch @panic("oom");

    for (color_formats, description.color_targets) |*format, color_target| {
        format.* = toVkImageFormat(color_target.format);
    }

    var pipeline_rendering: vk.PipelineRenderingCreateInfo = .{
        .color_attachment_count = @intCast(color_formats.len),
        .p_color_attachment_formats = color_formats.ptr,
        .depth_attachment_format = toVkImageFormat(description.depth_format),
        .stencil_attachment_format = toVkImageFormat(description.stencil_format),
        .view_mask = 0,
    };

    const vertex_module = createShaderModule(vertex_ir);
    defer context.device.destroyShaderModule(vertex_module, null);
    const fragment_module = createShaderModule(fragment_ir);
    defer context.device.destroyShaderModule(fragment_module, null);

    const dynamic_states: []const vk.DynamicState = &.{
        //Rasterization state
        vk.DynamicState.depth_clamp_enable_ext,
        vk.DynamicState.rasterizer_discard_enable,
        vk.DynamicState.polygon_mode_ext,
        vk.DynamicState.cull_mode,
        vk.DynamicState.front_face,
        vk.DynamicState.depth_bias,
        vk.DynamicState.line_width,
        //Depth stencil state
        vk.DynamicState.depth_test_enable,
        vk.DynamicState.depth_write_enable,
        vk.DynamicState.depth_compare_op,
        vk.DynamicState.depth_bounds_test_enable,
        vk.DynamicState.stencil_test_enable,
        vk.DynamicState.stencil_op,
        vk.DynamicState.depth_bounds,
        //Blend state
        vk.DynamicState.logic_op_enable_ext,
        vk.DynamicState.logic_op_ext,
        vk.DynamicState.color_blend_enable_ext,
        vk.DynamicState.color_blend_equation_ext,
        vk.DynamicState.color_write_mask_ext,
        vk.DynamicState.blend_constants,
        //Viewport and scissor
        vk.DynamicState.viewport,
        vk.DynamicState.viewport_with_count,
        vk.DynamicState.scissor,
        vk.DynamicState.scissor_with_count,
    };

    _ = context.device.createGraphicsPipelines(
        .null_handle,
        &[_]vk.GraphicsPipelineCreateInfo{.{
            .p_next = &pipeline_rendering,
            .stage_count = 2,
            .subpass = 0,
            .base_pipeline_index = 0,
            .p_stages = &.{
                .{ .stage = .{ .vertex = true }, .module = vertex_module, .p_name = "main" },
                .{ .stage = .{ .fragment = true }, .module = fragment_module, .p_name = "main" },
            },
            .p_vertex_input_state = &.{},
            .p_input_assembly_state = &.{
                .topology = .triangle_list,
                .primitive_restart_enable = .false,
            },
            .p_rasterization_state = null,
            .p_viewport_state = null,
            .p_depth_stencil_state = null,
            .p_color_blend_state = null,
            .p_dynamic_state = &.{
                .dynamic_state_count = @intCast(dynamic_states.len),
                .p_dynamic_states = dynamic_states.ptr,
            },
            .layout = context.raster_pipeline_layout,
        }},
        null,
        &pipelines,
    ) catch @panic("oom");

    const pipeline_data = context.pipeline_pool.create(context.gpa) catch @panic("oom");

    pipeline_data.handle = pipelines[0];
    pipeline_data.bind_point = .graphics;

    return @ptrCast(pipeline_data);
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
    var pipelines: [1]vk.Pipeline = undefined;

    const module = createShaderModule(compute_ir);
    defer context.device.destroyShaderModule(module, null);

    _ = context.device.createComputePipelines(
        .null_handle,
        &.{
            .{
                .base_pipeline_index = 0,
                .stage = .{
                    .module = module,
                    .p_name = "main",
                    .stage = .{ .compute = true },
                },
                .layout = context.compute_pipeline_layout,
            },
        },
        null,
        &pipelines,
    ) catch @panic("oom");

    const pipeline_data = context.pipeline_pool.create(context.gpa) catch @panic("oom");

    pipeline_data.handle = pipelines[0];
    pipeline_data.bind_point = .compute;

    return @ptrCast(pipeline_data);
}

pub fn freePipeline(
    pipeline: *Pipeline,
) void {
    const pipeline_data: *PipelineData = @ptrCast(@alignCast(pipeline));

    context.pipeline_pool.destroy(pipeline_data);
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
    const image_create_info = toVkImageCreateInfo(description);

    const memory_info: vk.DeviceImageMemoryRequirements = .{
        .p_create_info = &image_create_info,
        .plane_aspect = toVkImageAspectFlags(description.format),
    };

    var memory_requirements_2: vk.MemoryRequirements2 = .{
        .memory_requirements = undefined,
    };
    context.device.getDeviceImageMemoryRequirements(
        &memory_info,
        &memory_requirements_2,
    );

    return .{
        .size = memory_requirements_2.memory_requirements.size,
        .alignment = .fromByteUnits(memory_requirements_2.memory_requirements.alignment),
        .memory_type = .gpu,
    };
}

pub fn registerTextureMemory(
    memory: []u8,
    description: TextureDescription,
) void {
    const image_create_info = toVkImageCreateInfo(description);

    const allocation = getMemoryAllocationPtr(memory);
    const allocation_offset = getMemoryAllocationOffset(memory);

    var image: vk.Image = .null_handle;

    std.debug.assert(vma.vmaCreateAliasingImage2(
        context.vma_allocator,
        allocation.vma_alloc,
        allocation_offset,
        @ptrCast(&image_create_info),
        @ptrCast(&image),
    ) >= 0);

    const cmds = queueStartCommandRecording(.{}, .{});

    const cmd_buffer: vk.CommandBuffer = @enumFromInt(@intFromPtr(cmds));

    std.debug.assert(image != .null_handle);

    if (false) {
        context.device.cmdPipelineBarrier2(cmd_buffer, &.{
            .image_memory_barrier_count = 1,
            .p_image_memory_barriers = @ptrCast(&vk.ImageMemoryBarrier2{
                .image = image,
                .src_queue_family_index = context.graphics_queue.family,
                .dst_queue_family_index = context.graphics_queue.family,
                .subresource_range = .{
                    .aspect_mask = toVkImageAspectFlags(description.format),
                    .base_mip_level = 0,
                    .base_array_layer = 0,
                    .level_count = description.mip_count,
                    .layer_count = description.layer_count,
                },
                .old_layout = .undefined,
                .new_layout = .general,
                .src_stage_mask = .{ .all_commands = true },
                .src_access_mask = .{ .memory_write = true },
                .dst_stage_mask = .{ .all_commands = true },
                .dst_access_mask = .{ .memory_read = true, .memory_write = true },
            }),
        });
    }

    defer queueSubmit(.{}, &.{cmds}, &.{});

    allocation.textures.append(context.gpa, .{
        .allocation = memory,
        .handle = image,
        .view = .null_handle,
        .description = description,
    }) catch @panic("oom");
}

pub fn unregisterTextureMemory(
    texture: []const u8,
) void {
    _ = texture; // autofix
}

pub fn createTextureDescriptor(
    texture: []const u8,
) TextureDescriptor {
    _ = texture; // autofix
    return undefined;
}

pub fn createTextureSliceDescriptor(
    texture: []const u8,
    slice: gpu.TextureSliceDescription,
) TextureDescriptor {
    _ = texture; // autofix
    _ = slice; // autofix
    return undefined;
}

pub fn createTextureSliceSamplerDescriptor(
    texture: []const u8,
    slice: gpu.TextureSliceDescription,
    sampler: gpu.TextureSamplerDescription,
) TextureDescriptor {
    _ = texture; // autofix
    _ = slice; // autofix
    _ = sampler; // autofix
    return undefined;
}

pub fn createSamplerDescriptor(
    sampler: gpu.TextureSamplerDescription,
) TextureDescriptor {
    _ = sampler; // autofix
    return undefined;
}

pub fn readDescriptorTextureIntoHeap(
    texture: []const u8,
    descriptor: *TextureDescriptor,
) void {
    const heap_data: DescriptorHeapData = getMemoryAllocationDescriptorHeap(descriptor);
    const texture_data = getMemoryAllocationTexture(texture);
    const vk_image: vk.Image = texture_data.handle;

    if (context.vk_ext_descriptor_heap_enabled) {
        context.device.writeResourceDescriptorsEXT(
            &.{
                .{
                    .type = .sampled_image,
                    .data = .{
                        .p_image = &.{
                            .p_view = &.{
                                .image = vk_image,
                                .view_type = .@"2d",
                                .format = undefined,
                                .components = undefined,
                                .subresource_range = undefined,
                            },
                            .layout = .general,
                        },
                    },
                },
            },
            &.{.{
                .address = gpu.mem.toAccessiblePointer(descriptor),
                .size = @sizeOf(gpu.TextureDescriptor),
            }},
        ) catch @panic("oom");
    } else {
        const sampler = context.device.createSampler(&.{
            .mag_filter = .linear,
            .min_filter = .linear,
            .mipmap_mode = .linear,
            .address_mode_u = .repeat,
            .address_mode_v = .repeat,
            .address_mode_w = .repeat,
            .mip_lod_bias = 0,
            .anisotropy_enable = .false,
            .max_anisotropy = 0,
            .compare_enable = .false,
            .compare_op = .less,
            .min_lod = 0,
            .max_lod = 0,
            .border_color = .float_opaque_black,
            .unnormalized_coordinates = .false,
        }, null) catch @panic("oom");
        const view = context.device.createImageView(&.{
            .image = vk_image,
            .view_type = .@"2d",
            .format = .r8g8b8a8_unorm,
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = .{
                .aspect_mask = toVkImageAspectFlags(.rgba8_unorm32),
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }, null) catch @panic("oom");

        context.device.updateDescriptorSets(
            &.{
                .{
                    .dst_set = heap_data.descriptor_sets[0],
                    .dst_binding = 0,
                    .dst_array_element = @intCast(descriptor - heap_data.memory.ptr),
                    .descriptor_count = 1,
                    .descriptor_type = .sampled_image,
                    .p_image_info = &[_]vk.DescriptorImageInfo{.{
                        .sampler = sampler,
                        .image_view = view,
                        .image_layout = .general,
                    }},
                    .p_buffer_info = &.{},
                    .p_texel_buffer_view = &.{},
                },
            },
            &.{},
        );
    }
}

pub fn readTextureSliceDescriptorIntoHeap(
    texture: []const u8,
    slice: gpu.TextureSliceDescription,
    heap: []u8,
) void {
    _ = texture; // autofix
    _ = slice; // autofix
    _ = heap; // autofix
}

pub fn samplerHeapMemoryDescription(
    size: usize,
) gpu.ResourceMemoryDescription {
    return .{
        .size = size,
        .alignment = .of(TextureDescriptor),
        .memory_type = if (context.vk_ext_descriptor_heap_enabled) .gpu else .cpu,
    };
}

const DescriptorHeapData = struct {
    memory: []TextureDescriptor,
    descriptor_sets: [3]vk.DescriptorSet,
    descriptor_pool: vk.DescriptorPool,
};

pub fn createDescriptorHeap(
    memory: []TextureDescriptor,
) !void {
    var data: DescriptorHeapData = undefined;

    const allocation = getMemoryAllocationPtr(memory);

    const texture_count: u32 = @intCast(memory.len / @sizeOf(gpu.TextureDescriptor));

    data.memory = memory;

    if (context.vk_ext_descriptor_heap_enabled) {
        //TODO: Descriptor heaps
    } else {
        data.descriptor_pool = try context.device.createDescriptorPool(
            &.{
                .max_sets = 3,
                .flags = .{
                    .free_descriptor_set = true,
                    .update_after_bind = true,
                },
                .pool_size_count = 3,
                .p_pool_sizes = &[_]vk.DescriptorPoolSize{
                    .{ .type = .sampled_image, .descriptor_count = texture_count },
                    .{ .type = .storage_image, .descriptor_count = texture_count },
                    .{ .type = .sampler, .descriptor_count = texture_count },
                },
            },
            null,
        );

        context.device.allocateDescriptorSets(
            &.{
                .descriptor_pool = data.descriptor_pool,
                .descriptor_set_count = @intCast(context.descriptor_set_layouts.len),
                .p_set_layouts = context.descriptor_set_layouts.ptr,
            },
            &data.descriptor_sets,
        ) catch @panic("oom");
    }

    const descriptor_set_index = allocation.descriptor_sets.items.len;

    try allocation.descriptor_sets.append(context.gpa, data);
    try context.descriptor_heaps.append(context.gpa, .{
        .allocation_index = getMemoryAllocationIndex(memory),
        .descriptor_heap_index = @intCast(descriptor_set_index),
    });
}

pub fn setStatePipeline(
    command_buffer: *CommandBuffer,
    pipeline: *Pipeline,
) void {
    const vk_command_buffer: vk.CommandBuffer = @enumFromInt(@intFromPtr(command_buffer));
    const pipeline_data: *PipelineData = @ptrCast(@alignCast(pipeline));

    context.device.cmdBindPipeline(
        vk_command_buffer,
        pipeline_data.bind_point,
        pipeline_data.handle,
    );
}

pub fn setStateDepthStencil(
    command_buffer: *CommandBuffer,
    state: DepthStencilState,
) void {
    const vk_command_buffer: vk.CommandBuffer = @enumFromInt(@intFromPtr(command_buffer));

    context.device.cmdSetDepthCompareOp(vk_command_buffer, .less);
    context.device.cmdSetDepthTestEnable(vk_command_buffer, .true);
    context.device.cmdSetDepthWriteEnable(vk_command_buffer, .true);
    context.device.cmdSetDepthBiasEnable(vk_command_buffer, .false);

    context.device.cmdSetStencilTestEnable(vk_command_buffer, .false);
    context.device.cmdSetStencilWriteMask(vk_command_buffer, .{ .front = true, .back = true }, state.stencil_write_mask);
    context.device.cmdSetStencilCompareMask(vk_command_buffer, .{ .front = true, .back = true }, state.stencil_read_mask);
    context.device.cmdSetStencilOp(vk_command_buffer, .{ .front = true }, .keep, .keep, .keep, .always);
    context.device.cmdSetStencilOp(vk_command_buffer, .{ .back = true }, .keep, .keep, .keep, .always);
    context.device.cmdSetStencilReference(vk_command_buffer, .{ .front = true }, state.stencil_front.reference);
    context.device.cmdSetStencilReference(vk_command_buffer, .{ .back = true }, state.stencil_front.reference);

    if (@import("builtin").os.tag != .macos) {
        //context.device.cmdSetDepthClipEnableEXT(vk_command_buffer, .true);
    }
}

pub fn setStateBlend(
    command_buffer: *CommandBuffer,
    state: BlendState,
) void {
    _ = state; // autofix
    const vk_command_buffer: vk.CommandBuffer = @enumFromInt(@intFromPtr(command_buffer));

    context.device.cmdSetColorBlendEnableEXT(
        vk_command_buffer,
        0,
        &.{
            .true,
        },
    );
    context.device.cmdSetColorWriteMaskEXT(
        vk_command_buffer,
        0,
        &.{},
    );
}

pub fn setStateCull(
    command_buffer: *CommandBuffer,
    cull: gpu.RasterPipelineDescription.Cull,
) void {
    _ = cull; // autofix
    const vk_command_buffer: vk.CommandBuffer = @enumFromInt(@intFromPtr(command_buffer));
    context.device.cmdSetCullMode(vk_command_buffer, .{
        .front = false,
        .back = true,
    });
}

pub fn setStatePolygonMode(
    command_buffer: *CommandBuffer,
    mode: gpu.PolygonMode,
) void {
    const vk_command_buffer: vk.CommandBuffer = @enumFromInt(@intFromPtr(command_buffer));
    context.device.cmdSetPolygonModeEXT(
        vk_command_buffer,
        switch (mode) {
            .fill => .fill,
            .line => .line,
            .point => .point,
        },
    );
}

pub fn setStateViewport(
    command_buffer: *CommandBuffer,
    viewport: [4]f32,
) void {
    const vk_command_buffer: vk.CommandBuffer = @fromBackingInt(@intFromPtr(command_buffer));

    context.device.cmdSetViewport(
        vk_command_buffer,
        0,
        &.{
            .{
                .x = viewport[0],
                .y = viewport[1],
                .width = viewport[2],
                .height = viewport[3],
                .min_depth = 0,
                .max_depth = 1,
            },
        },
    );
}

pub fn setStateScissor(
    command_buffer: *CommandBuffer,
    scissor: [4]u32,
) void {
    const vk_command_buffer: vk.CommandBuffer = @fromBackingInt(@intFromPtr(command_buffer));

    context.device.cmdSetScissor(
        vk_command_buffer,
        0,
        &.{
            .{
                .offset = .{ .x = @intCast(scissor[0]), .y = @intCast(scissor[1]) },
                .extent = .{ .width = @intCast(scissor[0]), .height = @intCast(scissor[1]) },
            },
        },
    );
}

pub fn barrier(
    command_buffer: *CommandBuffer,
    before: ExecutionStage,
    after: ExecutionStage,
    hazards: HazardFlags,
) void {
    const vk_command_buffer: vk.CommandBuffer = @fromBackingInt(@intFromPtr(command_buffer));

    const vk_before: vk.PipelineStageFlags = toVkStage(before);
    const vk_after: vk.PipelineStageFlags = toVkStage(after);

    var src_access: vk.AccessFlags = .{};
    var dst_access: vk.AccessFlags = .{};

    if (hazards.draw_commands) {
        src_access.shader_write = true;
        dst_access.indirect_command_read = true;
    }

    if (hazards.descriptors) {
        src_access.shader_write = true;
        dst_access.shader_read = true;

        if (!context.vk_ext_descriptor_heap_enabled) {
            for (context.descriptor_heaps.items) |heap_index| {
                const heap_data = context.allocations.items[heap_index.allocation_index].descriptor_sets.items[heap_index.descriptor_heap_index];
                _ = heap_data; // autofix
                //TODO: write descriptors
            }
        }
    }

    if (hazards.depth_stencil) {
        src_access.depth_stencil_attachment_write = true;
        dst_access.depth_stencil_attachment_read = true;
        dst_access.depth_stencil_attachment_write = true;
    }

    if (hazards == gpu.HazardFlags{}) {
        src_access = .{ .memory_write = true };
        dst_access = .{ .memory_write = true, .memory_read = true };
    }

    context.device.cmdPipelineBarrier(
        vk_command_buffer,
        vk_before,
        vk_after,
        .{},
        &.{.{
            .src_access_mask = src_access,
            .dst_access_mask = dst_access,
        }},
        null,
        null,
    );
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
    const vk_command_buffer: vk.CommandBuffer = @fromBackingInt(@intFromPtr(command_buffer));

    var buffer: [256]u8 = undefined;

    var alloc: std.heap.BufferFirstAllocator = .init(&buffer, std.heap.page_allocator);

    const allocator = alloc.allocator();
    const color_attachments = allocator.alloc(
        vk.RenderingAttachmentInfo,
        description.color_attachments.len,
    ) catch @panic("oom");
    defer allocator.free(color_attachments);

    for (color_attachments, description.color_attachments) |*color_attachment, input_color_attachment| {
        color_attachment.* = .{
            .image_layout = .general,
            .resolve_mode = undefined,
            .resolve_image_layout = .undefined,
            .load_op = .load,
            .store_op = .store,
            .clear_value = .{ .color = .{ .float_32 = input_color_attachment.clear.? } },
        };
    }

    context.device.cmdBeginRendering(
        vk_command_buffer,
        &.{
            .render_area = .{
                .offset = .{ .x = description.render_area.x, .y = description.render_area.y },
                .extent = .{ .width = description.render_area.width, .height = description.render_area.height },
            },
            .layer_count = 1,
            .view_mask = 0,
            .p_color_attachments = color_attachments.ptr,
            .color_attachment_count = @intCast(color_attachments.len),
        },
    );
}

pub fn rasterPassEnd(
    command_buffer: *CommandBuffer,
) void {
    const vk_command_buffer: vk.CommandBuffer = @fromBackingInt(@intFromPtr(command_buffer));
    context.device.cmdEndRendering(vk_command_buffer);
}

pub fn dispatchCompute(
    command_buffer: *CommandBuffer,
    root_data: []const *anyopaque,
    commands: []const ComputeCommand,
) void {
    const vk_command_buffer: vk.CommandBuffer = @enumFromInt(@intFromPtr(command_buffer));

    var push_constants: CommonPushConstants = undefined;

    for (root_data, 0..) |root_ptr, i| {
        push_constants.data[i] = gpu.mem.toAccessiblePointer(root_ptr);
    }

    if (context.vk_ext_descriptor_heap_enabled) {
        context.device.cmdPushDataEXT(
            vk_command_buffer,
            &.{
                .offset = 0,
                .data = .{
                    .address = &push_constants,
                    .size = @sizeOf(CommonPushConstants),
                },
            },
        );
    } else {
        context.device.cmdPushConstants(
            vk_command_buffer,
            context.compute_pipeline_layout,
            .{ .compute = true },
            0,
            @sizeOf(CommonPushConstants),
            &push_constants,
        );
    }

    for (commands) |command| {
        context.device.cmdDispatch(
            vk_command_buffer,
            command.workgroup_count_x,
            command.workgroup_count_y,
            command.workgroup_count_z,
        );
    }
}

pub fn dispatchRasterDraw(
    command_buffer: *CommandBuffer,
    root_data: []const *anyopaque,
    commands: []const RasterDrawCommand,
    options: gpu.DispatchRasterDrawOptions,
) void {
    const vk_command_buffer: vk.CommandBuffer = @enumFromInt(@intFromPtr(command_buffer));

    var push_constants: CommonPushConstants = undefined;

    for (root_data, 0..) |root_ptr, i| {
        push_constants.data[i] = gpu.mem.toAccessiblePointer(root_ptr);
    }

    if (context.vk_ext_descriptor_heap_enabled) {
        context.device.cmdPushDataEXT(
            vk_command_buffer,
            &.{
                .offset = 0,
                .data = .{
                    .address = &push_constants,
                    .size = @sizeOf(CommonPushConstants),
                },
            },
        );
    } else {
        context.device.cmdPushConstants(
            vk_command_buffer,
            context.compute_pipeline_layout,
            .{
                .vertex = true,
                .fragment = true,
            },
            0,
            @sizeOf(CommonPushConstants),
            &push_constants,
        );
    }

    if (isGpuMemory(std.mem.sliceAsBytes(commands))) {
        const commands_allocation = getMemoryAllocation(std.mem.sliceAsBytes(commands));
        const commands_offset = getMemoryAllocationOffset(std.mem.sliceAsBytes(commands));
        //draw indirect
        context.device.cmdDrawIndirect(
            vk_command_buffer,
            commands_allocation.buffer,
            commands_offset,
            @intCast(commands.len),
            @intCast(options.command_stride),
        );
    } else {
        for (commands) |command| {
            context.device.cmdDraw(
                vk_command_buffer,
                command.count,
                command.instance_count,
                command.first,
                command.first_instance,
            );
        }
    }
}

pub fn dispatchRasterDrawMeshes(
    command_buffer: *CommandBuffer,
    root_data: []const *anyopaque,
    commands: []const RasterDrawMeshesCommand,
) void {
    _ = root_data; // autofix
    _ = command_buffer; // autofix
    _ = commands; // autofix
    @panic("");
}

pub fn dispatchTraceRays(
    command_buffer: *CommandBuffer,
    root_data: []const *anyopaque,
) void {
    _ = root_data; // autofix
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

pub fn queueStartCommandRecording(
    queue: Queue,
    initial_state: gpu.CommandBufferInitialState,
) *CommandBuffer {
    const pool = context.command_pools[@backingInt(queue)];
    const cmd_buffer_allocation_info: vk.CommandBufferAllocateInfo = .{
        .command_pool = pool,
        .level = .primary,
        .command_buffer_count = 1,
    };

    var command_buffer: vk.CommandBuffer = .null_handle;

    context.device.allocateCommandBuffers(&cmd_buffer_allocation_info, @ptrCast(&command_buffer)) catch @panic("oom");

    context.device.beginCommandBuffer(command_buffer, &.{}) catch @panic("oom");

    {
        const heap_data: DescriptorHeapData = getMemoryAllocationDescriptorHeap(@ptrCast(initial_state.sampler_heap));

        const allocation = getMemoryAllocation(@ptrCast(heap_data.memory));
        const allocation_offset = getMemoryAllocationOffset(@ptrCast(heap_data.memory));

        if (context.vk_ext_descriptor_heap_enabled) {
            context.device.cmdBindSamplerHeapEXT(
                command_buffer,
                &.{
                    .heap_range = .{
                        .address = allocation.device_address + allocation_offset,
                        .size = heap_data.memory.len,
                    },
                    .reserved_range_offset = 0,
                    .reserved_range_size = 0,
                },
            );
        } else {
            context.device.cmdBindDescriptorSets(
                command_buffer,
                .graphics,
                context.raster_pipeline_layout,
                0,
                &heap_data.descriptor_sets,
                null,
            );

            context.device.cmdBindDescriptorSets(
                command_buffer,
                .compute,
                context.compute_pipeline_layout,
                0,
                &heap_data.descriptor_sets,
                null,
            );
        }
    }

    return @ptrFromInt(@backingInt(command_buffer));
}

pub fn queueEndCommandRecording(
    command_buffer: *CommandBuffer,
) void {
    const vk_command_buffer: vk.CommandBuffer = @enumFromInt(@intFromPtr(command_buffer));

    context.device.endCommandBuffer(vk_command_buffer) catch @panic("oom");
}

pub fn queueSubmit(
    queue: Queue,
    command_buffers: []const *CommandBuffer,
    semaphores: []const *Semaphore,
) void {
    _ = semaphores; // autofix
    const submit_infos: []vk.SubmitInfo = context.arena.alloc(vk.SubmitInfo, command_buffers.len) catch @panic("oom");
    defer context.arena.free(submit_infos);

    for (command_buffers, submit_infos) |*command_buffer, *submit_info| {
        const vk_command_buffer: vk.CommandBuffer = @fromBackingInt(@intFromPtr(command_buffer.*));

        submit_info.* = .{
            .p_command_buffers = @ptrCast(&vk_command_buffer),
            .command_buffer_count = 1,
        };

        context.device.endCommandBuffer(vk_command_buffer) catch @panic("End command buffer failed!");
    }

    context.device.queueSubmit(
        context.queues[@backingInt(queue)],
        submit_infos,
        .null_handle,
    ) catch @panic("oom");
}

const SwapchainData = struct {
    handle: vk.SwapchainKHR,
    surface: vk.SurfaceKHR,
};

pub fn createSwapchain(
    window: *anyopaque,
) *gpu.Swapchain {
    const swapchain_data = context.arena.create(SwapchainData) catch @panic("oom");

    swapchain_data.handle = context.device.createSwapchainKHR(
        &.{
            .surface = swapchain_data.surface,
            .min_image_count = 1,
            .image_format = .undefined,
            .image_color_space = undefined,
            .image_extent = undefined,
            .image_array_layers = undefined,
            .image_usage = undefined,
            .image_sharing_mode = .exclusive,
            .pre_transform = undefined,
            .composite_alpha = undefined,
            .present_mode = undefined,
            .clipped = undefined,
        },
        null,
    ) catch @panic("oom");

    context.allocations.append(context.gpa, .{
        .buffer = .null_handle,
        .device_address = 0,
        .vma_alloc_info = undefined,
        .vma_alloc = undefined,
        .textures = .empty,
        .descriptor_sets = .empty,
    }) catch @panic("oom");

    _ = window; // autofix
    return @ptrCast(swapchain_data);
}

pub fn destroySwapchain(swapchain: *gpu.Swapchain) void {
    const swapchain_data: *SwapchainData = @ptrCast(@alignCast(swapchain));

    context.device.destroySwapchainKHR(swapchain_data.handle, null);
}

pub fn swapchainObtainTexture(
    _: *anyopaque,
) []u8 {
    return undefined;
}

pub fn swapchainPresent(
    _: *CommandBuffer,
    _: *gpu.Swapchain,
) void {}

pub fn placeCommandTimestampQuery(
    command_buffer: *CommandBuffer,
) *gpu.debug.TimestampQuery {
    _ = command_buffer; // autofix
    return undefined;
}

pub fn queryTimestampValue(
    query: *gpu.debug.TimestampQuery,
) ?u64 {
    _ = query; // autofix
    return 0;
}

test {
    _ = std.testing.refAllDecls(@This());
}

fn getInstanceProcAddress(instance: vk.Instance, name: [*:0]const u8) vk.PfnVoidFunction {
    const result = context.vkGetInstanceProcAddr(instance, name);

    if (result == null) {
        @panic("");
    }

    return result;
}

fn debugUtilsMessengerCallback(
    severity: vk.DebugUtilsMessageSeverityFlagsEXT,
    msg_type: vk.DebugUtilsMessageTypeFlagsEXT,
    callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT,
    _: ?*anyopaque,
) callconv(.c) vk.Bool32 {
    const severity_str = if (severity.verbose_ext) "verbose" else if (severity.info_ext) "info" else if (severity.warning_ext) "warning" else if (severity.error_ext) "error" else "unknown";

    const type_str = if (msg_type.general_ext) "general" else if (msg_type.validation_ext) "validation" else if (msg_type.performance_ext) "performance" else if (msg_type.device_address_binding_ext) "device addr" else "unknown";

    const message: [*c]const u8 = if (callback_data) |cb_data| cb_data.p_message else "NO MESSAGE!";
    std.debug.print("[{s}][{s}]. Message:\n  {s}\n", .{ severity_str, type_str, message });

    return .false;
}

fn pickPhysicalDevice(
    instance: vk.InstanceProxy,
    allocator: std.mem.Allocator,
) !DeviceCandidate {
    const pdevs = try instance.enumeratePhysicalDevicesAlloc(allocator);
    defer allocator.free(pdevs);

    for (pdevs) |pdev| {
        if (try checkSuitable(instance, pdev, allocator)) |candidate| {
            return candidate;
        }
    }

    return error.NoSuitableDevice;
}

fn checkSuitable(
    instance: vk.InstanceProxy,
    pdev: vk.PhysicalDevice,
    allocator: std.mem.Allocator,
) !?DeviceCandidate {
    if (!try checkExtensionSupport(instance, pdev, allocator)) {
        return null;
    }

    if (try allocateQueues(instance, pdev, allocator)) |allocation| {
        const props = instance.getPhysicalDeviceProperties(pdev);
        return DeviceCandidate{
            .pdev = pdev,
            .props = props,
            .queues = allocation,
        };
    }

    return null;
}

fn allocateQueues(
    instance: vk.InstanceProxy,
    pdev: vk.PhysicalDevice,
    allocator: std.mem.Allocator,
) !?QueueAllocation {
    const families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(pdev, allocator);
    defer allocator.free(families);

    var graphics_family: ?u32 = null;

    for (families, 0..) |properties, i| {
        const family: u32 = @intCast(i);

        if (graphics_family == null and properties.queue_flags.graphics) {
            graphics_family = family;
        }
    }

    if (graphics_family != null) {
        return QueueAllocation{
            .graphics_family = graphics_family.?,
            .present_family = 0,
        };
    }

    return null;
}

fn checkSurfaceSupport(
    instance: vk.InstanceProxy,
    pdev: vk.PhysicalDevice,
    surface: vk.SurfaceKHR,
) !bool {
    var format_count: u32 = undefined;
    _ = try instance.getPhysicalDeviceSurfaceFormatsKHR(pdev, surface, &format_count, null);

    var present_mode_count: u32 = undefined;
    _ = try instance.getPhysicalDeviceSurfacePresentModesKHR(pdev, surface, &present_mode_count, null);

    return format_count > 0 and present_mode_count > 0;
}

fn checkExtensionSupport(
    instance: vk.InstanceProxy,
    pdev: vk.PhysicalDevice,
    allocator: std.mem.Allocator,
) !bool {
    const propsv = try instance.enumerateDeviceExtensionPropertiesAlloc(pdev, null, allocator);
    defer allocator.free(propsv);

    var descriptor_heap_features: vk.PhysicalDeviceDescriptorHeapFeaturesEXT = .{};

    var physical_device_features: vk.PhysicalDeviceFeatures2 = .{
        .p_next = &descriptor_heap_features,
        .features = undefined,
    };

    instance.getPhysicalDeviceFeatures2(pdev, &physical_device_features);

    for (required_device_extensions) |ext| {
        for (propsv) |props| {
            std.debug.print("ext = {s}\n", .{std.mem.sliceTo(&props.extension_name, 0)});

            if (std.mem.eql(u8, std.mem.span(ext), std.mem.sliceTo(&props.extension_name, 0))) {
                break;
            }
        } else {
            return false;
        }
    }

    return true;
}

const DeviceCandidate = struct {
    pdev: vk.PhysicalDevice,
    props: vk.PhysicalDeviceProperties,
    queues: QueueAllocation,
};

const QueueAllocation = struct {
    graphics_family: u32,
    present_family: u32,
};

const QueueData = struct {
    handle: vk.Queue,
    family: u32,

    fn init(device: vk.DeviceProxy, family: u32) QueueData {
        return .{
            .handle = device.getDeviceQueue(family, 0),
            .family = family,
        };
    }
};

inline fn toVkSampleCount(count: u32) vk.SampleCountFlags {
    return switch (count) {
        0 => .{ .@"1" = true },
        1 => .{ .@"1" = true },
        2 => .{ .@"2" = true },
        4 => .{ .@"4" = true },
        8 => .{ .@"8" = true },
        else => @panic("Unsupported sample count!"),
    };
}

inline fn toVkImageFormat(
    format: gpu.ImageFormat,
) vk.Format {
    return switch (format) {
        .rgba8_unorm32 => .r8g8b8a8_unorm,
        .none => @panic("Unsupported"),
        .r32_u32 => .r32_uint,
        .r16_u16 => .r16_uint,
        .depth_f32 => .d32_sfloat,
        .depth_stencil_u24_u8 => .d24_unorm_s8_uint,
    };
}

inline fn toVkImageAspectFlags(
    format: gpu.ImageFormat,
) vk.ImageAspectFlags {
    return switch (format) {
        .depth_f32, .depth_stencil_u24_u8 => .{ .depth = true },
        else => .{ .color = true },
    };
}

inline fn toVkStage(stage: gpu.ExecutionStage) vk.PipelineStageFlags {
    return switch (stage) {
        .transfer => .{ .transfer = true },
        .compute => .{ .compute_shader = true },
        .raster_color_out => .{ .color_attachment_output = true },
        .raster_fragment => .{ .fragment_shader = true },
        .raster_vertex => .{ .vertex_shader = true },
    };
}

inline fn toVkImageUsage(usage: gpu.TextureDescription.Usage) vk.ImageUsageFlags {
    return .{
        .sampled = usage.sampled,
        .storage = usage.storage,
        .color_attachment = usage.color_attachment,
        .depth_stencil_attachment = usage.depth_stencil_attachment,
        .transfer_src = false,
        .transfer_dst = true,
    };
}

inline fn toVkImageCreateInfo(description: TextureDescription) vk.ImageCreateInfo {
    return .{
        .flags = .{
            .cube_compatible = description.type == .cube or description.type == .array_cube,
            .@"2d_array_compatible" = description.type == .array_2d or description.type == .array_cube,
        },
        .image_type = switch (description.type) {
            .@"1d" => .@"1d",
            .@"2d" => .@"2d",
            .@"3d" => .@"3d",
            .cube => .@"2d",
            .array_cube => .@"2d",
            .array_2d => .@"2d",
        },
        .format = toVkImageFormat(description.format),
        .extent = .{
            .width = description.dimensions[0],
            .height = description.dimensions[1],
            .depth = description.dimensions[2],
        },
        .mip_levels = description.mip_count,
        .array_layers = description.layer_count,
        .samples = toVkSampleCount(description.sample_count),
        .usage = toVkImageUsage(description.usage),
        .tiling = .optimal,
        .sharing_mode = .exclusive,
        .initial_layout = .undefined,
    };
}

inline fn isGpuMemory(memory: []const u8) bool {
    return gpu.mem.getMemoryType(memory) != .cpu;
}

inline fn getMemoryAllocation(memory: []const u8) MemoryAllocation {
    const gpu_ptr: gpu.mem.GpuPointerData = @bitCast(@intFromPtr(memory.ptr));

    const allocation = context.allocations.items[gpu_ptr.allocation_handle];

    return allocation;
}

inline fn getMemoryAllocationIndex(memory: []const u8) u32 {
    const gpu_ptr: gpu.mem.GpuPointerData = @bitCast(@intFromPtr(memory.ptr));

    return gpu_ptr.allocation_handle;
}

inline fn getMemoryAllocationPtr(memory: []const u8) *MemoryAllocation {
    const gpu_ptr: gpu.mem.GpuPointerData = @bitCast(@intFromPtr(memory.ptr));

    const allocation = &context.allocations.items[gpu_ptr.allocation_handle];

    return allocation;
}

inline fn getMemoryAllocationOffset(memory: []const u8) u64 {
    const gpu_ptr: gpu.mem.GpuPointerData = @bitCast(@intFromPtr(memory.ptr));

    const allocation = context.allocations.items[gpu_ptr.allocation_handle];

    return gpu_ptr.address - allocation.device_address;
}

inline fn getMemoryAllocationTag(memory: *const anyopaque) u16 {
    const gpu_ptr: gpu.mem.GpuPointerData = @bitCast(@intFromPtr(memory));

    const allocation = context.allocations.items[gpu_ptr.allocation_handle];
    return @intFromPtr(allocation.device_address) & 0x00ffffff_ffffff;
}

inline fn getMemoryAllocationTexture(memory: []const u8) TextureData {
    const gpu_ptr: gpu.mem.GpuPointerData = @bitCast(@intFromPtr(memory.ptr));

    const allocation = context.allocations.items[gpu_ptr.allocation_handle];

    for (allocation.textures.items) |texture_data| {
        if (texture_data.allocation.ptr == memory.ptr) {
            return texture_data;
        }
    }

    return undefined;
}

fn getMemoryAllocationDescriptorHeap(memory: *const TextureDescriptor) DescriptorHeapData {
    const gpu_ptr: gpu.mem.GpuPointerData = @bitCast(@intFromPtr(memory));

    const allocation = context.allocations.items[gpu_ptr.allocation_handle];

    for (allocation.descriptor_sets.items) |heap_data| {
        if (@intFromPtr(heap_data.memory.ptr) >= @intFromPtr(memory) and @intFromPtr(memory) < @intFromPtr(heap_data.memory.ptr + heap_data.memory.len)) {
            return heap_data;
        }
    }

    return undefined;
}

const CommonPushConstants = extern struct {
    data: [8]*anyopaque,
};

fn createShaderModule(ir: []const u8) vk.ShaderModule {
    @setRuntimeSafety(false);
    return context.device.createShaderModule(
        &.{
            .code_size = @intCast(ir.len),
            .p_code = @ptrCast(@alignCast(ir.ptr)),
        },
        null,
    ) catch @panic("oom");
}

const required_layer_names = [_][*:0]const u8{"VK_LAYER_KHRONOS_validation"};

const required_device_extensions = [_][*:0]const u8{
    vk.extensions.khr_swapchain.name,
    vk.extensions.ext_extended_dynamic_state_3.name,
};

const Pipeline = gpu.Pipeline;
const Queue = gpu.Queue;
const CommandBuffer = gpu.CommandBuffer;
const Semaphore = gpu.Semaphore;
const TextureDescriptor = gpu.TextureDescriptor;
const Stencil = gpu.Stencil;
const DepthStencilState = gpu.DepthStencilState;
const BlendState = gpu.BlendState;
const DeviceSelectionOptions = gpu.DeviceSelectionOptions;
const DeviceSelectionError = gpu.DeviceSelectionError;
const TextureDescription = gpu.TextureDescription;
const TextureMemoryDescription = gpu.ResourceMemoryDescription;
const PipelineOptimization = gpu.PipelineOptimization;
const RasterPipelineDescription = gpu.RasterPipelineDescription;
const ImageFormat = gpu.ImageFormat;
const ExecutionStage = gpu.ExecutionStage;
const HazardFlags = gpu.HazardFlags;
const ColorTarget = gpu.ColorTarget;
const RasterPassDescription = gpu.RasterPassDescription;
const DescriptorHeapMapping = gpu.DescriptorHeapMapping;
const AccelerationStructureBuildDescription = gpu.AccelerationStructureBuildDescription;
const RasterDrawCommand = gpu.RasterDrawCommand;
const RasterDrawMeshesCommand = gpu.RasterDrawMeshesCommand;
const ComputeCommand = gpu.ComputeCommand;
const PipelineMachineCodeEntry = gpu.PipelineMachineCodeEntry;
const vma = @import("vk_mem_alloc.zig");
const mem = gpu.mem;
const vk = @import("vk.zig");
const std = @import("std");
const gpu = @import("../gpu.zig");
