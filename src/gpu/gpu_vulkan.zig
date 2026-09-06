var context: struct {
    vulkan_loader: std.DynLib,
    instance: vk.InstanceProxy,
    arena: std.mem.Allocator,
    vkb: vk.BaseWrapper,
    debug_messenger: vk.DebugUtilsMessengerEXT,
    surface: vk.SurfaceKHR,
    device: vk.DeviceProxy,
    physical_device: vk.PhysicalDevice,

    graphics_queue: QueueData,
    present_queue: QueueData,

    props: vk.PhysicalDeviceProperties,
    mem_props: vk.PhysicalDeviceMemoryProperties,

    allocations: std.ArrayList(MemoryAllocation),
    vma_allocator: vma.VmaAllocator,

    ///Indexed by @bitCast(queue)
    command_pools: []vk.CommandPool,
    queues: []vk.Queue,

    raster_pipeline_layout: vk.PipelineLayout,
    compute_pipeline_layout: vk.PipelineLayout,

    vk_ext_descriptor_heap_enabled: bool,

    descriptor_set_layouts: []vk.DescriptorSetLayout,

    vkGetInstanceProcAddr: vk.PfnGetInstanceProcAddr,
} = undefined;

const MemoryAllocation = struct {
    buffer: vk.Buffer,
    device_address: u64,
    vma_alloc_info: vma.VmaAllocationInfo,
    vma_alloc: vma.VmaAllocation,
};

pub fn selectDevice(
    options: DeviceSelectionOptions,
    arena: std.mem.Allocator,
) !*Device {
    _ = options; // autofix
    context.arena = arena;
    context.allocations = .empty;
    context.command_pools = try arena.alloc(vk.CommandPool, 1 + std.math.maxInt(@TypeOf(@backingInt(gpu.Queue{}))));
    context.queues = try arena.alloc(vk.Queue, 1 + std.math.maxInt(@TypeOf(@backingInt(gpu.Queue{}))));
    context.vk_ext_descriptor_heap_enabled = false;

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
            //.verbose_ext = true,
            //.info_ext = true,
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

    return @ptrCast(&context.device);
}

pub fn freeDevice(device: Device) void {
    _ = device; // autofix
}

pub fn setStateDevice(
    device: *Device,
) void {
    _ = device; // autofix
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
            vma_usage = vma.VMA_MEMORY_USAGE_CPU_ONLY;
            properties = .{ .device_local = true };
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

    const gpu_ptr: gpu.mem.GpuPointerData = .{
        .address = @intCast(address),
        .allocation_handle = allocation_index + 1,
    };

    const allocation = try context.allocations.addOne(context.arena);

    allocation.device_address = address;
    allocation.buffer = buffer;
    allocation.vma_alloc_info = vma_alloc_info;
    allocation.vma_alloc = vma_alloc;

    const ptr: [*]u8 = @ptrFromInt(@as(u64, @bitCast(gpu_ptr)));

    return ptr[0..size];
}

///Free device memory
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
    @panic("");
}

pub fn memCopyToTexture(
    command_buffer: *CommandBuffer,
    dest_texture: *Texture,
    dest_slice: gpu.TextureSliceDescription,
    dest_gpu: []u8,
    src_gpu: []const u8,
) void {
    const vk_command_buffer: vk.CommandBuffer = @enumFromInt(@intFromPtr(command_buffer));
    const src_allocation = getMemoryAllocation(src_gpu);
    const src_offset = getMemoryAllocationOffset(src_gpu);

    const mip_width: u32 = @max(1, dest_slice.dimensions[0] >> @as(u5, @intCast(dest_slice.mip_start)));
    const mip_height: u32 = @max(1, dest_slice.dimensions[1] >> @as(u5, @intCast(dest_slice.mip_start)));
    const mip_depth: u32 = @max(1, dest_slice.dimensions[2] >> @as(u5, @intCast(dest_slice.mip_start)));

    _ = dest_gpu; // autofix
    context.device.cmdCopyBufferToImage(
        vk_command_buffer,
        src_allocation.buffer,
        @enumFromInt(@intFromPtr(dest_texture)),
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
    @panic("");
}

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

    std.debug.print("Creating pipeline from modules: vert[len = {}]: [{s}]\n, frag[len = {}]: [{s}]\n\n", .{
        vertex_ir.len,
        vertex_ir[0..60],
        fragment_ir.len,
        fragment_ir[0..60],
    });

    const vertex_module = createShaderModule(vertex_ir);
    defer context.device.destroyShaderModule(vertex_module, null);
    const fragment_module = createShaderModule(fragment_ir);
    defer context.device.destroyShaderModule(fragment_module, null);

    std.debug.print("Successfully created shader modules!\n", .{});

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

    return @ptrFromInt(@backingInt(pipelines[0]));
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

    std.debug.print("Successfully created compute module\n", .{});

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

    return @ptrFromInt(@backingInt(pipelines[0]));
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
    const image_create_info = toVkImageCreateInfo(description);

    std.debug.print("image_ci: {any}\n", .{
        image_create_info,
    });

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

    std.debug.print("mem_reqs: {any}\n", .{memory_requirements_2});

    return .{
        .size = memory_requirements_2.memory_requirements.size,
        .alignment = .fromByteUnits(memory_requirements_2.memory_requirements.alignment),
        .memory_type = .gpu,
    };
}

pub fn createTexture(
    description: TextureDescription,
    memory: []const u8,
) *Texture {
    const image_create_info = toVkImageCreateInfo(description);

    const allocation = getMemoryAllocation(memory);
    const allocation_offset = getMemoryAllocationOffset(memory);

    var image: vk.Image = .null_handle;

    std.debug.assert(vma.vmaCreateAliasingImage2(
        context.vma_allocator,
        allocation.vma_alloc,
        allocation_offset,
        @ptrCast(&image_create_info),
        @ptrCast(&image),
    ) >= 0);

    const cmds = queueStartCommandRecording(.{});
    queueEndCommandRecording(cmds);

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

    return @ptrFromInt(@backingInt(image));
}

pub fn destroyTexture(
    texture: *Texture,
) void {
    _ = texture; // autofix
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
    const heap_data: *DescriptorHeapData = @ptrCast(@alignCast(heap));
    const vk_image: vk.Image = @enumFromInt(@intFromPtr(texture));

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
                .address = gpu.mem.toAccessiblePointer(heap_data.memory.ptr + offset),
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
                    .dst_array_element = @intCast(offset / @sizeOf(TextureDescriptor)),
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

    return offset;
}

pub fn readSliceBytesDescriptorIntoHeap(
    memory: []const u8,
    heap: *DescriptorHeap,
    offset: usize,
) usize {
    _ = memory; // autofix
    _ = heap; // autofix
    _ = offset; // autofix
    return 0;
}

pub fn readTextureSliceDescriptorIntoHeap(
    texture: *Texture,
    slice: gpu.TextureSliceDescription,
    heap: *DescriptorHeap,
    offset: usize,
) usize {
    _ = texture; // autofix
    _ = slice; // autofix
    _ = heap; // autofix
    _ = offset; // autofix
    return 0;
}

pub fn descriptorHeapMemoryDescription(
    size: usize,
) gpu.ResourceMemoryDescription {
    return .{
        .size = size,
        .alignment = .of(TextureDescriptor),
        .memory_type = if (context.vk_ext_descriptor_heap_enabled) .gpu else .cpu,
    };
}

const DescriptorHeapData = struct {
    memory: []u8,
    descriptor_sets: [3]vk.DescriptorSet,
    descriptor_pool: vk.DescriptorPool,
};

pub fn createDescriptorHeap(
    memory: []u8,
) !*DescriptorHeap {
    const data = try std.heap.page_allocator.create(DescriptorHeapData);

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

    return @ptrCast(data);
}

pub fn setStateDescriptorHeap(
    command_buffer: *CommandBuffer,
    heap: *DescriptorHeap,
) void {
    const vk_command_buffer: vk.CommandBuffer = @enumFromInt(@intFromPtr(command_buffer));
    const heap_data: *DescriptorHeapData = @ptrCast(@alignCast(heap));

    const allocation = getMemoryAllocation(heap_data.memory);
    const allocation_offset = getMemoryAllocationOffset(heap_data.memory);

    if (context.vk_ext_descriptor_heap_enabled) {
        context.device.cmdBindResourceHeapEXT(
            vk_command_buffer,
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
            vk_command_buffer,
            .graphics,
            context.raster_pipeline_layout,
            0,
            &heap_data.descriptor_sets,
            null,
        );

        context.device.cmdBindDescriptorSets(
            vk_command_buffer,
            .compute,
            context.compute_pipeline_layout,
            0,
            &heap_data.descriptor_sets,
            null,
        );
    }
}

pub fn setStateSamplerDescriptorHeap(
    command_buffer: *CommandBuffer,
    heap: *DescriptorHeap,
) void {
    const vk_command_buffer: vk.CommandBuffer = @enumFromInt(@intFromPtr(command_buffer));
    const heap_data: *DescriptorHeapData = @ptrCast(@alignCast(heap));

    const allocation = getMemoryAllocation(heap_data.memory);
    const allocation_offset = getMemoryAllocationOffset(heap_data.memory);

    if (context.vk_ext_descriptor_heap_enabled) {
        context.device.cmdBindSamplerHeapEXT(
            vk_command_buffer,
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
            vk_command_buffer,
            .graphics,
            context.raster_pipeline_layout,
            0,
            &heap_data.descriptor_sets,
            null,
        );

        context.device.cmdBindDescriptorSets(
            vk_command_buffer,
            .compute,
            context.compute_pipeline_layout,
            0,
            &heap_data.descriptor_sets,
            null,
        );
    }
}

pub fn setStatePipeline(
    command_buffer: *CommandBuffer,
    pipeline: *Pipeline,
) void {
    const vk_command_buffer: vk.CommandBuffer = @enumFromInt(@intFromPtr(command_buffer));
    const vk_pipeline: vk.Pipeline = @enumFromInt(@intFromPtr(pipeline));

    context.device.cmdBindPipeline(vk_command_buffer, .compute, vk_pipeline);
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

pub fn setStateCull(
    command_buffer: *CommandBuffer,
    cull: gpu.RasterPipelineDescription.Cull,
) void {
    _ = cull; // autofix
    _ = command_buffer; // autofix
    @panic("");
}

pub fn setStatePolygonMode(
    command_buffer: *CommandBuffer,
    mode: gpu.PolygonMode,
) void {
    _ = mode; // autofix
    _ = command_buffer; // autofix
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
    root_data: []const *anyopaque,
    commands: []const ComputeCommand,
) void {
    const vk_command_buffer: vk.CommandBuffer = @enumFromInt(@intFromPtr(command_buffer));

    var push_constants: CommonPushConstants = undefined;

    for (root_data, 0..) |root_ptr, i| {
        push_constants.data[i] = gpu.mem.toAccessiblePointer(root_ptr);
    }

    context.device.cmdPushConstants(
        vk_command_buffer,
        context.compute_pipeline_layout,
        .{ .compute = true },
        0,
        @sizeOf(CommonPushConstants),
        &push_constants,
    );

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
    _ = root_data; // autofix
    _ = options; // autofix
    _ = command_buffer; // autofix
    _ = commands; // autofix

    @panic("");
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
        submit_info.* = .{
            .p_command_buffers = @ptrCast(command_buffer),
            .command_buffer_count = 1,
        };
    }

    context.device.queueSubmit(
        context.queues[@backingInt(queue)],
        submit_infos,
        .null_handle,
    ) catch @panic("oom");
}

pub fn createSwapchain(
    _: *anyopaque,
) *gpu.Swapchain {
    return @ptrFromInt(0xffff);
}

pub fn destroySwapchain(_: *gpu.Swapchain) void {}

pub fn swapchainObtainTexture(
    _: *anyopaque,
) *Texture {
    @panic("");
}

pub fn swapchainPresent(
    _: *CommandBuffer,
    _: *gpu.Swapchain,
) void {}

pub fn placeCommandTimestampQuery(
    command_buffer: *CommandBuffer,
) *gpu.debug.TimestampQuery {
    _ = command_buffer; // autofix
    @panic("");
}

pub fn queryTimestampValue(
    query: *gpu.debug.TimestampQuery,
) ?u64 {
    _ = query; // autofix
    @panic("");
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

fn toVkSampleCount(count: u32) vk.SampleCountFlags {
    return switch (count) {
        0 => .{ .@"1" = true },
        1 => .{ .@"1" = true },
        2 => .{ .@"2" = true },
        4 => .{ .@"4" = true },
        8 => .{ .@"8" = true },
        else => @panic("Unsupported sample count!"),
    };
}

fn toVkImageFormat(
    format: gpu.ImageFormat,
) vk.Format {
    return switch (format) {
        .rgba8_unorm32 => .r8g8b8a8_unorm,
        .none => @panic("Unsupported"),
        .rgb8_unorm24 => .r8g8b8_unorm,
        .r32_u32 => .r32_uint,
        .r16_u16 => .r16_uint,
        .depth_f32 => .d32_sfloat,
        .depth_stencil_u24_u8 => .d24_unorm_s8_uint,
    };
}

fn toVkImageAspectFlags(
    format: gpu.ImageFormat,
) vk.ImageAspectFlags {
    return switch (format) {
        .depth_f32, .depth_stencil_u24_u8 => .{ .depth = true },
        else => .{ .color = true },
    };
}

fn toVkImageUsage(usage: gpu.TextureDescription.Usage) vk.ImageUsageFlags {
    return .{
        .sampled = usage.sampled,
        .storage = usage.storage,
        .color_attachment = usage.color_attachment,
        .depth_stencil_attachment = usage.depth_stencil_attachment,
        .transfer_src = false,
        .transfer_dst = true,
    };
}

fn toVkImageCreateInfo(description: TextureDescription) vk.ImageCreateInfo {
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

inline fn getMemoryAllocation(memory: []const u8) MemoryAllocation {
    const gpu_ptr: gpu.mem.GpuPointerData = @bitCast(@intFromPtr(memory.ptr));

    const allocation = context.allocations.items[gpu_ptr.allocation_handle -| 1];

    return allocation;
}

inline fn getMemoryAllocationOffset(memory: []const u8) u64 {
    const gpu_ptr: gpu.mem.GpuPointerData = @bitCast(@intFromPtr(memory.ptr));

    const allocation = context.allocations.items[gpu_ptr.allocation_handle -| 1];

    return gpu_ptr.address - allocation.device_address;
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
};

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
