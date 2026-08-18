//! Immediate mode geometry

pub const Context = struct {
    draw_data: [2]Scene = @splat(.{}),
    active_draw_data: u32 = 0,
    id_stack: std.ArrayList(InstanceId) = .empty,
    type_faces: std.ArrayList(TextTypeFaceData) = .empty,
    default_type_face: TextTypeFaceHandle = .null,
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

    pub fn endSubmission(self: *Context) *Scene {
        defer {
            self.active_draw_data += 1;
            self.active_draw_data = self.active_draw_data % 2;
        }

        return &self.draw_data[self.active_draw_data];
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
    pub const white: Colour = .{ .r = 255, .g = 255, .b = 255, .a = 255 };
};

///Represents the full scene produced from a set of commands
pub const Scene = struct {
    views: std.ArrayList(View) = .empty,
    instance_ids_by_type: std.EnumArray(PrimitiveType, std.ArrayList(InstanceId)) = .initFill(.empty),
    transforms_by_type: std.EnumArray(PrimitiveType, std.ArrayList(AffineTransform3D)) = .initFill(.empty),
    materials_by_type: std.EnumArray(PrimitiveType, std.ArrayList(Material)) = .initFill(.empty),
    text_buffer: std.ArrayList(u8) = .empty,
    text_buffer_entires: std.ArrayList([]const u8) = .empty,
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
        self.text_buffer.clearRetainingCapacity();
        self.text_buffer_entires.clearRetainingCapacity();
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
        draws_by_state: [64]Group = @splat(.{}),
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
        text_typefaces: std.ArrayList(TextTypeFaceHandle) = .empty,

        pub fn clear(draw_group: *Group) void {
            for (draw_group.draws_by_type.values) |*val| {
                val.clearRetainingCapacity();
            }

            for (draw_group.parameters_by_type.values) |*val| {
                val.clearRetainingCapacity();
            }

            draw_group.text_typefaces.clearRetainingCapacity();
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
                .text_typefaces = draw_group.text_typefaces.items,
            };
        }
    };

    pub const GroupSlice = struct {
        parameters_by_type: std.EnumArray(PrimitiveType, []const f32),
        draws_by_type: std.EnumArray(PrimitiveType, []const DrawCommand),
        text_typefaces: []const TextTypeFaceHandle,

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
    face_culling: bool = false,
    face_culling_front_face: bool = false,
    transparency: bool = false,
    _: u27 = 0,
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
        id: InstanceId,
        draw_state: PipelineState = .{},
        colour: Colour,
        transform: AffineTransform3D,
        bounds: [3]f32,
    },
) bool {
    const context = current_context.?;
    const scene = &current_context.?.draw_data[current_context.?.active_draw_data];
    const view = scene.views.last().?;
    const group = view.drawGroup(options.draw_state);

    const primitive_type: PrimitiveType = .box;

    const materials_begin: u32 = @intCast(scene.materials_by_type.get(primitive_type).items.len);
    const transforms_begin: u32 = @intCast(scene.transforms_by_type.get(primitive_type).items.len);
    const parameters_begin: u32 = @intCast(group.parameters_by_type.get(primitive_type).items.len);
    const instance_ids_begin: u32 = @intCast(scene.instance_ids_by_type.get(primitive_type).items.len);

    scene.transforms_by_type.getPtr(primitive_type).append(context.arena.allocator(), options.transform) catch @panic("oom");
    scene.materials_by_type.getPtr(primitive_type).append(context.arena.allocator(), .{ .colour = options.colour }) catch @panic("oom");
    group.parameters_by_type.getPtr(primitive_type).append(context.arena.allocator(), undefined) catch @panic("oom");
    scene.instance_ids_by_type.getPtr(primitive_type).append(context.arena.allocator(), options.id) catch @panic("oom");

    scene.instance_ids_by_type.getPtr(primitive_type).append(
        context.arena.allocator(),
        options.id,
    ) catch @panic("oom");

    if (group.draws_by_type.getPtr(primitive_type).items.len == 0) {
        group.draws_by_type.getPtr(primitive_type).append(context.arena.allocator(), .{
            .instance_count = 1,
            .vertex_count = 6,
            .base_instance = 0,
            .first_vertex = 0,
            .primitive_type = primitive_type,
            .materials_begin = materials_begin,
            .transforms_begin = transforms_begin,
            .parameters_begin = parameters_begin,
            .instance_ids_begin = instance_ids_begin,
        }) catch return false;
    } else {
        const circle_draw = group.draws_by_type.getPtr(primitive_type).last().?;

        circle_draw.instance_count += 1;
    }

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
pub const TextTypeFaceData = struct {
    codepoints_to_glyph: std.AutoArrayHashMapUnmanaged(u21, Glyph),

    pub const Glyph = struct {
        aspect_ratio: f32,
        advance: f32,
        bearing_x: f32,
        bearing_y: f32,
    };
};

pub const TextTypeFaceHandle = enum(u32) {
    null = 0,
    default = std.math.maxInt(u32),
    _,
};

///Sets the default type face used for text instances
pub fn setDefaultStateTextTypeFace(
    type_face: TextTypeFaceHandle,
) void {
    current_context.?.default_type_face = type_face;
}

///Computes the text size of a given string
pub fn textComputeSize(
    options: struct {
        string: []const u8,
        type_face: TextTypeFaceHandle = .default,
        type: TextType = .utf8,
    },
) [2]f32 {
    const context = current_context.?;

    const type_face = &context.type_faces.items[@backingInt(context.default_type_face)];
    _ = type_face; // autofix
    var iter: std.mem.SplitIterator(u8, .sequence) = .{
        .buffer = options.string,
        .delimiter = "\n",
        .index = 0,
    };

    var width: f32 = 0;
    var height: f32 = 0;

    while (iter.next()) |text_line| {
        width = @max(width, @as(f32, @floatFromInt(text_line.len)));

        height += 1;
    }

    return .{ width, height };
}

pub fn textComputeSizeAndType(
    options: struct {
        string: []const u8,
        type_face: TextTypeFaceHandle = .default,
    },
) struct { [2]f32, TextType } {
    _ = options; // autofix
    return undefined;
}

pub const TextFormatting = packed struct(u32) {
    ///Enables terminal escape codes
    colour_escape_codes: bool = true,
    wrapping: bool = true,
    _: u30 = 0,
};

pub const TextBounds = union(enum) {
    ///Size based on the text itself
    auto,
    aabb: [3]f32,
};

///Draws a rect containing text defined by options.string
pub fn text(
    options: struct {
        id: InstanceId,
        draw_state: PipelineState = .{},
        background_colour: Colour,
        foreground_colour: Colour,
        string: []const u8,
        type: TextType = .utf8,
        type_face: TextTypeFaceHandle = .default,
        formatting: TextFormatting = .{},
        transform: AffineTransform3D,
        bounds: TextBounds = .auto,
    },
) void {
    const context = current_context.?;
    const scene = &current_context.?.draw_data[current_context.?.active_draw_data];
    const view = scene.views.last().?;
    const group = view.drawGroup(options.draw_state);

    const primitive_type: PrimitiveType = .text;

    const materials_begin: u32 = @intCast(scene.materials_by_type.get(primitive_type).items.len);
    const transforms_begin: u32 = @intCast(scene.transforms_by_type.get(primitive_type).items.len);
    const parameters_begin: u32 = @intCast(group.parameters_by_type.get(primitive_type).items.len);
    const instance_ids_begin: u32 = @intCast(scene.instance_ids_by_type.get(primitive_type).items.len);

    const typeface = if (options.type_face == .default) context.default_type_face else options.type_face;

    group.text_typefaces.append(context.arena.allocator(), typeface) catch @panic("oom");

    const text_buffer_begin: u32 = @intCast(scene.text_buffer.items.len);

    scene.text_buffer.appendSlice(context.arena.allocator(), options.string) catch @panic("oom");

    const text_buffer = scene.text_buffer.items[text_buffer_begin .. text_buffer_begin + options.string.len];

    scene.text_buffer_entires.append(context.arena.allocator(), text_buffer) catch @panic("");

    const bounds: [2]f32 = if (options.bounds == .aabb) options.bounds.aabb[0..2].* else textComputeSize(.{
        .string = options.string,
        .type = options.type,
        .type_face = typeface,
    });

    scene.transforms_by_type.getPtr(primitive_type).append(context.arena.allocator(), options.transform) catch @panic("oom");
    scene.materials_by_type.getPtr(primitive_type).append(context.arena.allocator(), .{ .colour = options.foreground_colour }) catch @panic("oom");
    group.parameters_by_type.getPtr(primitive_type).appendSlice(context.arena.allocator(), &bounds) catch @panic("oom");
    scene.instance_ids_by_type.getPtr(primitive_type).append(context.arena.allocator(), options.id) catch @panic("oom");

    scene.instance_ids_by_type.getPtr(primitive_type).append(
        context.arena.allocator(),
        options.id,
    ) catch @panic("oom");

    if (group.draws_by_type.getPtr(primitive_type).items.len == 0) {
        group.draws_by_type.getPtr(primitive_type).append(context.arena.allocator(), .{
            .instance_count = 1,
            .vertex_count = 6,
            .base_instance = 0,
            .first_vertex = 0,
            .primitive_type = primitive_type,
            .materials_begin = materials_begin,
            .transforms_begin = transforms_begin,
            .parameters_begin = parameters_begin,
            .instance_ids_begin = instance_ids_begin,
        }) catch return;
    } else {
        const circle_draw = group.draws_by_type.getPtr(primitive_type).last().?;

        circle_draw.instance_count += 1;
    }
}

pub fn sphere(
    options: struct {
        id: InstanceId,
        draw_state: PipelineState = .{},
        transform: AffineTransform3D,
        colour: Colour,
        radius: f32,
    },
) void {
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
    });
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
) void {
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
        }) catch @panic("unreachable");
    } else {
        const circle_draw = group.draws_by_type.getPtr(.circle).last().?;

        circle_draw.instance_count += 1;
    }
}

pub fn planeSegment() void {}

pub fn bezierCurve() void {}

pub const AffineTransform3D = amath.AffineTransform(f32, 3);
pub const AffineTransform2D = extern struct {
    position: [2]f32 = @splat(0),
    rotation_scale: [2]f32 = .{ 1, 0 },

    pub const identity: AffineTransform3D = .{
        .position = @splat(0),
        .rotation_scale = .{ 1, 0 },
    };
};

const amath = @import("lib").math;
const std = @import("std");
