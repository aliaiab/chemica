//! Immediate mode graphical user interface built on top of asym.geo

pub const Context = struct {};

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

pub const Layout = struct {
    anchors: std.ArrayList(Anchor) = .empty,

    pub fn init(
        arena: std.mem.Allocator,
        root_bounds: [2]f32,
    ) !Layout {
        var layout: Layout = .{};

        try layout.anchors.append(arena, .{
            .transform = .identity,
            .bounds = root_bounds,
        });

        return layout;
    }

    pub fn createAnchor(
        layout: *Layout,
        parent_anchor: AnchorIndex,
        anchor_data: Anchor,
        arena: std.mem.Allocator,
    ) !AnchorIndex {
        const anchor_index: AnchorIndex = @fromBackingInt(@intCast(layout.anchors.items.len));

        var actual_anchor_data: Anchor = anchor_data;

        actual_anchor_data.parent = parent_anchor;

        try layout.anchors.append(arena, anchor_data);

        var parent_anchor_data: *Anchor = layout.anchors.items[@backingInt(parent_anchor)];

        try parent_anchor_data.children.append(arena, anchor_index);

        return anchor_index;
    }

    pub fn anchorData(layout: Layout, anchor: AnchorIndex) *Anchor {
        return &layout.anchors.items[@backingInt(anchor)];
    }

    ///Extends the anchor bounds by extending to contain the extension bounds
    pub fn extend(
        layout: *Layout,
        anchor: AnchorIndex,
        position: [2]f32,
        bounds: [2]f32,
    ) void {
        _ = position; // autofix
        _ = layout; // autofix
        _ = anchor; // autofix
        _ = bounds; // autofix

    }

    pub fn resolveTransform(
        layout: Layout,
        anchor: AnchorIndex,
    ) geo.AffineTransform3D {
        const parent_transform = layout.resolveTransform(layout.anchorData(anchor).parent);
        const transform = layout.anchorData(anchor).transform;

        return .mul(parent_transform, transform);
    }

    pub const Anchor = struct {
        transform: geo.AffineTransform3D,
        bounds: [2]f32,
        parent: AnchorIndex = .root,
        children: std.ArrayList(AnchorIndex) = .empty,
    };

    pub const AnchorIndex = enum(u32) {
        root = 0,
        null = std.math.maxInt(u32),
        _,
    };
};

const gui = @This();
const geo = @import("geo.zig");
const std = @import("std");
