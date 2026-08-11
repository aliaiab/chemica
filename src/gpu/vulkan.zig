const required_layer_names = [_][*:0]const u8{"VK_LAYER_KHRONOS_validation"};

const required_device_extensions = [_][*:0]const u8{vk.extensions.khr_swapchain.name};

const BaseWrapper = vk.BaseWrapper;
const InstanceWrapper = vk.InstanceWrapper;
const DeviceWrapper = vk.DeviceWrapper;

pub const Context = struct {
    pub const CommandBuffer = vk.CommandBufferProxy;

    vulkan_loader: std.DynLib = undefined,

    allocator: std.mem.Allocator,

    vkb: BaseWrapper,

    instance: Instance,
    debug_messenger: vk.DebugUtilsMessengerEXT,
    surface: vk.SurfaceKHR,
    pdev: vk.PhysicalDevice,
    props: vk.PhysicalDeviceProperties,
    mem_props: vk.PhysicalDeviceMemoryProperties,

    dev: Device,
    graphics_queue: Queue,
    present_queue: Queue,

    var vkGetInstanceProcAddr: vk.PfnGetInstanceProcAddr = undefined;

    fn getInstanceProcAddress(instance: vk.Instance, name: [*:0]const u8) vk.PfnVoidFunction {
        std.debug.print("Loading {s}\n", .{name});

        const result = vkGetInstanceProcAddr(instance, name);
        //const result = glfw.getInstanceProcAddress(@bitCast(instance), name);
        if (result == null) {
            @panic("");
        }

        return result;
    }

    pub fn init(
        arena: std.mem.Allocator,
        window: *glfw.Window,
        io: std.Io,
    ) !Context {
        _ = io; // autofix
        var self: Context = undefined;
        const allocator = arena;
        self.allocator = allocator;

        const vulkan_loader_path = switch (@import("builtin").os.tag) {
            .linux, .freebsd => "libvulkan.so.1",
            .windows => "vulkan-1.dll",
            .macos => "libvulkan.1.dylib",
            else => @compileError("Targeted os doesn't support the Khronos vulkan loader!"),
        };

        self.vulkan_loader = try std.DynLib.open(vulkan_loader_path);
        errdefer self.vulkan_loader.close();

        vkGetInstanceProcAddr = self.vulkan_loader.lookup(
            @TypeOf(vkGetInstanceProcAddr),
            "vkGetInstanceProcAddr",
        ) orelse return error.LoaderProcedureNotFound;

        self.vkb = vk.BaseWrapper.load(getInstanceProcAddress);

        if (try checkLayerSupport(&self.vkb, self.allocator) == false) {
            return error.MissingLayer;
        }

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
                try extension_names.append(allocator, vk.extensions.khr_wayland_surface.name);
            },
            .windows => {
                try extension_names.append(allocator, vk.extensions.khr_win_32_surface.name);
            },
            else => @compileError("Os currently not supported for vulkan!"),
        }

        _ = try self.vkb.enumerateInstanceExtensionPropertiesAlloc("", allocator);

        const instance = try self.vkb.createInstance(&.{
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
            // enumerate_portability_khr to support vulkan in mac os
            // see https://github.com/glfw/glfw/issues/2335
            .flags = .{ .enumerate_portability_khr = @import("builtin").os.tag == .macos },
        }, null);

        const vki = try allocator.create(InstanceWrapper);
        errdefer allocator.destroy(vki);
        vki.* = InstanceWrapper.load(instance, self.vkb.dispatch.vkGetInstanceProcAddr.?);
        self.instance = Instance.init(instance, vki);
        errdefer self.instance.destroyInstance(null);

        self.debug_messenger = try self.instance.createDebugUtilsMessengerEXT(&.{
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

        self.surface = try createSurface(self.instance, window);
        errdefer self.instance.destroySurfaceKHR(self.surface, null);

        const candidate = try pickPhysicalDevice(self.instance, allocator, self.surface);
        self.pdev = candidate.pdev;
        self.props = candidate.props;

        const dev = try initializeCandidate(self.instance, candidate);

        const vkd = try allocator.create(DeviceWrapper);
        errdefer allocator.destroy(vkd);
        vkd.* = DeviceWrapper.load(dev, self.instance.wrapper.dispatch.vkGetDeviceProcAddr.?);
        self.dev = Device.init(dev, vkd);
        errdefer self.dev.destroyDevice(null);

        self.graphics_queue = Queue.init(self.dev, candidate.queues.graphics_family);
        self.present_queue = Queue.init(self.dev, candidate.queues.present_family);

        self.mem_props = self.instance.getPhysicalDeviceMemoryProperties(self.pdev);

        if (false) {
            try imgui.impl.vulkan.init(.{
                .ApiVersion = vk.API_VERSION_1_3.toU32(),
                .Instance = @ptrFromInt(@backingInt(self.instance.handle)),
                .PhysicalDevice = @ptrFromInt(@backingInt(self.pdev)),
                .Device = @ptrFromInt(@backingInt(self.dev.handle)),
                .QueueFamily = candidate.queues.graphics_family,
                .Queue = @ptrFromInt(@backingInt(self.graphics_queue.handle)),
                .DescriptorPool = null,
                .DescriptorPoolSize = 0,
                .MinImageCount = 2,
                .ImageCount = 2,
                .PipelineCache = null,
                .PipelineInfoMain = undefined,
                .PipelineInfoForViewports = undefined,
                .UseDynamicRendering = true,
                .Allocator = null,
                .CheckVkResultFn = null,
                .MinAllocationSize = 0,
                .CustomShaderVertCreateInfo = .{
                    .pNext = null,
                    .sType = @backingInt(vk.StructureType.shader_module_create_info),
                    .flags = 0,
                    .codeSize = 0,
                    .pCode = null,
                },
                .CustomShaderFragCreateInfo = .{
                    .pNext = null,
                    .sType = @backingInt(vk.StructureType.shader_module_create_info),
                    .flags = 0,
                    .codeSize = 0,
                    .pCode = null,
                },
            });
        }

        return self;
    }

    pub fn deviceName(self: *const Context) []const u8 {
        return std.mem.sliceTo(&self.props.device_name, 0);
    }

    pub fn findMemoryTypeIndex(self: Context, memory_types: u32, flags: vk.MemoryPropertyFlags) !u32 {
        for (self.mem_props.memory_types[0..self.mem_props.memory_type_count], 0..) |mem_type, i| {
            if (memory_types & (@as(u32, 1) << @truncate(i)) != 0 and mem_type.property_flags.contains(flags)) {
                return @truncate(i);
            }
        }

        return error.NoSuitableMemoryType;
    }

    pub fn allocate(self: Context, requirements: vk.MemoryRequirements, flags: vk.MemoryPropertyFlags) !vk.DeviceMemory {
        return try self.dev.allocateMemory(&.{
            .allocation_size = requirements.size,
            .memory_type_index = try self.findMemoryTypeIndex(requirements.memory_type_bits, flags),
        }, null);
    }

    pub fn deinit(context: *Context) void {
        context.vulkan_loader.close();
    }

    pub fn beginFrame(context: *Context) void {
        _ = context; // autofix

    }

    pub fn endFrame(context: *Context) void {
        _ = context; // autofix

    }

    const asym = @import("../asym.zig");

    pub fn renderGizmos(
        ctx: Context,
        scene: *asym.geo.Scene,
        views: []asym.geo.Scene.View,
    ) void {
        _ = scene; // autofix
        _ = views; // autofix
        _ = ctx; // autofix
    }
};

fn checkLayerSupport(vkb: *const BaseWrapper, alloc: std.mem.Allocator) !bool {
    const available_layers = try vkb.enumerateInstanceLayerPropertiesAlloc(alloc);
    defer alloc.free(available_layers);
    for (required_layer_names) |required_layer| {
        for (available_layers) |layer| {
            if (std.mem.eql(u8, std.mem.span(required_layer), std.mem.sliceTo(&layer.layer_name, 0))) {
                break;
            }
        } else {
            return false;
        }
    }
    return true;
}

pub const Queue = struct {
    handle: vk.Queue,
    family: u32,

    fn init(device: Device, family: u32) Queue {
        return .{
            .handle = device.getDeviceQueue(family, 0),
            .family = family,
        };
    }
};

fn createSurface(instance: Instance, window: *glfw.Window) !vk.SurfaceKHR {
    var surface: vk.SurfaceKHR = undefined;
    try glfw.createWindowSurface(
        @bitCast(instance.handle),
        window,
        null,
        @ptrCast(&surface),
    );

    return surface;
}

fn initializeCandidate(instance: Instance, candidate: DeviceCandidate) !vk.Device {
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

    return try instance.createDevice(candidate.pdev, &.{
        .queue_create_info_count = queue_count,
        .p_queue_create_infos = &qci,
        .enabled_extension_count = required_device_extensions.len,
        .pp_enabled_extension_names = @ptrCast(&required_device_extensions),
        .enabled_layer_count = 0,
        .pp_enabled_layer_names = undefined,
    }, null);
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

fn debugUtilsMessengerCallback(severity: vk.DebugUtilsMessageSeverityFlagsEXT, msg_type: vk.DebugUtilsMessageTypeFlagsEXT, callback_data: ?*const vk.DebugUtilsMessengerCallbackDataEXT, _: ?*anyopaque) callconv(.c) vk.Bool32 {
    const severity_str = if (severity.verbose_ext) "verbose" else if (severity.info_ext) "info" else if (severity.warning_ext) "warning" else if (severity.error_ext) "error" else "unknown";

    const type_str = if (msg_type.general_ext) "general" else if (msg_type.validation_ext) "validation" else if (msg_type.performance_ext) "performance" else if (msg_type.device_address_binding_ext) "device addr" else "unknown";

    const message: [*c]const u8 = if (callback_data) |cb_data| cb_data.p_message else "NO MESSAGE!";
    std.debug.print("[{s}][{s}]. Message:\n  {s}\n", .{ severity_str, type_str, message });

    return .false;
}

fn pickPhysicalDevice(
    instance: Instance,
    allocator: std.mem.Allocator,
    surface: vk.SurfaceKHR,
) !DeviceCandidate {
    const pdevs = try instance.enumeratePhysicalDevicesAlloc(allocator);
    defer allocator.free(pdevs);

    for (pdevs) |pdev| {
        if (try checkSuitable(instance, pdev, allocator, surface)) |candidate| {
            return candidate;
        }
    }

    return error.NoSuitableDevice;
}

fn checkSuitable(
    instance: Instance,
    pdev: vk.PhysicalDevice,
    allocator: std.mem.Allocator,
    surface: vk.SurfaceKHR,
) !?DeviceCandidate {
    if (!try checkExtensionSupport(instance, pdev, allocator)) {
        return null;
    }

    if (!try checkSurfaceSupport(instance, pdev, surface)) {
        return null;
    }

    if (try allocateQueues(instance, pdev, allocator, surface)) |allocation| {
        const props = instance.getPhysicalDeviceProperties(pdev);
        return DeviceCandidate{
            .pdev = pdev,
            .props = props,
            .queues = allocation,
        };
    }

    return null;
}

fn allocateQueues(instance: Instance, pdev: vk.PhysicalDevice, allocator: std.mem.Allocator, surface: vk.SurfaceKHR) !?QueueAllocation {
    const families = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(pdev, allocator);
    defer allocator.free(families);

    var graphics_family: ?u32 = null;
    var present_family: ?u32 = null;

    for (families, 0..) |properties, i| {
        const family: u32 = @intCast(i);

        if (graphics_family == null and properties.queue_flags.graphics) {
            graphics_family = family;
        }

        if (present_family == null and (try instance.getPhysicalDeviceSurfaceSupportKHR(pdev, family, surface)) == .true) {
            present_family = family;
        }
    }

    if (graphics_family != null and present_family != null) {
        return QueueAllocation{
            .graphics_family = graphics_family.?,
            .present_family = present_family.?,
        };
    }

    return null;
}

fn checkSurfaceSupport(instance: Instance, pdev: vk.PhysicalDevice, surface: vk.SurfaceKHR) !bool {
    var format_count: u32 = undefined;
    _ = try instance.getPhysicalDeviceSurfaceFormatsKHR(pdev, surface, &format_count, null);

    var present_mode_count: u32 = undefined;
    _ = try instance.getPhysicalDeviceSurfacePresentModesKHR(pdev, surface, &present_mode_count, null);

    return format_count > 0 and present_mode_count > 0;
}

fn checkExtensionSupport(
    instance: Instance,
    pdev: vk.PhysicalDevice,
    allocator: std.mem.Allocator,
) !bool {
    const propsv = try instance.enumerateDeviceExtensionPropertiesAlloc(pdev, null, allocator);
    defer allocator.free(propsv);

    for (required_device_extensions) |ext| {
        for (propsv) |props| {
            if (std.mem.eql(u8, std.mem.span(ext), std.mem.sliceTo(&props.extension_name, 0))) {
                break;
            }
        } else {
            return false;
        }
    }

    return true;
}

const Instance = vk.InstanceProxy;
const Device = vk.DeviceProxy;

pub const Simulation = struct {
    pub fn init(
        context: *Context,
        sim: @import("../Simulation.zig"),
        arena: std.mem.Allocator,
    ) !Simulation {
        _ = context; // autofix
        _ = sim; // autofix
        _ = arena; // autofix

        var gpu_sim: Simulation = .{};
        gpu_sim = gpu_sim;

        return gpu_sim;
    }

    pub fn updateCSGProgram(
        gpu_sim: *Simulation,
        sim: @import("../Simulation.zig"),
        program: @import("../Simulation.zig").CSGProgram,
    ) !void {
        _ = gpu_sim; // autofix
        _ = sim; // autofix
        _ = program; // autofix

    }

    pub fn renderSceneThumbnail(
        gpu_sim: *Simulation,
        context: Context,
        sim: *@import("../Simulation.zig"),
        scene_root_index: u32,
        scene_path: []const u8,
        gpa: std.mem.Allocator,
    ) !u32 {
        _ = gpu_sim; // autofix
        _ = context; // autofix
        _ = sim; // autofix
        _ = scene_root_index; // autofix
        _ = scene_path; // autofix
        _ = gpa; // autofix
        return 0;
    }

    pub fn update(gpu_sim: *Simulation, sim: *@import("../Simulation.zig"), shader_uniforms: ShaderUniforms) void {
        _ = gpu_sim; // autofix
        _ = sim; // autofix
        _ = shader_uniforms; // autofix

    }

    pub fn render(
        sim: Simulation,
        context: Context,
        shader_uniforms: ShaderUniforms,
        render_texture: ?*Texture,
        scene_root_index: u32,
        options: struct {
            render_sdf_raymarched: bool = false,
        },
    ) void {
        _ = sim; // autofix
        _ = context; // autofix
        _ = shader_uniforms; // autofix
        _ = render_texture; // autofix
        _ = scene_root_index; // autofix
        _ = options; // autofix
    }

    pub fn render2DScene(
        gpu_sim: *Simulation,
        context: Context,
        sim: *@import("../Simulation.zig"),
        scene_root_index: u32,
        gpa: std.mem.Allocator,
        width: u32,
        height: u32,
    ) !*Texture {
        _ = gpu_sim; // autofix
        _ = context; // autofix
        _ = sim; // autofix
        _ = scene_root_index; // autofix
        _ = gpa; // autofix
        _ = width; // autofix
        _ = height; // autofix
        return undefined;
    }
};

const Allocator = std.mem.Allocator;

pub const Swapchain = struct {
    pub const PresentState = enum {
        optimal,
        suboptimal,
    };

    gc: *const Context,
    allocator: Allocator,

    surface_format: vk.SurfaceFormatKHR,
    present_mode: vk.PresentModeKHR,
    extent: vk.Extent2D,
    handle: vk.SwapchainKHR,

    swap_images: []SwapImage,
    image_index: u32,
    next_image_acquired: vk.Semaphore,

    pub fn init(gc: *const Context, allocator: Allocator, extent: vk.Extent2D) !Swapchain {
        return try initRecycle(gc, allocator, extent, .null_handle);
    }

    pub fn initRecycle(gc: *const Context, allocator: Allocator, extent: vk.Extent2D, old_handle: vk.SwapchainKHR) !Swapchain {
        const caps = try gc.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(gc.pdev, gc.surface);
        const actual_extent = findActualExtent(caps, extent);
        if (actual_extent.width == 0 or actual_extent.height == 0) {
            return error.InvalidSurfaceDimensions;
        }

        const surface_format = try findSurfaceFormat(gc, allocator);
        const present_mode = try findPresentMode(gc, allocator);

        var image_count = caps.min_image_count + 1;
        if (caps.max_image_count > 0) {
            image_count = @min(image_count, caps.max_image_count);
        }

        const qfi = [_]u32{ gc.graphics_queue.family, gc.present_queue.family };
        const sharing_mode: vk.SharingMode = if (gc.graphics_queue.family != gc.present_queue.family)
            .concurrent
        else
            .exclusive;

        const handle = gc.dev.createSwapchainKHR(&.{
            .surface = gc.surface,
            .min_image_count = image_count,
            .image_format = surface_format.format,
            .image_color_space = surface_format.color_space,
            .image_extent = actual_extent,
            .image_array_layers = 1,
            .image_usage = .{ .color_attachment = true, .transfer_dst = true },
            .image_sharing_mode = sharing_mode,
            .queue_family_index_count = qfi.len,
            .p_queue_family_indices = &qfi,
            .pre_transform = caps.current_transform,
            .composite_alpha = .{ .opaque_khr = true },
            .present_mode = present_mode,
            .clipped = .true,
            .old_swapchain = old_handle,
        }, null) catch {
            return error.SwapchainCreationFailed;
        };
        errdefer gc.dev.destroySwapchainKHR(handle, null);

        if (old_handle != .null_handle) {
            // Apparently, the old swapchain handle still needs to be destroyed after recreating.
            gc.dev.destroySwapchainKHR(old_handle, null);
        }

        const swap_images = try initSwapchainImages(gc, handle, surface_format.format, allocator);
        errdefer {
            for (swap_images) |si| si.deinit(gc);
            allocator.free(swap_images);
        }

        var next_image_acquired = try gc.dev.createSemaphore(&.{}, null);
        errdefer gc.dev.destroySemaphore(next_image_acquired, null);

        const result = try gc.dev.acquireNextImageKHR(handle, std.math.maxInt(u64), next_image_acquired, .null_handle);
        // event with a .suboptimal_khr we can still go on to present
        // if we error even for .suboptimal_khr the example will crash and segfault
        // on resize, since even the recreated swapchain can be suboptimal during a
        // resize.
        if (result.result == .not_ready or result.result == .timeout) {
            return error.ImageAcquireFailed;
        }

        std.mem.swap(vk.Semaphore, &swap_images[result.image_index].image_acquired, &next_image_acquired);
        return Swapchain{
            .gc = gc,
            .allocator = allocator,
            .surface_format = surface_format,
            .present_mode = present_mode,
            .extent = actual_extent,
            .handle = handle,
            .swap_images = swap_images,
            .image_index = result.image_index,
            .next_image_acquired = next_image_acquired,
        };
    }

    fn deinitExceptSwapchain(self: Swapchain) void {
        for (self.swap_images) |si| si.deinit(self.gc);
        self.allocator.free(self.swap_images);
        self.gc.dev.destroySemaphore(self.next_image_acquired, null);
    }

    pub fn waitForAllFences(self: Swapchain) !void {
        for (self.swap_images) |si| try si.waitForFence(self.gc);
    }

    pub fn deinit(self: Swapchain) void {
        // if we have no swapchain none of these should exist and we can just return
        if (self.handle == .null_handle) return;
        self.deinitExceptSwapchain();
        self.gc.dev.destroySwapchainKHR(self.handle, null);
    }

    pub fn recreate(self: *Swapchain, new_extent: vk.Extent2D) !void {
        const gc = self.gc;
        const allocator = self.allocator;
        const old_handle = self.handle;

        // We need to wait until all semaphores are signaled. This can be done either using a deferred
        // destruction queue, or just by waiting until the associated queue is idle.
        try self.gc.dev.queueWaitIdle(self.gc.present_queue.handle);

        self.deinitExceptSwapchain();

        // set current handle to NULL_HANDLE to signal that the current swapchain does no longer need to be
        // de-initialized if we fail to recreate it.
        self.handle = .null_handle;
        self.* = initRecycle(gc, allocator, new_extent, old_handle) catch |err| switch (err) {
            error.SwapchainCreationFailed => {
                // we failed while recreating so our current handle still exists,
                // but we won't destroy it in the deferred deinit of this object.
                gc.dev.destroySwapchainKHR(old_handle, null);
                return err;
            },
            else => return err,
        };
    }

    pub fn currentImage(self: Swapchain) vk.Image {
        return self.swap_images[self.image_index].image;
    }

    pub fn currentSwapImage(self: Swapchain) *const SwapImage {
        return &self.swap_images[self.image_index];
    }

    pub fn present(self: *Swapchain, cmdbuf: vk.CommandBuffer) !PresentState {
        // Simple method:
        // 1) Acquire next image
        // 2) Wait for and reset fence of the acquired image
        // 3) Submit command buffer with fence of acquired image,
        //    dependendent on the semaphore signalled by the first step.
        // 4) Present current frame, dependent on semaphore signalled by previous step
        // Problem: This way we can't reference the current image while rendering.
        // Better method: Shuffle the steps around such that acquire next image is the last step,
        // leaving the swapchain in a state with the current image.
        // 1) Wait for and reset fence of current image
        // 2) Submit command buffer, signalling fence of current image and dependent on
        //    the semaphore signalled by step 4.
        // 3) Present current frame, dependent on semaphore signalled by the submit
        // 4) Acquire next image, signalling its semaphore
        // One problem that arises is that we can't know beforehand which semaphore to signal,
        // so we keep an extra auxilery semaphore that is swapped around

        // Step 1: Make sure the current frame has finished rendering
        const current = self.currentSwapImage();
        try current.waitForFence(self.gc);
        try self.gc.dev.resetFences(&.{current.frame_fence});

        // Step 2: Submit the command buffer
        const wait_stage = [_]vk.PipelineStageFlags{.{ .top_of_pipe = true }};
        try self.gc.dev.queueSubmit(self.gc.graphics_queue.handle, &.{.{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast(&current.image_acquired),
            .p_wait_dst_stage_mask = &wait_stage,
            .command_buffer_count = 1,
            .p_command_buffers = @ptrCast(&cmdbuf),
            .signal_semaphore_count = 1,
            .p_signal_semaphores = @ptrCast(&current.render_finished),
        }}, current.frame_fence);

        // Step 3: Present the current frame
        _ = try self.gc.dev.queuePresentKHR(self.gc.present_queue.handle, &.{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast(&current.render_finished),
            .swapchain_count = 1,
            .p_swapchains = @ptrCast(&self.handle),
            .p_image_indices = @ptrCast(&self.image_index),
        });

        // Step 4: Acquire next frame
        const result = try self.gc.dev.acquireNextImageKHR(
            self.handle,
            std.math.maxInt(u64),
            self.next_image_acquired,
            .null_handle,
        );

        std.mem.swap(vk.Semaphore, &self.swap_images[result.image_index].image_acquired, &self.next_image_acquired);
        self.image_index = result.image_index;

        return switch (result.result) {
            .success => .optimal,
            .suboptimal_khr => .suboptimal,
            else => unreachable,
        };
    }
};

const SwapImage = struct {
    image: vk.Image,
    view: vk.ImageView,
    image_acquired: vk.Semaphore,
    render_finished: vk.Semaphore,
    frame_fence: vk.Fence,

    fn init(gc: *const Context, image: vk.Image, format: vk.Format) !SwapImage {
        const view = try gc.dev.createImageView(&.{
            .image = image,
            .view_type = .@"2d",
            .format = format,
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = .{
                .aspect_mask = .{ .color = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }, null);
        errdefer gc.dev.destroyImageView(view, null);

        const image_acquired = try gc.dev.createSemaphore(&.{}, null);
        errdefer gc.dev.destroySemaphore(image_acquired, null);

        const render_finished = try gc.dev.createSemaphore(&.{}, null);
        errdefer gc.dev.destroySemaphore(render_finished, null);

        const frame_fence = try gc.dev.createFence(&.{ .flags = .{ .signaled = true } }, null);
        errdefer gc.dev.destroyFence(frame_fence, null);

        return SwapImage{
            .image = image,
            .view = view,
            .image_acquired = image_acquired,
            .render_finished = render_finished,
            .frame_fence = frame_fence,
        };
    }

    fn deinit(self: SwapImage, gc: *const Context) void {
        self.waitForFence(gc) catch return;
        gc.dev.destroyImageView(self.view, null);
        gc.dev.destroySemaphore(self.image_acquired, null);
        gc.dev.destroySemaphore(self.render_finished, null);
        gc.dev.destroyFence(self.frame_fence, null);
    }

    fn waitForFence(self: SwapImage, gc: *const Context) !void {
        _ = try gc.dev.waitForFences(&.{self.frame_fence}, .true, std.math.maxInt(u64));
    }
};

fn initSwapchainImages(gc: *const Context, swapchain: vk.SwapchainKHR, format: vk.Format, allocator: Allocator) ![]SwapImage {
    const images = try gc.dev.getSwapchainImagesAllocKHR(swapchain, allocator);
    defer allocator.free(images);

    const swap_images = try allocator.alloc(SwapImage, images.len);
    errdefer allocator.free(swap_images);

    var i: usize = 0;
    errdefer for (swap_images[0..i]) |si| si.deinit(gc);

    for (images) |image| {
        swap_images[i] = try SwapImage.init(gc, image, format);
        i += 1;
    }

    return swap_images;
}

fn findSurfaceFormat(gc: *const Context, allocator: Allocator) !vk.SurfaceFormatKHR {
    const preferred = vk.SurfaceFormatKHR{
        .format = .b8g8r8a8_srgb,
        .color_space = .srgb_nonlinear_khr,
    };

    const surface_formats = try gc.instance.getPhysicalDeviceSurfaceFormatsAllocKHR(gc.pdev, gc.surface, allocator);
    defer allocator.free(surface_formats);

    for (surface_formats) |sfmt| {
        if (std.meta.eql(sfmt, preferred)) {
            return preferred;
        }
    }

    return surface_formats[0]; // There must always be at least one supported surface format
}

fn findPresentMode(gc: *const Context, allocator: Allocator) !vk.PresentModeKHR {
    const present_modes = try gc.instance.getPhysicalDeviceSurfacePresentModesAllocKHR(gc.pdev, gc.surface, allocator);
    defer allocator.free(present_modes);

    const preferred = [_]vk.PresentModeKHR{
        .mailbox_khr,
        .immediate_khr,
    };

    for (preferred) |mode| {
        if (std.mem.indexOfScalar(vk.PresentModeKHR, present_modes, mode) != null) {
            return mode;
        }
    }

    return .fifo_khr;
}

fn findActualExtent(caps: vk.SurfaceCapabilitiesKHR, extent: vk.Extent2D) vk.Extent2D {
    if (caps.current_extent.width != 0xFFFF_FFFF) {
        return caps.current_extent;
    } else {
        return .{
            .width = std.math.clamp(extent.width, caps.min_image_extent.width, caps.max_image_extent.width),
            .height = std.math.clamp(extent.height, caps.min_image_extent.height, caps.max_image_extent.height),
        };
    }
}

const imgui = @import("../imgui.zig");
const Texture = @import("../gpu.zig").Texture;
const ShaderUniforms = @import("lib").shaders.ShaderUniforms;
const vk = @import("vk.zig");
const glfw = @import("zglfw");
const std = @import("std");
