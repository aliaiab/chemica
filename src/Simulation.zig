width: u32,
height: u32,
depth: u32,
voxel_materials: std.ArrayList(VoxelMaterial) = .empty,
voxel_materials_visual: std.ArrayList(VoxelMaterialVisual) = .empty,

gpu_sim: gpu.Simulation = undefined,
ray_stats: RayStats = .{},

camera: @import("main.zig").Camera = undefined,

measured_heat: i32 = 0,

enable_simulation: bool = true,
enable_radiative_cooling: bool = true,
csg_dirty: bool = true,

point_lights: std.ArrayList(PointLight) = .empty,

timestep_index: u32 = 0,

model_matrix: [4][4]f32 = undefined,
view_matrix: [4][4]f32 = undefined,
projection_matrix: [4][4]f32 = undefined,
renderer_view_type: RendererViewType = .pbr,

window_size: [2]u32,

pub fn init(
    context: *gpu.Context,
    arena: std.mem.Allocator,
    voxel_materials: std.ArrayList(VoxelMaterial),
    voxel_materials_visual: std.ArrayList(VoxelMaterialVisual),
) !Simulation {
    var sim: Simulation = .{
        .width = 128,
        .height = 128,
        .depth = 128,
        .window_size = undefined,
        .voxel_materials = voxel_materials,
        .voxel_materials_visual = voxel_materials_visual,
    };

    sim.gpu_sim = try .init(context, sim, arena);

    return sim;
}

pub fn deinit(sim: *Simulation, gpa: std.mem.Allocator) void {
    _ = sim; // autofix
    _ = gpa; // autofix
}

pub fn update(sim: *Simulation, scene_root_index: u32) !void {
    _ = scene_root_index; // autofix
    try sim.gpu_sim.update(sim);
}

pub fn render(
    sim: *Simulation,
    context: gpu.Context,
    render_texture: ?[]gpu.TextureByte,
    scene_root_index: u32,
    options: struct {
        render_sdf_raymarched: bool = false,
    },
) void {
    sim.gpu_sim.render(
        context,
        render_texture,
        scene_root_index,
        .{ .render_sdf_raymarched = options.render_sdf_raymarched },
    );
}

pub fn updateCSGProgram(
    sim: *Simulation,
    context: *gpu.Context,
    program: CSGProgram,
) !void {
    try sim.gpu_sim.updateCSGProgram(context, sim.*, program);
}

pub const VoxelMaterial = extern struct {
    //kgmol^-1
    molar_mass: f32 = 12.0 / 1000.0,
    //kgm^-3
    density: f32 = 10,
    heat_conductivity: f32 = 100,
    thermal_emisivity: f32 = 1.0,
    //JK^-1kg^-1
    heat_capacity: f32 = 1000,
    //K
    melting_point: f32 = 10000,
    //K
    boiling_point: f32 = 2000,
};

pub const VoxelMaterialVisual = extern struct {
    albedo: u32 = 0xffffff,
    roughness_metalness: u32 = 0xffffffff,
    reflectivity: f32 = 0,
    refractive_index: f32 = 1.5,
};

pub const SdfElement3D = extern struct {
    type: SdfElementTypeAndModifiers,
    params_start: u16,
    children_start: u16,
    children_count: u16,
};

pub const SdfElementTypeAndModifiers = packed struct(u16) {
    type: SdfElementType,
    modifiers: SdfElementModifiers,
};

pub const SdfElementModifiers = packed struct(u8) {
    rounding: bool = false,
    extrusion: bool = false,
    repetition: bool = false,
    revolution: bool = false,
    elongation: bool = false,
    _: u3 = 0,
};

pub const SdfElementType = enum(u8) {
    @"union",
    intersection,
    difference,
    box,
    cylinder,
    sphere,
    extrude,
    revolve,
    n_gon,
};

pub const CSGProgram = struct {
    //TODO: make this a multi array list
    elements: std.ArrayList(SdfElement3D) = .empty,
    element_bounds: std.ArrayList([4]f32) = .empty,
    transforms: std.ArrayList(AffineTransform3D) = .empty,
    element_params: std.ArrayList(f32) = .empty,

    elements_to_nodes: std.AutoArrayHashMapUnmanaged(u32, @import("main.zig").CSGTreeNodeHandle) = .empty,

    fn sdBox(p: @Vector(3, f32), b: @Vector(3, f32)) f32 {
        const q = @abs(p) - b;
        return zmath.length3(.{ @max(q[0], 0), @max(q[1], 0), @max(q[2], 0), 0 })[0] + @min(@max(q[0], @max(q[1], q[2])), 0);
    }

    fn sdSphere(q: @Vector(3, f32), r: f32) f32 {
        return zmath.length3(.{ q[0], q[1], q[2], 0 })[0] - r;
    }

    fn sdUnion(a: f32, b: f32) f32 {
        return @min(a, b);
    }

    pub fn clear(self: *@This()) void {
        self.transforms.clearRetainingCapacity();
        self.element_bounds.clearRetainingCapacity();
        self.elements.clearRetainingCapacity();
        self.element_params.clearRetainingCapacity();
        self.elements_to_nodes.clearRetainingCapacity();
    }

    pub fn rayMarchSDF(
        program: @This(),
        ray_origin: @Vector(3, f32),
        in_ray_direction: @Vector(3, f32),
    ) ?u32 {
        const ray_direction_v4 = zmath.normalize3(.{
            in_ray_direction[0],
            in_ray_direction[1],
            in_ray_direction[2],
            0,
        });
        const ray_direction: @Vector(3, f32) = .{
            ray_direction_v4[0],
            ray_direction_v4[1],
            ray_direction_v4[2],
        };

        const max_steps = 100;

        var t: @Vector(3, f32) = @splat(0);

        for (0..max_steps) |_| {
            const sample_point = ray_origin + ray_direction * t;

            const result = program.evaluateDistanceFunction(sample_point);

            if (result.signed_distance < 0.01) {
                return result.instruction;
            }

            t += @splat(result.signed_distance);
        }

        return null;
    }

    pub fn evaluateDistanceFunction(
        program: @This(),
        sample_position: @Vector(3, f32),
    ) struct {
        signed_distance: f32,
        transform: u32,
        instruction: u32,
    } {
        _ = program; // autofix
        _ = sample_position; // autofix
        return undefined;
    }

    fn transformPoint(point: @Vector(3, f32), rigid_transform: AffineTransform3D) @Vector(3, f32) {
        const result = point - rigid_transform.position;
        var inverse_rotation = rigid_transform.rotation;
        inverse_rotation[3] *= -1;

        var rotated = zmath.rotate(inverse_rotation, .{
            result[0],
            result[1],
            result[2],
            0,
        });

        rotated *= @splat(1.0 / rigid_transform.uniform_scale);

        return .{ rotated[0], rotated[1], rotated[2] };
    }
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

pub const CSGMaterialComponent = extern struct {
    material: VoxelMaterialHandle,
    density: f32,
};

pub const CSGMaterial = extern struct {
    component_start: u32,
    component_count: u32,
    min_temperature: f32,
    max_temperature: f32,
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

pub const VoxelMaterialHandle = enum(u32) {
    air = 0,
    _,
};

pub const PointLight = extern struct {
    position: [3]f32,
    radiance: f32,
    colour: u32,
    pad: [3]u32 = undefined,
};

pub const RayStats = extern struct {
    total_primary_rays: u32 = 0,
    total_primary_ray_hits: u32 = 0,
    total_primary_ray_steps: u32 = 0,
    max_primary_ray_steps: u32 = 0,
    min_primary_ray_steps: u32 = 0,
    total_secondary_rays: u32 = 0,
    total_secondary_ray_hits: u32 = 0,
    total_secondary_ray_steps: u32 = 0,
    max_secondary_ray_steps: u32 = 0,
    min_secondary_ray_steps: u32 = std.math.maxInt(u32),
};

const std = @import("std");
const Simulation = @This();
const math = @import("math.zig");
const zmath = @import("zmath");
const Texture = gpu.Texture;
const gpu = @import("gpu.zig");
