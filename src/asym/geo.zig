//! Immediate mode geometry

pub const Context = struct {
    draw_data: [2]Scene = @splat(.{}),
    active_draw_data: u32 = 0,
    id_stack: std.ArrayList(InstanceId) = .empty,
    arena: std.heap.ArenaAllocator,

    pub fn init(gpa: std.mem.Allocator) Context {
        return .{
            .arena = .init(gpa),
        };
    }

    pub fn deinit(context: *Context) void {
        context.arena.deinit();
    }

    pub fn beginSubmission(self: *Context) void {
        self.draw_data[self.active_draw_data].clear();
        self.id_stack.clearRetainingCapacity();
    }

    pub fn endSubmission(self: *Context) []Scene.View {
        defer {
            self.active_draw_data += 1;
            self.active_draw_data = self.active_draw_data % 2;
        }

        return self.draw_data[self.active_draw_data].views.items;
    }
};

pub const Colour = packed struct(u32) {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub const red: Colour = .{ .r = 255, .g = 0, .b = 0 };
    pub const green: Colour = .{ .r = 0, .g = 255, .b = 0 };
    pub const blue: Colour = .{ .r = 0, .g = 0, .b = 255 };
};

///Represents the full scene produced from a set of commands
pub const Scene = struct {
    views: std.ArrayList(View) = .empty,
    instance_ids_by_type: std.EnumArray(PrimitiveType, std.ArrayList(InstanceId)) = .initFill(.empty),
    transforms_by_type: std.EnumArray(PrimitiveType, std.ArrayList(AffineTransform3D)) = .initFill(.empty),
    materials_by_type: std.EnumArray(PrimitiveType, std.ArrayList(Material)) = .initFill(.empty),
    vertex_positions_3d: std.ArrayList([3]f32) = .empty,
    vertex_positions_2d: std.ArrayList([2]f32) = .empty,
    vertex_normals: std.ArrayList([3]f16) = .empty,
    vertex_colours: std.ArrayList(Colour) = .empty,
    indices: std.ArrayList(u16) = .empty,

    ///Clear the scene
    pub fn clear(self: *Scene) void {
        for (&self.instance_ids_by_type.values) |*val| {
            val.clearRetainingCapacity();
        }
        for (&self.transforms_by_type.values) |*val| {
            val.clearRetainingCapacity();
        }
        for (&self.materials_by_type.values) |*val| {
            val.clearRetainingCapacity();
        }
        self.vertex_positions_3d.clearRetainingCapacity();
        self.vertex_positions_2d.clearRetainingCapacity();
        self.vertex_colours.clearRetainingCapacity();
        self.vertex_normals.clearRetainingCapacity();
        self.indices.clearRetainingCapacity();
        self.views.clearRetainingCapacity();
    }

    pub const View = struct {
        view: [4][4]f32,
        projection: [4][4]f32,
        scissor: [4]f32,
        ///Indexed by @backingInt(draw_state)
        draws_by_state: [8]Group = @splat(.{}),
        draw_group_count: usize = 0,

        ///Returns an iterator which iterates the draw groups and clears them afterwards
        pub fn iterate(self: *const View) Iterator {
            return .{
                .group_index = 0,
                .view = self,
            };
        }

        pub fn drawGroup(self: *View, draw_state: PipelineState) *Group {
            self.draw_group_count = @max(self.draw_group_count, @backingInt(draw_state));

            return &self.draws_by_state[@backingInt(draw_state)];
        }
    };

    pub const Group = struct {
        parameters_by_type: std.EnumArray(PrimitiveType, std.ArrayList(f32)) = .initFill(.empty),
        draws_by_type: std.EnumArray(PrimitiveType, std.ArrayList(DrawCommand)) = .initFill(.empty),

        pub fn clear(draw_group: *Group) void {
            for (draw_group.draws_by_type.values) |*val| {
                val.clearRetainingCapacity();
            }

            for (draw_group.parameters_by_type.values) |*val| {
                val.clearRetainingCapacity();
            }
        }

        pub fn slice(draw_group: *const Group) GroupSlice {
            var parameters_by_type: std.EnumArray(PrimitiveType, []const f32) = .initFill(&.{});
            var draws_by_type: std.EnumArray(PrimitiveType, []const DrawCommand) = .initFill(&.{});

            inline for (
                comptime std.meta.fieldNames(PrimitiveType),
                draw_group.parameters_by_type.values,
                draw_group.draws_by_type.values,
            ) |enum_name, val, draw| {
                const prim_type = @field(PrimitiveType, enum_name);

                parameters_by_type.set(prim_type, val.items);
                draws_by_type.set(prim_type, draw.items);
            }

            return .{
                .parameters_by_type = parameters_by_type,
                .draws_by_type = draws_by_type,
            };
        }
    };

    pub const GroupSlice = struct {
        parameters_by_type: std.EnumArray(PrimitiveType, []const f32),
        draws_by_type: std.EnumArray(PrimitiveType, []const DrawCommand),

        pub fn empty(self: GroupSlice) bool {
            for (self.draws_by_type.values) |val| {
                if (val.len != 0) {
                    return false;
                }
            }

            return true;
        }
    };

    pub const Iterator = struct {
        view: *const View,
        group_index: u32,

        pub fn next(iter: *Iterator) ?struct { PipelineState, GroupSlice } {
            defer iter.group_index += 1;

            if (iter.group_index >= iter.view.draw_group_count) {
                return null;
            }

            var slice = iter.view.draws_by_state[iter.group_index].slice();

            while (slice.empty()) {
                iter.group_index += 1;

                if (iter.group_index == 8) {
                    return null;
                }
                slice = iter.view.draws_by_state[iter.group_index].slice();
            }

            return .{
                @bitCast(iter.group_index),
                slice,
            };
        }
    };
};

pub const PrimitiveType = enum(u32) {
    triangle_list_3d,
    triangle_list_2d,
    line_list_2d,
    line_list_3d,
    box,
    line,
    sphere,
    circle,
    text,
    bezier_curve,
    plane_segment,
};

///Meant to be passed to a graphics api via *DrawIndirect()
pub const DrawCommand = extern struct {
    vertex_count: u32,
    instance_count: u32,
    first_vertex: u32,
    base_instance: u32,

    primitive_type: PrimitiveType,
    materials_begin: u32,
    transforms_begin: u32,
    parameters_begin: u32,
    instance_ids_begin: u32,
};

pub const Material = extern struct {
    colour: Colour,
};

///Represents a handle to a pipeline that the renderer will use
pub const PipelineHandle = enum(u64) {
    null = 0,
    ///The default rendering path that the renderer must provide
    default = std.math.maxInt(u64),
    _,
};

///Represents a handle to a bitmap image that the renderer will use
pub const ImageHandle = enum(u64) {
    null = 0,
    _,
};

pub const PipelineState = packed struct(u32) {
    depth_testing: bool = false,
    filled: bool = true,
    transparency: bool = false,
    _: u29 = 0,
};

///Represents a frame stable id of a draw primitive or group of draws
pub const InstanceId = enum(u32) {
    _,

    pub fn fromSrc(comptime src: std.lang.SourceLocation) InstanceId {
        const hash = std.hash.Crc32.hash(
            src.file ++ src.fn_name ++ src.module ++ std.fmt.comptimePrint("{}:{}", .{
                src.line,
                src.column,
            }),
        );

        return @fromBackingInt(hash);
    }

    pub fn fromSrcIndexed(comptime src: std.lang.SourceLocation, index: usize) InstanceId {
        const draw_id: InstanceId = .fromSrc(src);

        return draw_id.indexed(index);
    }

    pub fn indexed(id: InstanceId, index: usize) InstanceId {
        const bytes: [12]u8 = @bitCast(packed struct { id: InstanceId, index: usize }{
            .id = id,
            .index = index,
        });

        return @fromBackingInt(std.hash.Crc32.hash(&bytes));
    }
};

var current_context: ?*Context = null;

pub fn setCurrentContext(context: *Context) void {
    current_context = context;
}

pub fn beginView(
    view: [4][4]f32,
    projection: [4][4]f32,
    scissor: [4]f32,
) void {
    current_context.?.draw_data[current_context.?.active_draw_data].views.append(current_context.?.arena.allocator(), .{
        .view = view,
        .projection = projection,
        .scissor = scissor,
    }) catch @panic("oom");
    std.debug.assert(current_context.?.draw_data[current_context.?.active_draw_data].views.items.len == 1);

    for (&current_context.?.draw_data[current_context.?.active_draw_data].views.items[0].draws_by_state) |*draw_group| {
        draw_group.* = .{
            .parameters_by_type = .initFill(.empty),
        };

        for (&draw_group.parameters_by_type.values) |*params| {
            params.items = &.{};
            std.debug.print("params.len = {}\n", .{params.items.len});
            std.debug.assert(params.items.len == 0);
        }
    }
}

pub fn endView() void {}

pub fn pushId(draw_id: InstanceId) void {
    current_context.?.id_stack.append(current_context.?.arena, draw_id) catch @panic("oom");
}

pub fn popId() void {
    current_context.?.id_stack.pop();
}

pub fn line(
    options: struct {
        draw_state: PipelineState = .{},
    },
) bool {
    _ = options; // autofix
    return false;
}

pub fn box(
    options: struct {
        draw_state: PipelineState = .{},
        transform: AffineTransform3D,
        bounds: [3]f32,
    },
) bool {
    _ = options; // autofix
    return false;
}

pub const TextType = enum(u32) {
    ///Could be any arbitrary text format
    unclassified,
    ///Plain ascii
    ascii,
    ///Ascii with escape sequences
    ascii_escaped,
    /// Unicode utf8
    utf8,
    /// Unicode utf16
    utf16,
};

///Describes the type face of text
pub const TextTypeFace = struct {};

pub const TextTypeFaceHandle = enum(u32) {
    null = 0,
    default = std.math.maxInt(u32),
    _,
};

///Sets the default type face used for text instances
pub fn setDefaultStateTextTypeFace(
    type_face: TextTypeFaceHandle,
) void {
    _ = type_face; // autofix
}

///Computes the text size of a given string
pub fn textComputeSize(
    options: struct {
        string: []const u8,
        type_face: TextTypeFaceHandle = .default,
        type: TextType = .utf8,
    },
) void {
    _ = options; // autofix
}

pub const TextLineWrapping = enum(u32) {
    dont_wrap,
    wrap,
};

///Draws a rect containing text defined by options.string
pub fn text(
    options: struct {
        instance_id: InstanceId,
        draw_state: PipelineState = .{},
        string: []const u8,
        type: TextType = .utf8,
        type_face: TextTypeFaceHandle = .default,
        line_wrapping: TextLineWrapping = .wrap,
        bounds: [3]f32,
    },
) void {
    _ = options; // autofix
}

pub fn sphere(
    options: struct {
        draw_state: PipelineState = .{},
        interactable: ?InstanceId = null,
        transform: AffineTransform3D,
        colour: Colour,
        radius: f32,
    },
) bool {
    const context = current_context.?;
    const view = current_context.?.draw_data[current_context.?.active_draw_data].views.last().?;
    const group = view.drawGroup(options.draw_state);

    group.spheres.append(context.arena.allocator(), .{
        .radius = options.radius,
        .draw = .{
            .material = .{
                .colour = options.colour,
            },
        },
    }) orelse return false;

    return true;
}

pub fn circle(
    options: struct {
        id: InstanceId,
        draw_state: PipelineState = .{},
        transform: AffineTransform3D,
        colour: Colour,
        radius: f32,
        ///Segment angle in turns
        segment_angle: f32 = 1,
    },
) bool {
    const context = current_context.?;
    const scene = &current_context.?.draw_data[current_context.?.active_draw_data];
    const view = scene.views.last().?;
    const group = view.drawGroup(options.draw_state);

    const materials_begin: u32 = @intCast(scene.materials_by_type.get(.circle).items.len);
    const transforms_begin: u32 = @intCast(scene.transforms_by_type.get(.circle).items.len);
    const parameters_begin: u32 = @intCast(group.parameters_by_type.get(.circle).items.len);
    const instance_ids_begin: u32 = @intCast(scene.instance_ids_by_type.get(.circle).items.len);

    scene.transforms_by_type.getPtr(.circle).append(context.arena.allocator(), options.transform) catch @panic("oom");
    scene.materials_by_type.getPtr(.circle).append(context.arena.allocator(), .{ .colour = options.colour }) catch @panic("oom");
    group.parameters_by_type.getPtr(.circle).append(context.arena.allocator(), options.radius) catch @panic("oom");
    scene.instance_ids_by_type.getPtr(.circle).append(context.arena.allocator(), options.id) catch @panic("oom");

    scene.instance_ids_by_type.getPtr(.circle).append(
        context.arena.allocator(),
        options.id,
    ) catch @panic("oom");

    if (group.draws_by_type.getPtr(.circle).items.len == 0) {
        group.draws_by_type.getPtr(.circle).append(context.arena.allocator(), .{
            .instance_count = 1,
            .vertex_count = 3,
            .base_instance = 0,
            .first_vertex = 0,
            .primitive_type = .circle,
            .materials_begin = materials_begin,
            .transforms_begin = transforms_begin,
            .parameters_begin = parameters_begin,
            .instance_ids_begin = instance_ids_begin,
        }) catch return false;
    } else {
        const circle_draw = group.draws_by_type.getPtr(.circle).last().?;

        circle_draw.instance_count += 1;
    }

    return true;
}

pub fn planeSegment() void {}

pub fn bezierCurve() void {}

pub const AffineTransform3D = extern struct {
    position: [3]f32 = @splat(0),
    ///Uniform scale
    scale: f32 = 1,
    ///Quaternion rotation
    rotation: [4]f32 = .{ 0, 0, 0, 1 },

    pub const identity: AffineTransform3D = .{
        .position = @splat(0),
        .scale = 1,
        .rotation = .{ 0, 0, 0, 1 },
    };
};

pub const AffineTransform2D = extern struct {
    position: [2]f32 = @splat(0),
    rotation_scale: [2]f32 = .{ 1, 0 },

    pub const identity: AffineTransform3D = .{
        .position = @splat(0),
        .rotation_scale = .{ 1, 0 },
    };
};

const std = @import("std");
