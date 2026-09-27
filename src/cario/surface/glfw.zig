pub fn deviceSelect() !void {
    if (@import("builtin").os.tag == .linux) {
        try glfw.initHint(.platform, glfw.Platform.x11);
    }
    try glfw.init();

    glfw.windowHint(.client_api, .no_api);

    if (@import("builtin").os.tag == .macos) {
        glfw.windowHint(.cocoa_retina_framebuffer, true);
    }
    glfw.swapInterval(0);
}

pub fn deviceFree() void {
    glfw.terminate();
}

pub fn createSurface(description: SurfaceDescription) !*Surface {
    const result = try std.heap.smp_allocator.create(SurfaceData);
    result.surface.width = 640;
    result.surface.height = 480;

    const window = try glfw.createWindow(
        @intCast(result.surface.width),
        @intCast(result.surface.height),
        description.label,
        null,
        null,
    );

    result.handle = window;

    return @ptrCast(result);
}

pub fn surfaceFree(surface: *Surface) void {
    const surface_data: *SurfaceData = @ptrCast(@alignCast(surface));

    surface_data.handle.destroy();
}

pub fn surfaceGetSystemHandle(surface: *Surface) *anyopaque {
    const surface_data: *SurfaceData = @ptrCast(@alignCast(surface));

    return surface_data.handle;
}

pub fn surfacePoll(surface: *Surface) ?SurfacePollResult {
    const surface_data: *SurfaceData = @ptrCast(@alignCast(surface));

    const window: *glfw.Window = surface_data.handle;

    glfw.pollEvents();

    if (glfw.windowShouldClose(window)) {
        return null;
    }

    const window_size = window.getSize();

    surface_data.surface.width = @intCast(window_size[0]);
    surface_data.surface.height = @intCast(window_size[1]);

    return .{
        .input_state = .{
            .keyboard = .{
                .keyboard_utf8 = &.{},
            },
            .mouse = .{
                .cursor_position = @splat(0),
                .mouse_position = @splat(0),
            },
        },
    };
}

pub fn createVkSurface(surface: *const Surface, instance: vk.Instance) vk.SurfaceKHR {
    const surface_data: *const SurfaceData = @ptrCast(@alignCast(surface));
    const glfw_window: *glfw.Window = surface_data.handle;

    var vk_surface: vk.SurfaceKHR = undefined;

    _ = glfw.createWindowSurface(@fromBackingInt(@backingInt(instance)), glfw_window, null, @ptrCast(&vk_surface)) catch @panic("oom");

    return vk_surface;
}

const SurfaceData = extern struct {
    surface: Surface,
    handle: *glfw.Window,
};

const Surface = @import("../surface.zig").Surface;
const SurfaceDescription = @import("../surface.zig").SurfaceDescription;
const SurfacePollResult = @import("../surface.zig").SurfacePollResult;
const std = @import("std");
const vk = @import("../bindings/vulkan/vk.zig");
const glfw = @import("zglfw");
