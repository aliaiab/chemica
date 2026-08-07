pub const ShaderUniforms = extern struct {
    model: [4][4]f32,
    view: [4][4]f32,
    projection: [4][4]f32,
    size: [3]u32,
    padding0: u32 = 0,
    base_velocity: [3]i32,
    substep_index: u32,
    root_transform: AffineTransform3D,
    csg_bounding_min: [3]i32,
    padding1: u32 = 0,
    csg_bounding_max: [3]i32,
    delta_time: f32,
    window_size: [2]u32,
    enable_radiative_cooling: u32,
    renderer_view_type: RendererViewType,
    sdf_texture_root: u32 = 0,
};

pub const AffineTransform3D = extern struct {
    position: [3]f32 = .{ 0, 0, 0 },
    uniform_scale: f32 = 1,
    rotation: [4]f32 = .{ 0, 0, 0, 1 },

    pub const identity: AffineTransform3D = .{
        .position = .{ 0, 0, 0 },
        .uniform_scale = 1,
        .rotation = .{ 0, 0, 0, 1 },
    };

    pub fn compose(lhs: AffineTransform3D, rhs: AffineTransform3D) AffineTransform3D {
        var result: AffineTransform3D = .identity;
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

    pub inline fn transformInverseVector(
        transform: AffineTransform3D,
        vector: @Vector(3, f32),
    ) @Vector(3, f32) {
        const transform_position: @Vector(3, f32) = .{ transform.position[0], transform.position[1], transform.position[2] };
        _ = transform_position; // autofix
        var translated = vector;

        translated[0] -= transform.position[0];

        if (false) {
            const rotated = zmath.rotate(
                transform.rotation,
                .{ translated[0], translated[1], translated[2], 0 },
            );
            _ = rotated; // autofix
        }
        const rotated = translated;

        if (true) {
            return translated;
        }

        var scaled: @Vector(3, f32) = .{ rotated[0], rotated[1], rotated[2] };

        scaled *= @splat(1 / transform.uniform_scale);

        return scaled;
    }

    test {
        std.testing.refAllDecls(@This());
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

pub const common = @import("common.zig");
pub const sdf = @import("sdf.zig");

test {
    _ = std.testing.refAllDecls(@This());
}

const zmath = @import("lib").zmath;
const math = @import("lib").math;
const std = @import("std");
