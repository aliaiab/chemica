pub const ShaderUniforms = extern struct {
    model: [4][4]f32,
    view: [4][4]f32,
    projection: [4][4]f32,
    size: [3]u32,
    padding0: u32 = 0,
    base_velocity: [3]i32,
    substep_index: u32,
    root_transform: CSGRigidTransform,
    csg_bounding_min: [3]i32,
    padding1: u32 = 0,
    csg_bounding_max: [3]i32,
    delta_time: f32,
    window_size: [2]u32,
    enable_radiative_cooling: u32,
    renderer_view_type: RendererViewType,
};

pub const CSGRigidTransform = extern struct {
    position: [3]f32 = .{ 0, 0, 0 },
    uniform_scale: f32 = 1,
    rotation: @Vector(4, f32) align(@alignOf(f32)) = .{ 0, 0, 0, 1 },

    pub const identity: CSGRigidTransform = .{
        .position = .{ 0, 0, 0 },
        .uniform_scale = 1,
        .rotation = .{ 0, 0, 0, 1 },
    };

    pub fn compose(lhs: CSGRigidTransform, rhs: CSGRigidTransform) CSGRigidTransform {
        var result: CSGRigidTransform = .identity;
        const rotated_pos = zmath.rotate(lhs.rotation, .{ rhs.position[0], rhs.position[1], rhs.position[2], 0 });
        result.position = .{
            lhs.position[0] + rotated_pos[0] * lhs.uniform_scale,
            lhs.position[1] + rotated_pos[1] * lhs.uniform_scale,
            lhs.position[2] + rotated_pos[2] * lhs.uniform_scale,
        };
        result.uniform_scale = lhs.uniform_scale * rhs.uniform_scale;
        result.rotation = math.mulQuat(lhs.rotation, rhs.rotation);

        return result;
    }
};

pub const RendererViewType = enum(u32) {
    pbr,
    albedo,
    roughness,
    metalness,
    ambient_occlusion,
    normal,
    material,
    deviation,
    temperature,
    ray_steps,
};

const zmath = @import("zmath");
const math = @import("math.zig");
