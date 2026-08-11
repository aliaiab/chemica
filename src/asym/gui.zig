//! Immediate mode graphical user interface built on top of asym.geo

pub const WidgetId = enum(u32) {
    _,

    pub fn fromSrc(source: std.lang.SourceLocation) WidgetId {
        _ = source; // autofix
        return undefined;
    }
};

pub const WindowOptions = struct {
    title: []const u8,
};

pub const Widget = struct {
    pub fn end(_: Widget) void {
        geo.popId();
    }
};

pub fn widget(id: WidgetId) Widget {
    geo.pushId(@bitCast(id));
    return .{};
}

pub const Window = struct {
    widget_handle: Widget,

    pub fn deinit(self: Window) void {
        self.widget_handle.end();
    }
};

///A floating window
///Must call Window.deinit() to end the window
pub fn window(
    id: WidgetId,
    options: WindowOptions,
) ?Window {
    const widget_handle = gui.widget(id);
    _ = options; // autofix
    return .{
        .widget_handle = widget_handle,
    };
}

pub fn button(id: WidgetId) bool {
    const widget_handle = gui.widget(id);
    defer widget_handle.end();

    return false;
}

pub fn editValue(id: WidgetId, ptr: anytype) bool {
    _ = id; // autofix
    _ = ptr; // autofix
    return false;
}

pub fn demoWindow(id: WidgetId) void {
    const widget_group = gui.widget(id);
    defer widget_group.end();

    if (gui.window(.fromSrc(@src()), .{
        .title = "Demo Window",
    })) |wind| {
        defer wind.deinit();

        if (gui.button(.fromSrc(@src()))) {
            //Button pressed!
        }

        var float: f32 = 0.5;

        _ = gui.editValue(.fromSrc(@src()), &float, .{});
    }
}

pub const layout = struct {
    pub fn anchor() Anchor {
        return .{};
    }

    pub const Anchor = struct {
        pub fn deinit(self: Anchor) void {
            _ = self; // autofix
        }
    };
};

const gui = @This();
const geo = @import("geo.zig");
const std = @import("std");

