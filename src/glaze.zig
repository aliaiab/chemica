//! Surface and input library

pub fn init(
    arena: std.mem.Allocator,
) !void {
    _ = arena; // autofix
}

pub fn deinit() void {}

pub fn createSurface(
    arena: std.mem.Allocator,
    description: SurfaceDescription,
) !*Surface {
    _ = arena; // autofix
    _ = description; // autofix
    @panic("oom");
}

pub fn destroySurface(surface: *Surface) void {
    _ = surface; // autofix
}

///Returns the platform handle for a surface
pub fn surfaceGetPlatformHandle(surface: *Surface) *anyopaque {
    _ = surface; // autofix
    return undefined;
}

///Returns null if the surface becomes inactive
pub fn surfacePoll(
    arena: std.mem.Allocator,
    surface: *Surface,
) !?SurfacePollResult {
    _ = arena; // autofix
    _ = surface; // autofix
    return null;
}

pub const SurfacePollResult = struct {
    ///The extents of the surface in pixels
    surface_extent: [2]u32,
    keyboard_input: KeyboardInputState,
    mouse_input: MouseInputState,
};

pub const SurfaceDescription = struct {
    preferred_width: ?u32 = null,
    preferred_height: ?u32 = null,
    name: [:0]const u8,
};

pub const MouseInputState = struct {};

pub const KeyboardInputState = struct {
    keyboard_utf8: []const u8,
};

///Represents a presentable surface (a window or some other surface)
pub const Surface = opaque {
    ///Returns null if the surface becomes inactive
    pub fn poll(surface: *Surface, arena: std.mem.Allocator) !?SurfacePollResult {
        return surfacePoll(arena, surface);
    }
};

const std = @import("std");
