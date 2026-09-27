pub fn deviceSelect() !void {
    return backendCall(@src(), .{});
}

pub fn deviceFree() void {
    return backendCall(@src(), .{});
}

pub fn createSurface(description: SurfaceDescription) !*Surface {
    return backendCall(@src(), .{description});
}

pub fn surfaceFree(surface: *Surface) void {
    return backendCall(@src(), .{
        surface,
    });
}

pub fn surfaceGetSystemHandle(surface: *Surface) *anyopaque {
    return backendCall(@src(), .{surface});
}

pub fn surfacePoll(surface: *Surface) ?SurfacePollResult {
    return backendCall(@src(), .{
        surface,
    });
}

pub const Surface = extern struct {
    width: u32,
    height: u32,
};

pub const SurfaceDescription = struct {
    label: [:0]const u8,
};

pub const SurfacePollResult = struct {
    input_state: input.State,
};

inline fn backendCall(
    comptime src: std.lang.SourceLocation,
    args: anytype,
) (@typeInfo(@TypeOf(@field(backend, src.fn_name))).@"fn".return_type orelse void) {
    const return_value = @call(
        .always_inline,
        @field(backend, src.fn_name),
        args,
    );

    return return_value;
}

pub const backend = switch (@import("builtin").os.tag) {
    else => @import("surface/glfw.zig"),
};

test {
    _ = std.testing.refAllDecls(@This());
}

const input = carol.input;
const carol = @import("../carol.zig");
const std = @import("std");
