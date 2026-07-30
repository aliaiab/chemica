width: u32,
height: u32,
depth: u32,
voxel_materials: std.ArrayList(VoxelMaterial) = .empty,
voxel_materials_visual: std.ArrayList(VoxelMaterialVisual) = .empty,

gpu_sim: gpu.Simulation = undefined,
camera: @import("main.zig").Camera = undefined,

measured_heat: i32 = 0,

enable_simulation: bool = true,
enable_radiative_cooling: bool = true,
csg_dirty: bool = true,

point_lights: std.ArrayList(PointLight) = .empty,

timestep_index: u32 = 0,

csg_invocations: std.ArrayList(CSGInvocation) = .empty,

model_matrix: [4][4]f32 = undefined,
view_matrix: [4][4]f32 = undefined,
projection_matrix: [4][4]f32 = undefined,
renderer_view_type: RendererViewType = .pbr,

window_size: [2]u32,

pub fn init(
    arena: std.mem.Allocator,
    window_size: [2]u32,
) !Simulation {
    var sim: Simulation = .{
        .width = 128,
        .height = 128,
        .depth = 128,
        .window_size = window_size,
    };

    sim.gpu_sim = try .init(arena);

    return sim;
}

pub fn deinit(sim: *Simulation, gpa: std.mem.Allocator) void {
    sim.csg_invocations.deinit(gpa);
}

pub fn update(sim: *Simulation) void {
    const shader_uniforms: ShaderUniforms = .{
        .size = .{ sim.width, sim.height, sim.depth },
        .base_velocity = undefined,
        .model = sim.model_matrix,
        .view = sim.view_matrix,
        .projection = sim.projection_matrix,
        .root_transform = sim.csg_invocations.items[0].transform,
        .csg_bounding_min = sim.csg_invocations.items[0].bound_min,
        .csg_bounding_max = sim.csg_invocations.items[0].bound_max,
        .substep_index = sim.timestep_index,
        .window_size = sim.window_size,
        .delta_time = 0,
        .enable_radiative_cooling = @intFromBool(sim.enable_radiative_cooling),
        .renderer_view_type = sim.renderer_view_type,
    };

    sim.gpu_sim.update(shader_uniforms);
}

pub fn render(sim: *Simulation, render_texture: ?*Texture) void {
    const shader_uniforms: ShaderUniforms = .{
        .size = .{ sim.width, sim.height, sim.depth },
        .base_velocity = undefined,
        .model = sim.model_matrix,
        .view = sim.view_matrix,
        .projection = sim.projection_matrix,
        .root_transform = sim.csg_invocations.items[0].transform,
        .csg_bounding_min = sim.csg_invocations.items[0].bound_min,
        .csg_bounding_max = sim.csg_invocations.items[0].bound_max,
        .substep_index = sim.timestep_index,
        .window_size = sim.window_size,
        .delta_time = 0,
        .enable_radiative_cooling = @intFromBool(sim.enable_radiative_cooling),
        .renderer_view_type = sim.renderer_view_type,
    };

    sim.gpu_sim.render(shader_uniforms, render_texture);
}

pub fn updateCSGProgram(
    sim: *Simulation,
    program: CSGProgram,
) !void {
    if (program.instructions.items.len == 0) {
        return;
    }

    sim.csg_invocations.items[0].bound_min = .{ 0, 0, 0 };
    sim.csg_invocations.items[0].bound_max = .{
        @intCast(sim.width),
        @intCast(sim.height),
        @intCast(sim.depth),
    };

    gl.NamedBufferData(
        sim.csg_instruction_buffer,
        @intCast(program.instructions.items.len * @sizeOf(CSGInstruction)),
        program.instructions.items.ptr,
        gl.DYNAMIC_DRAW,
    );

    if (program.instructions_box.items.len > 0) {
        gl.NamedBufferData(
            sim.csg_instructions_box_buffer,
            @intCast(program.instructions_box.items.len * @sizeOf(CSGInstructionBox)),
            program.instructions_box.items.ptr,
            gl.DYNAMIC_DRAW,
        );
    }

    if (program.instructions_sphere.items.len > 0) {
        gl.NamedBufferData(
            sim.csg_instructions_sphere_buffer,
            @intCast(program.instructions_sphere.items.len * @sizeOf(CSGInstructionSphere)),
            program.instructions_sphere.items.ptr,
            gl.DYNAMIC_DRAW,
        );
    }

    if (program.instructions_extrude_post.items.len > 0) {
        gl.NamedBufferData(
            sim.csg_instructions_extrude_post_buffer,
            @intCast(program.instructions_extrude_post.items.len * @sizeOf(CSGInstructionExtrudePost)),
            program.instructions_extrude_post.items.ptr,
            gl.DYNAMIC_DRAW,
        );
    }

    gl.NamedBufferData(
        sim.csg_transform_buffer,
        @intCast(program.transforms.items.len * @sizeOf(CSGRigidTransform)),
        program.transforms.items.ptr,
        gl.DYNAMIC_DRAW,
    );
}

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

pub const CSGProgram = struct {
    transforms: std.ArrayList(CSGRigidTransform) = .empty,
    instructions: std.ArrayList(CSGInstruction) = .empty,
    instructions_box: std.ArrayList(CSGInstructionBox) = .empty,
    instructions_sphere: std.ArrayList(CSGInstructionSphere) = .empty,
    instructions_extrude_post: std.ArrayList(CSGInstructionExtrudePost) = .empty,
    material: std.ArrayList(CSGMaterialComponent) = .empty,
    instructions_to_nodes: std.AutoArrayHashMapUnmanaged(u32, @import("main.zig").CSGTreeNodeHandle) = .empty,

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
        var distance_stack: [16]f32 = undefined;
        var transform_stack: [16]u32 = undefined;
        var instruction_stack: [16]usize = [1]usize{std.math.maxInt(u32)} ** 16;

        var position_stack: [16]@Vector(3, f32) = undefined;

        var stack_pointer: u32 = 0;
        const position_stack_pointer: u32 = 0;
        position_stack[position_stack_pointer] = sample_position;

        for (program.instructions.items, 0..) |instruction, instruction_index| {
            const position = position_stack[position_stack_pointer];

            switch (instruction.csg_op) {
                .box => {
                    const instruction_box = program.instructions_box.items[instruction.stream_index];
                    const transform = program.transforms.items[instruction_box.rigid_transform];

                    const point = transformPoint(position, transform);

                    transform_stack[stack_pointer] = instruction_box.rigid_transform;
                    distance_stack[stack_pointer] = sdBox(point, instruction_box.bounds) * transform.uniform_scale;
                    instruction_stack[stack_pointer] = instruction_index;
                    stack_pointer += 1;
                },
                .sphere => {
                    const instructions_sphere = program.instructions_sphere.items[instruction.stream_index];
                    const transform = program.transforms.items[instructions_sphere.rigid_transform];

                    const point = transformPoint(position, transform);

                    transform_stack[stack_pointer] = instructions_sphere.rigid_transform;
                    distance_stack[stack_pointer] = sdSphere(point, instructions_sphere.radius) * transform.uniform_scale;
                    instruction_stack[stack_pointer] = instruction_index;
                    stack_pointer += 1;
                },
                .binary_op_union => {
                    stack_pointer -= 1;
                    const d1 = distance_stack[stack_pointer];
                    const transform_1 = transform_stack[stack_pointer];
                    const instruction_1 = instruction_stack[stack_pointer];
                    stack_pointer -= 1;
                    const d0 = distance_stack[stack_pointer];
                    const transform_0 = transform_stack[stack_pointer];
                    const instruction_0 = instruction_stack[stack_pointer];

                    if (d0 < d1) {
                        transform_stack[stack_pointer] = transform_0;
                        instruction_stack[stack_pointer] = instruction_0;
                    } else {
                        transform_stack[stack_pointer] = transform_1;
                        instruction_stack[stack_pointer] = instruction_1;
                    }

                    distance_stack[stack_pointer] = sdUnion(d0, d1);
                    stack_pointer += 1;
                },
                else => {},
            }
        }

        return .{
            .signed_distance = distance_stack[stack_pointer -| 1],
            .transform = transform_stack[stack_pointer -| 1],
            .instruction = @intCast(instruction_stack[stack_pointer -| 1]),
        };
    }

    fn transformPoint(point: @Vector(3, f32), rigid_transform: CSGRigidTransform) @Vector(3, f32) {
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

pub const CSGInstructionOp = enum(u32) {
    identity,
    box,
    sphere,
    plane,
    triangle,
    cylynder,
    cone,
    torus,

    binary_op_union,
    binary_op_intersection,
    binary_op_difference,
    binary_op_xor,
    binary_op_smooth_union,
    binary_op_smooth_intersection,
    binary_op_smooth_difference,
    unary_op_revolve,
    unary_op_elgongate,
    unary_op_extrude_pre,
    unary_op_extrude_post,
    pop_distance,
    pop_position,
    transform,
    transform_post,
};

pub const CSGInstruction = extern struct {
    csg_op: CSGInstructionOp,
    stream_index: u32,
};

pub const CSGInstructionBox = extern struct {
    bounds: [3]f32,
    rigid_transform: u32,
    material: VoxelMaterialHandle,
    pad: [12]u8 = undefined,
};

pub const CSGInstructionSphere = extern struct {
    radius: f32,
    rigid_transform: u32,
    material: VoxelMaterialHandle,
};

pub const CSGInstructionExtrudePost = extern struct {
    h: f32,
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
        var result: CSGRigidTransform = undefined;
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

pub const CSGInvocation = extern struct {
    transform: CSGRigidTransform,
    bound_min: [3]i32,
    bound_max: [3]i32,
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

const std = @import("std");
const Simulation = @This();
const gl = @import("gl");
const math = @import("math.zig");
const zmath = @import("zmath");
const metal = @import("metal");
const Texture = gpu.Texture;
const gpu = @import("gpu.zig");
