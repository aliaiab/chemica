//! Hand maintained imgui bindings

pub fn createContext(
    options: struct {},
) *Context {
    _ = options; // autofix
    return @ptrCast(cimgui.ImGui_CreateContext(null));
}

pub fn getIO() *IO {
    return @ptrCast(cimgui.ImGui_GetIO());
}

pub fn showDemoWindow(options: struct {}) void {
    _ = options; // autofix
    cimgui.ImGui_ShowDemoWindow(null);
}

pub fn isKeyDown(key: c_int) bool {
    return cimgui.ImGui_IsKeyDown(key);
}

pub fn isKeyPressed(key: c_int) bool {
    return cimgui.ImGui_IsKeyPressed(key);
}

pub fn isAnyItemActive() bool {
    return cimgui.ImGui_IsAnyItemActive();
}

pub fn dockSpace(
    id: Id,
    options: struct {},
) void {
    _ = options; // autofix
    _ = cimgui.ImGui_DockSpace(@bitCast(id.value), .{ .x = 0, .y = 0 }, 0, null);
}

pub fn separator(
    options: struct {},
) void {
    _ = options; // autofix
    cimgui.ImGui_Separator();
}

pub fn newLine() void {
    cimgui.ImGui_NewLine();
}

pub fn beginMenuBar() bool {
    return cimgui.ImGui_BeginMenuBar();
}

pub fn endMenuBar() void {
    cimgui.ImGui_EndMenuBar();
}

pub fn beginMenu(
    label: [:0]const u8,
    options: struct {
        enabled: bool = true,
    },
) bool {
    return cimgui.ImGui_BeginMenuEx(
        label.ptr,
        options.enabled,
    );
}

pub fn endMenu() void {
    return cimgui.ImGui_EndMenu();
}

pub const TreeNodeFlags = packed struct(u32) {
    selected: bool = false,
    framed: bool = false,
    allow_overlap: bool = false,
    no_tree_push_on_open: bool = false,
    no_auto_open_on_log: bool = false,
    default_open: bool = false,
    open_on_double_click: bool = false,
    open_on_arrow: bool = false,
    leaf: bool = false,
    bullet: bool = false,
    frame_padding: bool = false,
    span_avail_width: bool = false,
    span_full_width: bool = false,
    span_label_width: bool = false,
    span_all_columns: bool = false,
    label_span_all_columns: bool = false,
    nav_left_jumps_to_parent: bool = false,
    draw_lines_none: bool = false,
    draw_lines_full: bool = false,
    draw_lines_to_nodes: bool = false,
    _: u12 = 0,
};

pub fn treeNode(label: [:0]const u8, options: struct {
    flags: TreeNodeFlags = .{},
}) bool {
    return cimgui.ImGui_TreeNodeEx(
        label.ptr,
        @bitCast(options.flags),
    );
}

pub fn treePop() void {
    cimgui.ImGui_TreePop();
}

pub fn isItemClicked() bool {
    return cimgui.ImGui_IsItemClicked();
}

pub fn setDragDropPayload(
    value: anytype,
    options: struct {
        //If this is null then the type_string is @typeName(@TypeOf(value))
        type_string: ?[:0]const u8 = null,
    },
) bool {
    const @"type": [:0]const u8 = if (options.type_string) |type_string| type_string else @typeName(@TypeOf(value));

    return cimgui.ImGui_SetDragDropPayload(
        @"type".ptr,
        &value,
        @sizeOf(@TypeOf(value)),
        1,
    );
}

pub fn beginDragDropSource(options: struct {}) bool {
    _ = options; // autofix
    return cimgui.ImGui_BeginDragDropSource(0);
}

pub fn endDragDropSource() void {
    cimgui.ImGui_EndDragDropSource();
}

pub fn beginDragDropTarget() bool {
    return cimgui.ImGui_BeginDragDropTarget();
}

pub fn endDragDropTarget() void {
    cimgui.ImGui_EndDragDropTarget();
}

pub fn acceptDragDropTarget(
    comptime T: type,
    options: struct {
        //If this is null, the full type name of T is used as the type stirng
        type_string: ?[:0]const u8 = null,
    },
) ?T {
    const @"type": [:0]const u8 = if (options.type_string) |type_string| type_string else @typeName(T);

    const payload = cimgui.ImGui_AcceptDragDropPayload(@"type", 0);

    if (payload == null) {
        return null;
    }

    const ptr: *const T = @ptrCast(@alignCast(payload.*.Data));

    return ptr.*;
}

///Push and id value, can be an integer, pointer or a string
pub fn pushId(value: anytype) void {
    const T = @TypeOf(value);

    switch (@typeInfo(T)) {
        .int => |int_info| {
            const cint: c_int = switch (int_info.signedness) {
                .signed => @intCast(value),
                .unsigned => @intCast(value),
            };

            cimgui.ImGui_PushIDInt(cint);
        },
        .@"enum" => {
            const cint: c_int = @bitCast(@intFromEnum(value));

            cimgui.ImGui_PushIDInt(cint);
        },
        .pointer => {
            switch (T) {
                []const u8 => {
                    cimgui.ImGui_PushIDStr(value.ptr, value.ptr + value.len);
                },
                else => @compileError("type of value not supported for id creation!"),
            }
        },
        else => @compileError("type of value not supported for id creation!"),
    }
}

pub fn popId() void {
    cimgui.ImGui_PopID();
}

pub fn begin(
    name: [:0]const u8,
    options: struct {
        open: ?*bool = null,
        flags: WindowFlags = .{},
        size: ?[2]f32 = null,
    },
) bool {
    if (options.size) |size| {
        cimgui.ImGui_SetNextWindowSize(.{
            .x = size[0],
            .y = size[1],
        }, 1);
    }
    return cimgui.ImGui_Begin(name.ptr, options.open, @bitCast(options.flags));
}

pub fn end() void {
    return cimgui.ImGui_End();
}

pub fn setNextWindowBgAlpha(alpha: f32) void {
    return cimgui.ImGui_SetNextWindowBgAlpha(alpha);
}

pub fn sameLine(
    options: struct {
        offset_from_start_x: f32 = 0,
        spacing: f32 = -1,
    },
) void {
    return cimgui.ImGui_SameLineEx(options.offset_from_start_x, options.spacing);
}

pub fn text(
    comptime fmt: []const u8,
    args: anytype,
) void {
    var fmt_buffer: [1024]u8 = undefined;

    const formatted = std.fmt.bufPrint(&fmt_buffer, fmt, args) catch @panic("Format allocation failed!");

    textUnformatted(formatted);
}

pub fn textUnformatted(string: []const u8) void {
    cimgui.ImGui_TextUnformattedEx(string.ptr, string.ptr + string.len);
}

pub fn loadIniSettingsFromMemory(ini_data: []const u8) void {
    cimgui.ImGui_LoadIniSettingsFromMemory(ini_data.ptr, ini_data.len);
}

pub fn saveIniSettingsToDisk(file_name: [:0]const u8) void {
    cimgui.ImGui_SaveIniSettingsToDisk(file_name.ptr);
}

pub fn menuItem(label: [:0]const u8, options: struct {
    shortcut: ?[:0]const u8 = null,
    selected: bool = false,
    enabled: bool = true,
}) bool {
    return cimgui.ImGui_MenuItemEx(
        label.ptr,
        if (options.shortcut) |shortcut| shortcut.ptr else null,
        options.selected,
        options.enabled,
    );
}

pub fn openPopup(string: [:0]const u8) void {
    cimgui.ImGui_OpenPopup(string.ptr, 0);
}

pub fn selectable(string: [:0]const u8) bool {
    return cimgui.ImGui_Selectable(string.ptr);
}

pub fn beginPopup(string: [:0]const u8) bool {
    return cimgui.ImGui_BeginPopup(string.ptr, 0);
}

pub fn endPopup() void {
    cimgui.ImGui_EndPopup();
}

pub fn checkbox(
    label: [:0]const u8,
    value: *bool,
) bool {
    return cimgui.ImGui_Checkbox(label, value);
}

pub fn button(
    label: [:0]const u8,
    options: struct {
        size: [2]f32 = .{ 0, 0 },
        button_flags: ButtonFlags = .{},
    },
) bool {
    return cimgui.ImGui_ButtonEx(
        label.ptr,
        .{ .x = options.size[0], .y = options.size[1] },
    );
}

pub fn inputText(
    label: [:0]const u8,
    buffer: []u8,
    options: struct {},
) ?[]const u8 {
    _ = options; // autofix
    const edited = cimgui.ImGui_InputText(
        label.ptr,
        buffer.ptr,
        buffer.len,
        0,
    );

    if (!edited) {
        return null;
    }

    const buffer_end = std.mem.find(u8, buffer, &.{0}) orelse return buffer;

    return buffer[0..buffer_end];
}

pub fn plotLines(label: [:0]const u8, values: []const f32) void {
    cimgui.ImGui_PlotLinesEx(
        label.ptr,
        values.ptr,
        @intCast(values.len),
        0,
        "",
        std.math.floatMax(f32),
        std.math.floatMax(f32),
        .{ .x = 200, .y = 200 },
        @sizeOf(f32),
    );
}

pub fn combo(
    label: [:0]const u8,
    current_item: *usize,
    items: []const [*]const u8,
) bool {
    var current_item_i32: i32 = @intCast(current_item.*);

    const result = cimgui.ImGui_ComboChar(
        label.ptr,
        &current_item_i32,
        items.ptr,
        @intCast(items.len),
    );

    current_item.* = @intCast(current_item_i32);

    return result;
}

pub fn image(
    ///Must be a pointer sized value
    user_texture_id: anytype,
    image_size: [2]f32,
    options: struct {
        uv0: [2]f32 = .{ 0, 1 },
        uv1: [2]f32 = .{ 1, 0 },
        tint_col: [4]f32 = .{ 1, 1, 1, 1 },
        border_col: [4]f32 = .{ 0, 0, 0, 0 },
    },
) void {
    const imgui_texture_id = userImageToImTextureID(user_texture_id);

    return cimgui.ImGui_ImageEx(
        .{ ._TexID = imgui_texture_id },
        .{ .x = image_size[0], .y = image_size[1] },
        .{ .x = options.uv0[0], .y = options.uv0[1] },
        .{ .x = options.uv1[0], .y = options.uv1[1] },
    );
}

pub fn imageButton(
    id: Id,
    ///Must be a pointer sized value
    user_texture_id: anytype,
    image_size: [2]f32,
    options: struct {
        uv0: [2]f32 = .{ 0, 1 },
        uv1: [2]f32 = .{ 1, 0 },
        tint_col: [4]f32 = .{ 1, 1, 1, 1 },
        border_col: [4]f32 = .{ 0, 0, 0, 0 },
        flags: ButtonFlags = .{},
    },
) bool {
    const imgui_texture_id = userImageToImTextureID(user_texture_id);

    var str_id_buf: [128]u8 = undefined;

    const str_id = std.fmt.bufPrintZ(&str_id_buf, "0x{x}", .{id.value}) catch @panic("");

    return cimgui.ImGui_ImageButtonEx(
        str_id.ptr,
        .{ ._TexID = imgui_texture_id },
        .{ .x = image_size[0], .y = image_size[1] },
        .{ .x = options.uv0[0], .y = options.uv0[1] },
        .{ .x = options.uv1[0], .y = options.uv1[1] },
        .{ .x = options.border_col[0], .y = options.border_col[1], .z = options.border_col[2], .w = options.border_col[3] },
        .{ .x = options.tint_col[0], .y = options.tint_col[1], .z = options.tint_col[2], .w = options.tint_col[3] },
    );
}

pub fn dragValue(
    label: []const u8,
    comptime fmt: []const u8,
    value: anytype,
    options: DragScalarOptions(std.meta.Child(@TypeOf(value))),
) bool {
    _ = label; // autofix
    _ = fmt; // autofix
    _ = options; // autofix

}

pub fn dragFloat(
    label: []const u8,
    comptime fmt: []const u8,
    value: *f32,
    options: DragScalarOptions(f32),
) bool {
    return reimpls.dragScalar(
        f32,
        label,
        fmt,
        value,
        options,
    );
}

fn DragScalarOptions(comptime T: type) type {
    return struct {
        speed: T = if (@typeInfo(T) == .float) 0.1 else 1,
        value_min: T = 0,
        value_max: T = 0,
        flags: SliderFlags = .{},
    };
}

pub fn dragFloat3(
    label: [:0]const u8,
    comptime fmt: []const u8,
    value: [*]f32,
    options: DragScalarOptions(f32),
) bool {
    if (true) {
        return cimgui.ImGui_DragFloat3Ex(
            label.ptr,
            @ptrCast(value),
            options.speed,
            options.value_min,
            options.value_max,
            null,
            0,
        );
    }

    return dragScalarN(
        label,
        fmt,
        f32,
        value,
        3,
        options,
    );
}

fn dragScalarN(
    label: []const u8,
    comptime fmt: []const u8,
    comptime T: type,
    value: [*]T,
    comptime components: usize,
    options: DragScalarOptions(T),
) bool {
    if (true) return false;

    var value_change: bool = false;

    cimgui.ImGui_BeginGroup();
    pushId(label);
    cimgui.ImGui_PushMultiItemsWidths(
        @intCast(components),
        cimgui.ImGui_CalcItemWidth(),
    );

    for (0..components) |i| {
        pushId(i);

        if (i > 0) {
            sameLine(.{ .offset_from_start_x = 0, .spacing = 5 });
        }

        if (true) {
            const color_markers: [4]u32 = .{
                4279506160,
                4279562260,
                4293923860,
                4287401100,
            };

            cimgui.ImGui_SetNextItemColorMarker(color_markers[i]);
        }

        value_change |= reimpls.dragScalar(
            T,
            "",
            fmt,
            &value[i],
            options,
        );

        popId();
        cimgui.ImGui_PopItemWidth();
    }

    popId();

    const label_end = label.len;

    if (label_end != label.len) {
        sameLine(.{ .spacing = 5 });
        text("{s}", .{label});
    }

    cimgui.ImGui_EndGroup();

    return value_change;
}

pub fn colorEdit(
    label: [:0]const u8,
    colour: anytype,
    options: struct {},
) bool {
    _ = options; // autofix
    return cimgui.ImGui_ColorEdit4(label.ptr, @ptrCast(colour), 0);
}

pub fn newFrame() void {
    cimgui.ImGui_NewFrame();
}

pub fn endFrame() void {
    cimgui.ImGui_EndFrame();
}

pub fn render() void {
    cimgui.ImGui_Render();
}

pub fn getDrawData() *DrawData {
    return @ptrCast(cimgui.ImGui_GetDrawData());
}

pub fn dockspaceOverViewport(
    options: struct {},
) u32 {
    _ = options; // autofix
    return cimgui.ImGui_DockSpaceOverViewportEx(
        0,
        cimgui.ImGui_GetMainViewport(),
        cimgui.ImGuiDockNodeFlags_PassthruCentralNode,
        null,
    );
}

pub fn dockspace(dockspace_id: u32) u32 {
    return cimgui.ImGui_DockSpace(dockspace_id);
}

pub fn getStyle() *cimgui.ImGuiStyle {
    return @ptrCast(cimgui.ImGui_GetStyle());
}

pub fn getFrameHeightWithSpacing() f32 {
    return cimgui.ImGui_GetFrameHeightWithSpacing();
}

pub fn getScrollMaxY() f32 {
    return cimgui.ImGui_GetScrollMaxY();
}

pub fn setScrollY(scroll_y: f32) void {
    cimgui.ImGui_SetScrollY(scroll_y);
}

pub fn beginChild(
    name: [:0]const u8,
    options: struct {
        size: [2]f32,
        child_flags: i32 = 0,
        window_flags: WindowFlags = .{},
    },
) bool {
    return cimgui.ImGui_BeginChild(
        name.ptr,
        @bitCast(options.size),
        options.child_flags,
        @bitCast(options.window_flags),
    );
}

pub fn endChild() void {
    cimgui.ImGui_EndChild();
}

///An automatic value edit widget for any type
pub fn valueEdit(
    label: [:0]const u8,
    value: anytype,
    options: struct {
        naming_case: enum {
            snake,
            spaced_pascal,
        } = .spaced_pascal,
    },
) bool {
    const Type = std.meta.Child(@TypeOf(value));

    switch (@typeInfo(Type)) {
        .@"enum" => |enum_info| {
            const ptr_to_enum = @as([*]u8, @ptrCast(value));

            var items: [enum_info.fields.len][*]const u8 = undefined;

            inline for (enum_info.fields, 0..) |field, i| {
                items[i] = field.name.ptr;

                switch (options.naming_case) {
                    .spaced_pascal => {
                        items[i] = &snakeToSpacedPascalCase(field.name);
                    },
                    else => {},
                }
            }

            var current_item: usize = @as(usize, @intCast(ptr_to_enum[0]));

            if (combo(label, &current_item, &items)) {
                ptr_to_enum[0] = @as(u8, @intCast(current_item));

                return true;
            }

            return false;
        },
        else => {},
    }

    return false;
}

fn snakeToSpacedPascalCase(comptime str: []const u8) [str.len + 1]u8 {
    var result: [str.len + 1]u8 = [1]u8{0} ** (str.len + 1);

    var previous_char: u8 = 0;

    for (str, result[0..str.len]) |chr, *out_chr| {
        switch (chr) {
            '_' => out_chr.* = ' ',
            else => {
                if (previous_char == 0 or previous_char == '_') {
                    out_chr.* = std.ascii.toUpper(chr);
                } else {
                    out_chr.* = chr;
                }
            },
        }

        previous_char = chr;
    }

    return result;
}

pub const Id = packed struct(u32) {
    value: u32,

    pub fn fromStr(string: []const u8) Id {
        const value = cimgui.ImGui_GetIDStr(string.ptr, string.ptr + string.len);

        return .{ .value = value };
    }

    pub fn fromFmt(comptime fmt: []const u8, args: anytype) Id {
        var fmt_buffer: [256]u8 = undefined;

        const str_id = std.fmt.bufPrint(&fmt_buffer, fmt, args) catch @panic("Fmt allocation failed");

        return .fromStr(str_id);
    }
};

pub const WindowFlags = packed struct(u32) {
    no_title_bar: bool = false,
    no_resize: bool = false,
    no_move: bool = false,
    no_scroll_bar: bool = false,
    no_scroll_with_mouse: bool = false,
    no_collapse: bool = false,
    always_auto_resize: bool = false,
    no_background: bool = false,
    no_saved_settings: bool = false,
    no_mouse_inputs: bool = false,
    menu_bar: bool = false,
    horizontal_scroll_bar: bool = false,
    no_focus_on_appearing: bool = false,
    no_bring_to_front_on_focus: bool = false,
    always_vertical_scroll_bar: bool = false,
    always_horizontal_scroll_bar: bool = false,
    no_nav_inputs: bool = false,
    no_nav_focus: bool = false,
    unsaved_document: bool = false,
    no_docking: bool = false,
    nav_flattened: bool = false,
    child_window: bool = false,
    tooltip: bool = false,
    popup: bool = false,
    modal: bool = false,
    child_menu: bool = false,
    dock_node_host: bool = false,

    _: u5 = 0,

    pub const no_nav: WindowFlags = .{
        .no_nav_focus = true,
        .no_nav_inputs = true,
    };

    pub const no_decoration: WindowFlags = .{
        .no_resize = true,
        .no_title_bar = true,
        .no_scroll_bar = true,
        .no_collapse = true,
    };

    pub const no_inputs: WindowFlags = .{
        .no_nav_inputs = true,
        .no_nav_focus = true,
    };

    comptime {
        std.debug.assert(@as(u32, @bitCast(no_decoration)) == 43);
    }

    pub fn combine(flags: []const WindowFlags) WindowFlags {
        var result: u32 = 0;

        for (flags) |flag| {
            result |= @bitCast(flag);
        }

        return @bitCast(result);
    }
};

pub const ButtonFlags = packed struct(u32) {
    mouse_button_left: bool = true,
    mouse_button_rImGui_ht: bool = false,
    mouse_button_middle: bool = false,

    _: u29 = 0,
};

pub const SliderFlags = packed struct(u32) {
    always_clamp: bool = true,
    logarithmic: bool = false,
    no_round_to_format: bool = false,
    no_input: bool = false,

    _: u28 = 0,
};

pub const Context = cimgui.ImGuiContext;
pub const DrawData = cimgui.ImDrawData;
pub const IO = cimgui.ImGuiIO;

fn userImageToImTextureID(
    user_image: anytype,
) cimgui.ImTextureID {
    const UserImage = @TypeOf(user_image);

    const user_texture_integer: usize = blk: switch (@typeInfo(UserImage)) {
        .@"enum" => {
            break :blk @intFromEnum(user_image);
        },
        .@"struct" => |struct_info| {
            if (struct_info.layout != .@"packed") {
                @compileError("User image type must be a packed struct!");
            }

            break :blk @bitCast(user_image);
        },
        .int => user_image,
        .pointer => @intFromPtr(user_image),
        .optional => if (user_image) |img| @intFromPtr(img) else 0,
        else => @compileError("User image type not allowed! Must be a packed struct or enum"),
    };

    const imgui_tex_id: cimgui.ImTextureID = (user_texture_integer);

    return imgui_tex_id;
}

///Reimplementations in zImGui_ of some dear imgui functions
const reimpls = struct {
    pub fn dragScalar(
        comptime T: type,
        label: []const u8,
        comptime fmt: []const u8,
        p_data: *T,
        options: DragScalarOptions(T),
    ) bool {
        if (true) {
            if (T == f32) {
                return cimgui.ImGui_DragFloatEx(
                    label.ptr,
                    @ptrCast(p_data),
                    options.speed,
                    options.value_min,
                    options.value_max,
                    null,
                    0,
                );
            }
        }
        const DRAG_MOUSE_THRESHOLD_FACTOR = 0.50;
        _ = DRAG_MOUSE_THRESHOLD_FACTOR; // autofix
        const v_speed = options.speed;
        _ = v_speed; // autofix
        const p_min = options.value_min;
        const p_max = options.value_max;
        const flags: u32 = @bitCast(options.flags);

        const window: *ImGui_extras.ImGuiWindow = @ptrCast(@alignCast(cimgui.ImGui_GetCurrentWindow().?));

        const g: *cimgui.ImGuiContext = @ptrCast(cimgui.ImGui_GetCurrentContext().?);
        const style: *cimgui.ImGuiStyle = @ptrCast(cimgui.ImGui_GetStyle());
        const id = cimgui.ImGuiWindow_GetIDStrEx(@ptrCast(window), label.ptr, label.ptr + label.len);

        const w = cimgui.ImGui_CalcItemWidth();

        var label_size: cimgui.ImVec2 = undefined;

        label_size = cimgui.ImGui_CalcTextSizeEx(label.ptr, label.ptr + label.len, true, 0);
        const frame_bb: cimgui.ImRect = .{
            .Min = window.DC.CursorPos,
            .Max = cimgui.ImVec2{ .x = w + window.DC.CursorPos.x, .y = window.DC.CursorPos.y + label_size.y + style.FramePadding.y * 2.0 },
        };
        const total_bb: cimgui.ImRect = .{
            .Min = frame_bb.Min,
            .Max = cimgui.ImVec2{ .x = frame_bb.Max.x + if (label_size.x > 0.0) style.ItemInnerSpacing.x + label_size.x else 0.0, .y = frame_bb.Max.y },
        };

        const temp_input_allowed = (flags & cimgui.ImGuiSliderFlags_NoInput) == 0;

        cimgui.ImGui_ItemSizeImRectEx(total_bb, style.FramePadding.y);

        if (!cimgui.ImGui_ItemAddEx(total_bb, id, &frame_bb, if (temp_input_allowed) cimgui.ImGuiItemFlags_Inputable else 0))
            return false;

        const last_item_data: *cimgui.ImGuiItemFlags = @ptrCast(@alignCast(@as([*]u8, @ptrCast(g)) + 7808));

        const hovered = cimgui.ImGui_ItemHoverable(frame_bb, id, last_item_data.*);
        var temp_input_is_active = temp_input_allowed and cimgui.ImGui_TempInputIsActive(id);

        const active_id = cimgui.ImGui_GetActiveID();

        if (!temp_input_is_active) {
            const nav_activate_id: *c_uint = @ptrCast(@alignCast(@as([*]u8, @ptrCast(g)) + 8204));
            const nav_activate_flags: *c_uint = @ptrCast(@alignCast(@as([*]u8, @ptrCast(g)) + 8216));

            // Tabbing or CTRL-clicking on Drag turns it into an InputText
            const clicked = hovered and cimgui.ImGui_IsMouseClickedEx(0, false);
            const double_clicked = (hovered and cimgui.ImGui_IsMouseDoubleClicked(0) and cimgui.ImGui_TestKeyOwner(cimgui.ImGuiKey_MouseLeft, id));
            const make_active = (clicked or double_clicked or nav_activate_id.* == id);
            if (make_active and (clicked or double_clicked))
                cimgui.ImGui_SetKeyOwner(cimgui.ImGuiKey_MouseLeft, id, 0);
            if (make_active and temp_input_allowed) {
                if ((clicked and cimgui.ImGui_IsKeyDown(cimgui.ImGuiKey_LeftCtrl)) or double_clicked or (nav_activate_id.* == id and (nav_activate_flags.* & cimgui.ImGuiActivateFlags_PreferInput != 0))) {
                    temp_input_is_active = true;
                }
            }

            // (Optional) simple click (without moving) turns Drag into an InputText
            if (temp_input_allowed and !temp_input_is_active) {
                if (active_id == id and hovered and cimgui.ImGui_IsMouseReleased(0) and !cimgui.ImGui_IsMouseDragPastThreshold(0)) {
                    nav_activate_id.* = id;

                    nav_activate_flags.* = cimgui.ImGuiActivateFlags_PreferInput;
                    temp_input_is_active = true;
                }
            }

            const active_id_using_nav_dir_mask: *c_uint = @ptrCast(@alignCast(@as([*]u8, @ptrCast(g)) + 7728));

            if (make_active and !temp_input_is_active) {
                cimgui.ImGui_SetActiveID(id, @ptrCast(window));
                cimgui.ImGui_SetFocusID(id, @ptrCast(window));
                cimgui.ImGui_FocusWindow(@ptrCast(window), 0);
                active_id_using_nav_dir_mask.* = (1 << cimgui.ImGuiDir_Left) | (1 << cimgui.ImGuiDir_Right);
            }
        }

        if (temp_input_is_active) {
            return tempInputScalar(T, frame_bb, id, label, p_data, fmt, p_min, p_max);
        }

        // Draw frame
        const frame_col: u32 = cimgui.ImGui_GetColorU32Ex(if (active_id == id) cimgui.ImGuiCol_FrameBgActive else if (hovered) cimgui.ImGuiCol_FrameBgHovered else cimgui.ImGuiCol_FrameBg, 1);

        cimgui.ImGui_RenderNavHighlightEx(frame_bb, id, 0);
        cimgui.ImGui_RenderFrameEx(frame_bb.Min, frame_bb.Max, frame_col, true, style.FrameRounding);

        // Drag behavior
        // const value_changed = cimgui.ImGui_DragBehavior(id, data_type, p_data, v_speed, p_min, p_max, format, flags);
        const value_changed = false;

        if (value_changed)
            cimgui.ImGui_MarkItemEdited(id);

        var value_buf: [64]u8 = undefined;
        // const value_buf_end = value_buf + DataTypeFormatString(value_buf, value_buf.len, data_type, p_data, format);

        const value_buf_str = std.fmt.bufPrint(&value_buf, fmt, .{p_data.*}) catch @panic("");
        const value_buf_end = value_buf_str.ptr + value_buf_str.len;

        cimgui.ImGui_RenderTextClippedEx(
            frame_bb.Min,
            frame_bb.Max,
            &value_buf,
            value_buf_end,
            null,
            .{ .x = 0.5, .y = 0.5 },
            null,
        );

        if (label_size.x > 0.0) {
            cimgui.ImGui_RenderTextEx(
                .{ .x = frame_bb.Max.x + style.ItemInnerSpacing.x, .y = frame_bb.Min.y + style.FramePadding.y },
                label.ptr,
                label.ptr + label.len,
                true,
            );
        }

        return value_changed;
    }

    fn tempInputScalar(
        comptime ScalarType: type,
        bb: cimgui.ImRect,
        id: cimgui.ImGuiID,
        label: []const u8,
        p_data: *ScalarType,
        comptime fmt: []const u8,
        clamp_min: ?ScalarType,
        clamp_max: ?ScalarType,
    ) bool {
        var fmt_buf: [32]u8 = undefined;
        var data_buf: [32]u8 = undefined;

        _ = std.fmt.bufPrint(&fmt_buf, fmt, .{p_data.*}) catch @panic("");

        //TODO: trim blanks

        const flags = cimgui.ImGuiInputTextFlags_AutoSelectAll;

        var value_changed: bool = false;

        if (cimgui.ImGui_TempInputText(bb, id, label.ptr, &data_buf, data_buf.len, flags)) {
            // Backup old value
            const data_backup: ScalarType = p_data.*;

            p_data.* = std.fmt.parseFloat(ScalarType, &data_buf) catch p_data.*;

            if (clamp_min != null or clamp_max != null) {
                var actual_min: ScalarType = clamp_min orelse 0;
                var actual_max: ScalarType = clamp_max orelse 0;

                if (clamp_min != null and clamp_max != null) {
                    if (clamp_max.? < clamp_min.?) {
                        std.mem.swap(ScalarType, &actual_min, &actual_max);
                    }
                }

                if (clamp_max != null) {
                    p_data.* = @min(p_data.*, clamp_max.?);
                }

                if (clamp_min != null) {
                    p_data.* = @max(p_data.*, clamp_min.?);
                }
            }

            // Only mark as edited if new value is different
            value_changed = data_backup != p_data.*;

            if (value_changed) {
                cimgui.ImGui_MarkItemEdited(id);
            }
        }
        return value_changed;
    }
};

const ImGui_extras = struct {
    pub const ImGuiWindow = extern struct {
        Ctx: *cimgui.ImGuiContext,
        Name: [*c]u8,
        ID: cimgui.ImGuiID,
        Flags: cimgui.ImGuiWindowFlags,
        FlagsPreviousFrame: cimgui.ImGuiWindowFlags,
        ChildFlags: cimgui.ImGuiChildFlags,
        Viewport: [*c]cimgui.ImGuiViewportP,
        ViewportId: cimgui.ImGuiID,
        ViewportPos: cimgui.ImVec2,
        ViewportAllowPlatformMonitorExtend: c_int,
        Pos: cimgui.ImVec2,
        Size: cimgui.ImVec2,
        SizeFull: cimgui.ImVec2,
        ContentSize: cimgui.ImVec2,
        ContentSizeIdeal: cimgui.ImVec2,
        ContentSizeExplicit: cimgui.ImVec2,
        WindowPadding: cimgui.ImVec2,
        WindowRounding: f32,
        WindowBorderSize: f32,
        DecoOuterSizeX1: f32,
        DecoOuterSizeY1: f32,
        DecoOuterSizeX2: f32,
        DecoOuterSizeY2: f32,
        DecoInnerSizeX1: f32,
        DecoInnerSizeY1: f32,
        NameBufLen: c_int,
        MoveId: cimgui.ImGuiID,
        TabId: cimgui.ImGuiID,
        ChildId: cimgui.ImGuiID,
        Scroll: cimgui.ImVec2,
        ScrollMax: cimgui.ImVec2,
        ScrollTarget: cimgui.ImVec2,
        ScrollTargetCenterRatio: cimgui.ImVec2,
        ScrollTargetEdgeSnapDist: cimgui.ImVec2,
        ScrollbarSizes: cimgui.ImVec2,
        ScrollbarX: bool,
        ScrollbarY: bool,
        ViewportOwned: bool,
        Active: bool,
        WasActive: bool,
        WriteAccessed: bool,
        Collapsed: bool,
        WantCollapseToggle: bool,
        SkipItems: bool,
        Appearing: bool,
        Hidden: bool,
        IsFallbackWindow: bool,
        IsExplicitChild: bool,
        HasCloseButton: bool,
        ResizeBorderHovered: i8,
        ResizeBorderHeld: i8,
        BeginCount: i16,
        BeginCountPreviousFrame: i16,
        BeginOrderWithinParent: i16,
        BeginOrderWithinContext: i16,
        FocusOrder: i16,
        PopupId: cimgui.ImGuiID,
        AutoFitFramesX: cimgui.ImS8,
        AutoFitFramesY: cimgui.ImS8,
        AutoFitOnlyGrows: bool,
        AutoPosLastDirection: cimgui.ImGuiDir,
        HiddenFramesCanSkipItems: cimgui.ImS8,
        HiddenFramesCannotSkipItems: cimgui.ImS8,
        HiddenFramesForRenderOnly: cimgui.ImS8,
        DisableInputsFrames: cimgui.ImS8,

        bit_field_zero: packed struct(u32) {
            SetWindowPosAllowFlags: u8,
            SetWindowSizeAllowFlags: u8,
            SetWindowCollapsedAllowFlags: u8,
            SetWindowDockAllowFlags: u8,
        },

        SetWindowPosVal: cimgui.ImVec2,
        SetWindowPosPivot: cimgui.ImVec2,
        IDStack: cimgui.ImVector_ImGuiID,
        DC: cimgui.ImGuiWindowTempData,
        OuterRectClipped: cimgui.ImRect,
        InnerRect: cimgui.ImRect,
        InnerClipRect: cimgui.ImRect,
        WorkRect: cimgui.ImRect,
        ParentWorkRect: cimgui.ImRect,
        ClipRect: cimgui.ImRect,
        ContentRegionRect: cimgui.ImRect,
        HitTestHoleSize: cimgui.ImVec2ih,
        HitTestHoleOffset: cimgui.ImVec2ih,
        LastFrameActive: c_int,
        LastFrameJustFocused: c_int,
        LastTimeActive: f32,
        ItemWidthDefault: f32,
        StateStorage: cimgui.ImGuiStorage,
        ColumnsStorage: cimgui.ImVector_ImGuiOldColumns,
        FontWindowScale: f32,
        FontDpiScale: f32,
        SettingsOffset: c_int,
        DrawList: *cimgui.ImDrawList,
        DrawListInst: cimgui.ImDrawList,
        ParentWindow: *cimgui.ImGuiWindow,
        ParentWindowInBeginStack: *cimgui.ImGuiWindow,
        RootWindow: *cimgui.ImGuiWindow,
        RootWindowPopupTree: *cimgui.ImGuiWindow,
        RootWindowDockTree: *cimgui.ImGuiWindow,
        RootWindowForTitleBarHighlight: *cimgui.ImGuiWindow,
        RootWindowForNav: *cimgui.ImGuiWindow,
        NavLastChildNavWindow: *cimgui.ImGuiWindow,
        NavLastIds: [cimgui.ImGuiNavLayer_COUNT]cimgui.ImGuiID,
        NavRectRel: [cimgui.ImGuiNavLayer_COUNT]cimgui.ImRect,
        NavPreferredScoringPosRel: [cimgui.ImGuiNavLayer_COUNT]cimgui.ImVec2,
        NavRootFocusScopeId: cimgui.ImGuiID,
        MemoryDrawListIdxCapacity: c_int,
        MemoryDrawListVtxCapacity: c_int,
        MemoryCompacted: bool,

        bit_field_two: packed struct(u8) {
            dock_is_active: bool,
            dock_node_is_visible: bool,
            dock_tab_is_visible: bool,
            dock_tab_want_close: bool,
            _: u4,
        },
    };
};

pub const impl = struct {
    pub const InitError = error{
        InitFailed,
    };

    pub const glfw = struct {
        pub fn initForOpenGL(window: *@import("zglfw").Window, options: struct {
            install_callbacks: bool = true,
        }) InitError!void {
            if (cimgui.cImGui_ImplGlfw_InitForOpenGL(
                @ptrCast(window),
                options.install_callbacks,
            ) == false) {
                return InitError.InitFailed;
            }
        }

        pub fn initForMetal(window: *@import("zglfw").Window, options: struct {
            install_callbacks: bool = true,
        }) InitError!void {
            if (cimgui.cImGui_ImplGlfw_InitForOther(
                @ptrCast(window),
                options.install_callbacks,
            ) == false) {
                return InitError.InitFailed;
            }
        }

        pub fn shutdown() void {
            cimgui.cImGui_ImplGlfw_Shutdown();
        }

        pub fn newFrame() void {
            cimgui.cImGui_ImplGlfw_NewFrame();
        }
    };

    pub const opengl3 = struct {
        pub fn init(
            options: struct {
                glsl_version: ?[:0]const u8 = null,
            },
        ) InitError!void {
            const status = if (options.glsl_version) |glsl_version|
                cimgui.cImGui_ImplOpenGL3_InitEx(glsl_version.ptr)
            else
                cimgui.cImGui_ImplOpenGL3_Init();

            if (status == false) {
                return InitError.InitFailed;
            }
        }

        pub fn shutdown() void {
            cimgui.cImGui_ImplOpenGL3_Shutdown();
        }

        pub fn newFrame() void {
            cimgui.cImGui_ImplOpenGL3_NewFrame();
        }

        pub fn renderDrawData(draw_data: *DrawData) void {
            cimgui.cImGui_ImplOpenGL3_RenderDrawData(@ptrCast(draw_data));
        }
    };

    pub const metal = struct {
        pub fn init(device: mtl.MetalDevice) !void {
            if (!cimgui.cImGui_ImplMetal_Init(device.handle.value)) {
                return error.InitFailed;
            }

            _ = cimgui.cImGui_ImplMetal_CreateDeviceObjects(device.handle.value);
        }

        pub fn newFrame(render_pass_descriptor: mtl.MetalRenderPassDescriptor) void {
            cimgui.cImGui_ImplMetal_NewFrame(render_pass_descriptor.handle.value);
        }

        pub fn renderDrawData(
            draw_data: *DrawData,
            command_buffer: mtl.MetalCommandBuffer,
            encoder: mtl.MetalRenderEncoder,
        ) void {
            cimgui.cImGui_ImplMetal_RenderDrawData(
                draw_data,
                command_buffer.handle.value,
                encoder.handle.value,
            );
        }

        const mtl = @import("metal");
    };
};

pub const cimgui = @import("cimgui");
const std = @import("std");
