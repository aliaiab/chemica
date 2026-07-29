pub const Mode = enum(u32) { local, world };

pub const Operation = packed struct(u32) {
    translate_x: bool = false,
    translate_y: bool = false,
    translate_z: bool = false,
    rotate_x: bool = false,
    rotate_y: bool = false,
    rotate_z: bool = false,
    rotate_screen: bool = false,
    scale_x: bool = false,
    scale_y: bool = false,
    scale_z: bool = false,
    bounds: bool = false,
    scale_xu: bool = false,
    scale_yu: bool = false,
    scale_zu: bool = false,

    padding: u18 = 0,

    pub const translate = Operation{ .translate_x = true, .translate_y = true, .translate_z = true };
    pub const scale = Operation{ .scale_x = true, .scale_y = true, .scale_z = true };
    pub const rotate = Operation{ .rotate_x = true, .rotate_y = true, .rotate_z = true, .rotate_screen = true };
    pub const universal = Operation{
        .translate_x = true,
        .translate_y = true,
        .translate_z = true,
        .rotate_x = true,
        .rotate_y = true,
        .rotate_z = true,
        .rotate_screen = true,
        .scale_x = true,
        .scale_y = true,
        .scale_z = true,
        .bounds = true,
    };
};

extern fn ImGuizmo_SetDrawlist(drawlist: [*c]cimgui.ImDrawList) void;
extern fn ImGuizmo_BeginFrame() void;
pub extern fn ImGuizmo_SetImGuiContext(ctx: [*c]cimgui.ImGuiContext) void;
pub extern fn ImGuizmo_IsOver() bool;
pub extern fn ImGuizmo_IsUsing() bool;
extern fn ImGuizmo_Enable(enable: bool) void;
pub extern fn ImGuizmo_DecomposeMatrixToComponents(matrix: [*]f32, translation: [*]f32, rotation: [*]f32, scale: [*]f32) void;
pub extern fn ImGuizmo_RecomposeMatrixFromComponents(translation: [*]const f32, rotation: [*]const f32, scale: [*]const f32, matrix: [*]f32) void;
extern fn ImGuizmo_SetRect(x: f32, y: f32, width: f32, height: f32) void;
pub extern fn ImGuizmo_SetOrthographic(is_orthographic: bool) void;
pub extern fn ImGuizmo_DrawCubes(view: [*]const f32, projection: [*]const f32, matrices: [*]const f32, matrix_count: c_int) void;
pub extern fn ImGuizmo_DrawGrid(view: [*]const f32, projection: [*]const f32, matrix: [*]const f32, grid_size: f32) void;
extern fn ImGuizmo_Manipulate(view: [*]const f32, projection: [*]const f32, operation: Operation, mode: Mode, matrix: [*]f32, delta_quat: [*]f32, delta_matrix: ?[*]f32, snap: ?[*]f32, local_bounds: ?[*]const f32, bounds_snap: ?[*]const f32) bool;
pub extern fn ImGuizmo_ViewManipulate(view: [*]f32, length: f32, position: cimgui.ImVec2, size: cimgui.ImVec2, background_color: u32) void;
pub extern fn ImGuizmo_ViewManipulateExt(view: [*]f32, projection: [*]const f32, operation: Operation, mode: Mode, matrix: [*]f32, length: f32, position: cimgui.ImVec2, size: cimgui.ImVec2, background_color: u32) void;
pub extern fn ImGuizmo_SetID(id: u32) void;
pub extern fn ImGuizmo_IsOperationOver(op: Operation) bool;
pub extern fn ImGuizmo_SetGizmoSizeClipSpace(value: f32) void;
pub extern fn ImGuizmo_AllowAxisFlip(value: bool) void;

pub inline fn setRect(x: f32, y: f32, w: f32, h: f32) void {
    ImGuizmo_SetRect(x, y, w, h);
}

pub inline fn setDrawList(draw_list: *cimgui.ImDrawList) void {
    ImGuizmo_SetDrawlist(@ptrCast(draw_list));
}

pub inline fn beginFrame() void {
    ImGuizmo_BeginFrame();
}

pub inline fn enable(should_enable: bool) void {
    ImGuizmo_Enable(should_enable);
}

pub inline fn manipulate(
    view_matrix: [*]const f32,
    projection_matrix: [*]const f32,
    operation: Operation,
    mode: Mode,
    matrix: [*]f32,
    delta_quat: [*]f32,
    optionals: struct {
        delta_matrix: ?[*]f32 = null,
        snap: ?[*]f32 = null,
        local_bounds: ?[*]f32 = null,
        bounds_snap: ?[*]const f32 = null,
    },
) bool {
    return ImGuizmo_Manipulate(
        view_matrix,
        projection_matrix,
        operation,
        mode,
        matrix,
        delta_quat,
        optionals.delta_matrix,
        optionals.snap,
        optionals.local_bounds,
        optionals.bounds_snap,
    );
}

pub const view = struct {
    extern fn ImViewGuizmo_BeginFrame() void;
    extern fn ImViewGuizmo_Rotate(
        camera_pos: *[3]f32,
        camera_rot: *[4]f32,
        pivot: *const [3]f32,
        position: *const [2]f32,
        rotation_speed: f32,
    ) bool;

    pub fn beginFrame() void {
        return ImViewGuizmo_BeginFrame();
    }

    pub fn rotate(
        camera_pos: *[3]f32,
        camera_rot: *[4]f32,
        pivot: [3]f32,
        position: [2]f32,
        options: struct {
            rotation_speed: f32 = 0.01,
        },
    ) bool {
        return ImViewGuizmo_Rotate(
            camera_pos,
            camera_rot,
            &pivot,
            &position,
            options.rotation_speed,
        );
    }
};

const cimgui = @import("cimgui");
