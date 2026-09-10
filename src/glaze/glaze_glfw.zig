pub fn init(
    arena: std.mem.Allocator,
) !void {
    _ = arena; // autofix
    try glfw.initHint(.platform, glfw.Platform.x11);
    try glfw.init();

    glfw.windowHint(.client_api, .no_api);

    if (@import("builtin").os.tag == .macos) {
        glfw.windowHint(.cocoa_retina_framebuffer, true);
    }
    glfw.swapInterval(0);
}

pub fn deinit() void {
    glfw.terminate();
}

pub fn createSurface(
    arena: std.mem.Allocator,
    description: SurfaceDescription,
) !*Surface {
    _ = arena; // autofix

    const window = try glfw.createWindow(
        @intCast(description.preferred_width orelse 640),
        @intCast(description.preferred_height orelse 480),
        description.name,
        null,
        null,
    );

    return @ptrCast(window);
}

pub fn destroySurface(surface: *Surface) void {
    const window: *glfw.Window = @ptrCast(surface);
    window.destroy();
}

pub fn surfaceGetPlatformHandle(surface: *Surface) *anyopaque {
    return surface;
}

pub fn surfacePoll(
    arena: std.mem.Allocator,
    surface: *Surface,
) !?SurfacePollResult {
    _ = arena; // autofix
    const window: *glfw.Window = @ptrCast(surface);

    glfw.pollEvents();

    if (glfw.windowShouldClose(window)) {
        return null;
    }

    const window_size = window.getSize();

    return .{
        .surface_state = .{
            .extent = .{
                @intCast(window_size[0]),
                @intCast(window_size[1]),
            },
            .focused = false,
            .cursor_captured = false,
            .cursor_hidden = false,
        },
        .keyboard_input = .{
            .keyboard_utf8 = &.{},
        },
        .mouse_input = .{
            .cursor_position = @splat(0),
            .mouse_position = @splat(0),
        },
    };
}

fn glfwScrollCallback(window: *glfw.Window, x: f64, y: f64) callconv(.c) void {
    _ = x; // autofix
    const scroll = window.getUserPointer(f32);

    scroll.?.* = @floatCast(-y * 0.1);
}

const std = @import("std");
const glaze = @import("../glaze.zig");
const Surface = glaze.Surface;
const SurfaceDescription = glaze.SurfaceDescription;
const SurfacePollResult = glaze.SurfacePollResult;
const glfw = @import("zglfw");
