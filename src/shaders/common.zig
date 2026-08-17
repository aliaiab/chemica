pub const chunk_size = 16;

pub const VoxelHeapIndex = enum(u32) {
    null = 0xffff,
    _,
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

pub const GizmoUniforms = extern struct {
    view_projection: [4][4]f32,
};

///Meant to be passed to a graphics api via *DrawIndirect()
pub const DrawCommand = extern struct {
    count: u32,
    instance_count: u32,
    first: u32,
    base_instance: u32,

    primitive_type: PrimitiveType,
    materials_begin: u32,
    transforms_begin: u32,
    parameters_begin: u32,
};

pub const PrimitiveType = enum(u32) {
    triangle_list_3d,
    triangle_list_2d,
    box,
    line,
    sphere,
    circle,
    bezier_curve,
    plane_segment,
};

pub const Material = extern struct {
    colour: Colour,
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

pub fn StorageBuffer(comptime T: type) type {
    return switch (@import("builtin").cpu.arch) {
        .spirv32, .spirv64 => *addrspace(.storage_buffer) T,
        else => enum(u32) {
            _,

            pub const address_space: std.lang.AddressSpace = .storage_buffer;
        },
    };
}

pub fn RuntimeArray(comptime T: type) type {
    return switch (@import("builtin").cpu.arch) {
        .spirv32, .spirv64 => extern struct {
            data: @SpirvType(.{ .runtime_array = T }),
        },
        else => u32,
    };
}

pub const AsymDescriptors = struct {
    uniforms: StorageBuffer(GizmoUniforms),
    draws: StorageBuffer(RuntimeArray(DrawCommand)),
    transforms: StorageBuffer(RuntimeArray(AffineTransform3D)),
    materials: StorageBuffer(RuntimeArray(Material)),
    parameters: StorageBuffer(RuntimeArray(f32)),
    vertices: StorageBuffer(RuntimeArray([3]f32)),
    transform_offsets_by_type: StorageBuffer(RuntimeArray(u32)),
    parameter_offsets_by_type: StorageBuffer(RuntimeArray(u32)),
};

pub const asym = struct {
    pub const GraphemeBuffer = extern struct {
        buffer_begin: u32,
        width: u32,
        height: u32,
    };

    pub const GraphemePidgeonHole = extern struct {
        grapheme_slice: GraphemeSlice,

        pub const GraphemeSlice = packed struct(u32) {
            offset: u28,
            count: u4,
        };
    };

    pub const GraphemeInstance = extern struct {
        glyph_index: u16,
        x_offset: f16,
    };

    pub const GlyphMetric = extern struct {
        width: f32 = 0,
        height: f32 = 0,
        advance: f32 = 0,
        bearing_x: f32 = 0,
        bearing_y: f32 = 0,
    };
};

pub const uniforms = @extern(*addrspace(.storage_buffer) const ShaderUniforms, .{
    .name = "uniforms",
    .decoration = .{
        .descriptor = .{
            .binding = 0,
            .set = 0,
        },
    },
});

pub const voxel_chunk_positions_image = @extern(
    *addrspace(.constant) const UImage3D,
    .{
        .name = "voxel_chunk_positions_image",
        .decoration = .{
            .descriptor = .{
                .set = 0,
                .binding = 2,
            },
        },
    },
);

pub const voxel_chunk_positions_sampler = @extern(
    *addrspace(.constant) const USampler3D,
    .{
        .name = "voxel_chunk_positions_sampler",
        .decoration = .{
            .descriptor = .{
                .set = 0,
                .binding = 11,
            },
        },
    },
);

const USampler3D = @SpirvType(.{ .sampled_image = UImage3DSampled });

pub const UImage3DSampled = @SpirvType(.{ .image = .{
    .usage = .{ .sampled = u32 },
    .format = .unknown,
    .dim = .@"3d",
    .depth = .not_depth,
    .arrayed = false,
    .multisampled = false,
    .access = .unknown,
} });

pub const UImage3D = @SpirvType(.{ .image = .{
    .usage = .{ .storage = u32 },
    .format = .r32u,
    .dim = .@"3d",
    .depth = .not_depth,
    .arrayed = false,
    .multisampled = false,
    .access = .unknown,
} });

const math = @import("../math.zig");
const std = @import("std");
const zmath = @import("zmath");
