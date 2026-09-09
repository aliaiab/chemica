//! Surface and input library

pub fn init(
    arena: std.mem.Allocator,
) !void {
    return backendCall(@src(), .{
        arena,
    });
}

pub fn deinit() void {
    return backendCall(@src(), .{});
}

pub fn createSurface(
    arena: std.mem.Allocator,
    description: SurfaceDescription,
) !*Surface {
    return backendCall(@src(), .{
        arena, description,
    });
}

pub fn destroySurface(surface: *Surface) void {
    return backendCall(@src(), .{
        surface,
    });
}

///Returns the platform handle for a surface
pub fn surfaceGetPlatformHandle(surface: *Surface) *anyopaque {
    return backendCall(@src(), .{
        surface,
    });
}

///Returns null if the surface becomes inactive
pub fn surfacePoll(
    arena: std.mem.Allocator,
    surface: *Surface,
) !?SurfacePollResult {
    return backendCall(@src(), .{
        arena,
        surface,
    });
}

pub const SurfacePollResult = struct {
    surface_state: SurfaceState,
    ///The extents of the surface in pixels
    keyboard_input: KeyboardInputState,
    mouse_input: MouseInputState,
};

pub const SurfaceState = struct {
    extent: [2]u16,
    focused: bool,
    cursor_captured: bool,
    cursor_hidden: bool,
};

pub const SurfaceDescription = struct {
    preferred_width: ?u32 = null,
    preferred_height: ?u32 = null,
    name: [:0]const u8,
};

pub const MouseInputState = struct {
    buttons: std.EnumArray(MouseButton, ButtonAction) = .initFill(.release),
    cursor_position: [2]f32,
    mouse_position: [2]f32,
};

pub const KeyboardInputState = struct {
    keys: std.EnumArray(KeyboardKey, ButtonAction) = .initFill(.release),
    keyboard_utf8: []const u8,
};

pub const KeyboardKey = enum(u8) {
    unknown,
    space,
    apostrophe,
    comma,
    minus,
    period,
    slash,
    zero,
    one,
    two,
    three,
    four,
    five,
    six,
    seven,
    eight,
    nine,
    semicolon,
    equal,
    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,
    i,
    j,
    k,
    l,
    m,
    n,
    o,
    p,
    q,
    r,
    s,
    t,
    u,
    v,
    w,
    x,
    y,
    z,
    left_bracket,
    backslash,
    right_bracket,
    grave_accent,
    world_1,
    world_2,
    escape,
    enter,
    tab,
    backspace,
    insert,
    delete,
    right,
    left,
    down,
    up,
    page_up,
    page_down,
    home,
    end,
    caps_lock,
    scroll_lock,
    num_lock,
    print_screen,
    pause,
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
    f13,
    f14,
    f15,
    f16,
    f17,
    f18,
    f19,
    f20,
    f21,
    f22,
    f23,
    f24,
    f25,
    kp_0,
    kp_1,
    kp_2,
    kp_3,
    kp_4,
    kp_5,
    kp_6,
    kp_7,
    kp_8,
    kp_9,
    kp_decimal,
    kp_divide,
    kp_multiply,
    kp_subtract,
    kp_add,
    kp_enter,
    kp_equal,
    left_shift,
    left_control,
    left_alt,
    left_super,
    right_shift,
    right_control,
    right_alt,
    right_super,
    menu,
};

pub const MouseButton = enum(u8) {
    left,
    right,
    middle,
    four,
    five,
    six,
    seven,
    eight,
};

///Represents the state of any type of button or key
pub const ButtonAction = enum(u8) {
    /// The button was released.
    release,
    /// The button was pressed.
    press,
    /// The key was held down.
    down,
};

///Represents a user facing, presentable display surface
pub const Surface = opaque {};

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

const backend = @import("glaze/glaze_glfw.zig");
const std = @import("std");
