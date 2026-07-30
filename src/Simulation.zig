width: u32,
height: u32,
depth: u32,
voxel_materials: std.ArrayList(VoxelMaterial) = .empty,
voxel_materials_visual: std.ArrayList(VoxelMaterialVisual) = .empty,

renderer_program: u32 = 0,
vertex_array: u32 = 0,
vertex_buffer: u32 = 0,

simulation_material_buffers: [2]u32 = .{ 0, 0 },
simulation_deviation_buffers: [2]u32 = .{ 0, 0 },
simulation_temperature_buffers: [2]u32 = .{ 0, 0 },

heat_measurement_buffer: u32 = 0,
measured_heat: i32 = 0,

voxel_materials_buffer: u32 = 0,
voxel_materials_visual_buffer: u32 = 0,

simulation_shader: u32 = 0,
thermal_shader: u32 = 0,
grain_simulation_shader: u32 = 0,
fill_region_shader: u32 = 0,

enable_simulation: bool = true,
enable_radiative_cooling: bool = true,
csg_dirty: bool = true,

point_light_buffer: u32 = 0,
point_lights: std.ArrayList(PointLight) = .empty,

timestep_index: u32 = 0,

uniform_buffer: u32 = 0,

csg_instruction_buffer: u32 = 0,
csg_instructions_box_buffer: u32 = 0,
csg_instructions_sphere_buffer: u32 = 0,
csg_instructions_extrude_post_buffer: u32 = 0,
csg_transform_buffer: u32 = 0,
csg_composite_material_buffer: u32 = 0,

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

    sim.renderer_program = try loadShaderProgram(arena, &.{
        .{
            .type = gl.VERTEX_SHADER,
            .binary = @embedFile("shaders/Include/RendererVertex.spv"),
        },
        .{
            .type = gl.FRAGMENT_SHADER,
            .binary = @embedFile("shaders/Include/RendererFragment.spv"),
        },
    });
    sim.simulation_shader = try loadShaderProgram(arena, &.{
        .{
            .type = gl.COMPUTE_SHADER,
            .binary = @embedFile("shaders/Include/GrainSimulation.spv"),
        },
    });
    sim.thermal_shader = try loadShaderProgram(arena, &.{
        .{
            .type = gl.COMPUTE_SHADER,
            .binary = @embedFile("shaders/Include/ThermalCompute.spv"),
        },
    });
    sim.grain_simulation_shader = try loadShaderProgram(arena, &.{
        .{
            .type = gl.COMPUTE_SHADER,
            .binary = @embedFile("shaders/Include/GrainSimulation.spv"),
        },
    });
    sim.fill_region_shader = try loadShaderProgram(arena, &.{
        .{
            .type = gl.COMPUTE_SHADER,
            .binary = @embedFile("shaders/Include/FillRegion.spv"),
        },
    });

    gl.CreateVertexArrays(1, @ptrCast(&sim.vertex_array));

    gl.CreateBuffers(1, @ptrCast(&sim.uniform_buffer));
    gl.CreateBuffers(1, @ptrCast(&sim.vertex_buffer));
    gl.CreateBuffers(2, &sim.simulation_material_buffers);
    gl.CreateBuffers(2, &sim.simulation_temperature_buffers);
    gl.CreateBuffers(2, &sim.simulation_deviation_buffers);
    gl.CreateBuffers(1, @ptrCast(&sim.heat_measurement_buffer));

    gl.CreateBuffers(1, @ptrCast(&sim.csg_instruction_buffer));
    gl.CreateBuffers(1, @ptrCast(&sim.csg_instructions_box_buffer));
    gl.CreateBuffers(1, @ptrCast(&sim.csg_instructions_sphere_buffer));
    gl.CreateBuffers(1, @ptrCast(&sim.csg_instructions_extrude_post_buffer));
    gl.CreateBuffers(1, @ptrCast(&sim.csg_transform_buffer));
    gl.CreateBuffers(1, @ptrCast(&sim.csg_composite_material_buffer));

    gl.CreateBuffers(1, @ptrCast(&sim.voxel_materials_buffer));
    gl.CreateBuffers(1, @ptrCast(&sim.voxel_materials_visual_buffer));
    gl.CreateBuffers(1, @ptrCast(&sim.point_light_buffer));

    // gl.CreateBuffers(1, &voxel_allocator_bins_buffer);
    // gl.CreateBuffers(1, &voxel_pallete_memory_buffer);
    // gl.CreateBuffers(1, &voxel_pallete_counters_buffer);
    // gl.CreateBuffers(1, &voxel_bit_buffer_memory_buffer);
    // gl.CreateBuffers(1, &voxel_temperature_memory_buffer);
    // gl.CreateBuffers(1, &voxel_allocator_buffer);
    // gl.CreateBuffers(1, &voxel_chunks_buffer);

    gl.VertexArrayVertexBuffer(
        sim.vertex_array,
        0,
        sim.vertex_buffer,
        0,
        @sizeOf([3]f32),
    );

    gl.EnableVertexArrayAttrib(sim.vertex_array, 0);
    gl.VertexArrayAttribFormat(
        sim.vertex_array,
        0,
        3,
        gl.FLOAT,
        gl.FALSE,
        0,
    );
    gl.VertexArrayAttribBinding(sim.vertex_array, 0, 0);

    const vertices = [_]f32{
        0.0, 0.0, 0.0,
        1.0, 1.0, 0.0,
        1.0, 0.0, 0.0,
        1.0, 1.0, 0.0,
        0.0, 0.0, 0.0,
        0.0, 1.0, 0.0,
        0.0, 0.0, 1.0,
        1.0, 0.0, 1.0,
        1.0, 1.0, 1.0,
        1.0, 1.0, 1.0,
        0.0, 1.0, 1.0,
        0.0, 0.0, 1.0,
        0.0, 1.0, 1.0,
        0.0, 1.0, 0.0,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        0.0, 0.0, 1.0,
        0.0, 1.0, 1.0,
        1.0, 1.0, 1.0,
        1.0, 0.0, 0.0,
        1.0, 1.0, 0.0,
        1.0, 0.0, 0.0,
        1.0, 1.0, 1.0,
        1.0, 0.0, 1.0,
        0.0, 0.0, 0.0,
        1.0, 0.0, 0.0,
        1.0, 0.0, 1.0,
        1.0, 0.0, 1.0,
        0.0, 0.0, 1.0,
        0.0, 0.0, 0.0,
        0.0, 1.0, 0.0,
        1.0, 1.0, 1.0,
        1.0, 1.0, 0.0,
        1.0, 1.0, 1.0,
        0.0, 1.0, 0.0,
        0.0, 1.0, 1.0,
    };

    gl.NamedBufferStorage(
        sim.vertex_buffer,
        @sizeOf(@TypeOf(vertices)),
        &vertices,
        gl.DYNAMIC_STORAGE_BIT,
    );

    const buffer_length = sim.width * sim.height * sim.depth;

    gl.NamedBufferStorage(
        sim.simulation_material_buffers[0],
        buffer_length * @sizeOf(u16),
        null,
        gl.DYNAMIC_STORAGE_BIT,
    );

    gl.NamedBufferStorage(
        sim.simulation_material_buffers[1],
        buffer_length * @sizeOf(u16),
        null,
        gl.DYNAMIC_STORAGE_BIT,
    );

    gl.NamedBufferStorage(
        sim.simulation_temperature_buffers[0],
        buffer_length * @sizeOf(f32),
        null,
        gl.DYNAMIC_STORAGE_BIT,
    );

    gl.NamedBufferStorage(
        sim.simulation_temperature_buffers[1],
        buffer_length * @sizeOf(f32),
        null,
        gl.DYNAMIC_STORAGE_BIT,
    );

    gl.NamedBufferStorage(
        sim.simulation_deviation_buffers[0],
        buffer_length * @sizeOf(u8),
        null,
        gl.DYNAMIC_STORAGE_BIT,
    );

    gl.NamedBufferStorage(
        sim.simulation_deviation_buffers[1],
        buffer_length * @sizeOf(u8),
        null,
        gl.DYNAMIC_STORAGE_BIT,
    );

    gl.NamedBufferStorage(
        sim.heat_measurement_buffer,
        @sizeOf(f32),
        null,
        gl.DYNAMIC_STORAGE_BIT,
    );

    gl.NamedBufferData(
        sim.voxel_materials_buffer,
        @intCast(@sizeOf(VoxelMaterial) * sim.voxel_materials.items.len),
        sim.voxel_materials.items.ptr,
        gl.DYNAMIC_STORAGE_BIT,
    );

    gl.NamedBufferData(
        sim.voxel_materials_visual_buffer,
        @intCast(@sizeOf(VoxelMaterialVisual) * sim.voxel_materials_visual.items.len),
        sim.voxel_materials_visual.items.ptr,
        gl.DYNAMIC_STORAGE_BIT,
    );

    gl.NamedBufferData(
        sim.uniform_buffer,
        @sizeOf(ShaderUniforms),
        null,
        gl.DYNAMIC_DRAW,
    );

    return sim;
}

pub fn deinit(sim: *Simulation, gpa: std.mem.Allocator) void {
    sim.csg_invocations.deinit(gpa);
}

pub fn update(sim: *Simulation) void {
    gl.NamedBufferData(
        sim.voxel_materials_buffer,
        @intCast(@sizeOf(VoxelMaterial) * sim.voxel_materials.items.len),
        sim.voxel_materials.items.ptr,
        gl.DYNAMIC_DRAW,
    );
    gl.NamedBufferData(
        sim.voxel_materials_visual_buffer,
        @intCast(@sizeOf(VoxelMaterialVisual) * sim.voxel_materials_visual.items.len),
        sim.voxel_materials_visual.items.ptr,
        gl.DYNAMIC_DRAW,
    );

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

    gl.NamedBufferSubData(
        sim.uniform_buffer,
        0,
        @sizeOf(ShaderUniforms),
        &shader_uniforms,
    );
    gl.NamedBufferData(
        sim.point_light_buffer,
        @intCast(@sizeOf(PointLight) * sim.point_lights.items.len),
        sim.point_lights.items.ptr,
        gl.DYNAMIC_DRAW,
    );

    gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, sim.uniform_buffer);
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 0, sim.simulation_temperature_buffers[0]);
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 1, sim.simulation_temperature_buffers[1]);
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 2, sim.voxel_materials_buffer);
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 23, sim.voxel_materials_visual_buffer);
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 3, 0);
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 4, sim.simulation_material_buffers[0]);
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 10, sim.csg_transform_buffer);
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 11, sim.csg_instruction_buffer);
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 12, sim.csg_instructions_box_buffer);
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 13, sim.csg_instructions_sphere_buffer);
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 30, sim.csg_instructions_extrude_post_buffer);
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 14, sim.csg_composite_material_buffer);
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 20, sim.simulation_deviation_buffers[0]);
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 21, sim.simulation_deviation_buffers[1]);
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 22, sim.point_light_buffer);
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 32, sim.heat_measurement_buffer);

    if (!sim.enable_simulation and sim.csg_dirty) {
        gl.UseProgram(sim.fill_region_shader);

        sim.csg_dirty = false;

        const material_clear: u16 = 0;
        const temperature_clear: f32 = 0;
        const deviation_clear: u8 = 0;

        gl.ClearNamedBufferData(
            sim.simulation_material_buffers[0],
            gl.R16UI,
            gl.RED,
            gl.UNSIGNED_SHORT,
            &material_clear,
        );
        gl.ClearNamedBufferData(
            sim.simulation_temperature_buffers[0],
            gl.R32UI,
            gl.RED,
            gl.FLOAT,
            &temperature_clear,
        );
        gl.ClearNamedBufferData(
            sim.simulation_deviation_buffers[0],
            gl.R8I,
            gl.RED,
            gl.BYTE,
            &deviation_clear,
        );

        gl.DispatchCompute(
            sim.width / 8,
            sim.height / 8,
            sim.depth / 8,
        );
    }

    gl.MemoryBarrier(gl.SHADER_STORAGE_BARRIER_BIT);

    if (sim.enable_simulation) {
        gl.ClearNamedBufferData(
            sim.heat_measurement_buffer,
            gl.R32F,
            gl.RED,
            gl.FLOAT,
            &@as(f32, 0),
        );

        gl.MemoryBarrier(gl.SHADER_STORAGE_BARRIER_BIT);

        gl.UseProgram(sim.thermal_shader);
        gl.DispatchCompute(
            sim.width / 8,
            sim.height / 8,
            sim.depth / 8,
        );
        gl.MemoryBarrier(gl.SHADER_STORAGE_BARRIER_BIT);

        gl.UseProgram(sim.grain_simulation_shader);
        gl.BindBufferBase(
            gl.SHADER_STORAGE_BUFFER,
            2,
            sim.voxel_materials_buffer,
        );

        gl.BindBufferBase(
            gl.SHADER_STORAGE_BUFFER,
            4,
            sim.simulation_material_buffers[0],
        );
        gl.BindBufferBase(
            gl.SHADER_STORAGE_BUFFER,
            5,
            sim.simulation_material_buffers[1],
        );

        gl.BindBufferBase(
            gl.SHADER_STORAGE_BUFFER,
            6,
            sim.simulation_temperature_buffers[1],
        );
        gl.BindBufferBase(
            gl.SHADER_STORAGE_BUFFER,
            7,
            sim.simulation_temperature_buffers[0],
        );

        gl.DispatchCompute(
            sim.width / 8,
            sim.height / 8,
            sim.depth / 8,
        );

        gl.MemoryBarrier(gl.SHADER_STORAGE_BARRIER_BIT);

        gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 3, 0);
        gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 2, 0);
        gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 1, 0);
        gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 0, 0);
        gl.BindBufferBase(gl.UNIFORM_BUFFER, 0, 0);
    }

    if (sim.enable_simulation) {
        std.mem.swap(
            u32,
            &sim.simulation_material_buffers[0],
            &sim.simulation_material_buffers[1],
        );

        std.mem.swap(
            u32,
            &sim.simulation_deviation_buffers[0],
            &sim.simulation_deviation_buffers[1],
        );

        sim.timestep_index += 1;

        gl.MemoryBarrier(gl.SHADER_STORAGE_BARRIER_BIT);

        //TODO: hard cpu-gpu sync here, must change when porting to vulkan
        gl.GetNamedBufferSubData(
            sim.heat_measurement_buffer,
            0,
            @sizeOf(i32),
            &sim.measured_heat,
        );
    }
}

pub fn render(sim: *Simulation, render_texture: ?u32) void {
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

    gl.NamedBufferSubData(
        sim.uniform_buffer,
        0,
        @sizeOf(ShaderUniforms),
        &shader_uniforms,
    );

    gl.BindBufferBase(
        gl.SHADER_STORAGE_BUFFER,
        0,
        sim.voxel_materials_buffer,
    );
    gl.BindBufferBase(
        gl.SHADER_STORAGE_BUFFER,
        1,
        sim.simulation_material_buffers[0],
    );
    gl.BindBufferBase(
        gl.SHADER_STORAGE_BUFFER,
        2,
        sim.simulation_temperature_buffers[0],
    );
    gl.BindBufferBase(
        gl.SHADER_STORAGE_BUFFER,
        21,
        sim.simulation_deviation_buffers[0],
    );

    gl.BindBufferBase(
        gl.SHADER_STORAGE_BUFFER,
        22,
        sim.point_light_buffer,
    );

    gl.MemoryBarrier(gl.SHADER_IMAGE_ACCESS_BARRIER_BIT);

    var framebuffer: u32 = 0;
    var renderbuffer: u32 = 0;

    if (render_texture) |texture| {
        gl.CreateFramebuffers(1, @ptrCast(&framebuffer));

        gl.BindFramebuffer(gl.FRAMEBUFFER, framebuffer);
        gl.FramebufferTexture2D(
            gl.FRAMEBUFFER,
            gl.COLOR_ATTACHMENT0,
            gl.TEXTURE_2D,
            texture,
            0,
        );

        gl.CreateRenderbuffers(1, @ptrCast(&renderbuffer));

        gl.BindRenderbuffer(gl.RENDERBUFFER, renderbuffer);
        gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH24_STENCIL8, 128, 128);
        gl.BindRenderbuffer(gl.RENDERBUFFER, 0);

        gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_STENCIL_ATTACHMENT, gl.RENDERBUFFER, renderbuffer);

        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    }

    gl.UseProgram(sim.renderer_program);
    gl.BindVertexArray(sim.vertex_array);
    gl.CullFace(gl.FRONT);
    defer gl.CullFace(gl.BACK);
    gl.Enable(gl.CULL_FACE);

    gl.DrawArrays(gl.TRIANGLES, 0, 36);

    gl.BindFramebuffer(gl.FRAMEBUFFER, 0);

    if (render_texture) |_| {
        gl.DeleteFramebuffers(1, @ptrCast(&framebuffer));
        gl.DeleteRenderbuffers(1, @ptrCast(&renderbuffer));
    }
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

pub const ShaderSource = struct {
    type: u32 = 0,
    binary: []const u8,
};

pub fn loadShaderProgram(
    arena: std.mem.Allocator,
    sources: []const ShaderSource,
) !u32 {
    const program = gl.CreateProgram();

    if (program == 0) return error.ProgramCreationFailed;

    var shaders: [8]u32 = undefined;

    for (sources, 0..) |source, i| {
        shaders[i] = try loadShader(source);

        gl.AttachShader(program, shaders[i]);
    }

    gl.LinkProgram(program);

    var link_status: i32 = 0;

    gl.GetProgramiv(program, gl.LINK_STATUS, @ptrCast(&link_status));

    if (link_status == 0) {
        var info_log_length: i32 = 0;

        gl.GetProgramiv(
            program,
            gl.INFO_LOG_LENGTH,
            @ptrCast(&info_log_length),
        );

        const info_log = try arena.alloc(u8, @intCast(info_log_length));

        std.log.err(
            "[OpenGL]: Shader Program failed to link: {s}\n",
            .{info_log},
        );

        return error.FailedToLink;
    }

    for (shaders) |shader| {
        gl.DetachShader(program, shader);
        gl.DeleteShader(shader);
    }

    return program;
}

pub fn loadShader(source: ShaderSource) !u32 {
    const shader = gl.CreateShader(source.type);

    gl.ShaderBinary(
        1,
        @ptrCast(&shader),
        gl.SHADER_BINARY_FORMAT_SPIR_V,
        source.binary.ptr,
        @intCast(source.binary.len),
    );

    gl.SpecializeShader(
        shader,
        "main",
        0,
        undefined,
        undefined,
    );

    var success: i32 = 0;

    gl.GetShaderiv(
        shader,
        gl.COMPILE_STATUS,
        @ptrCast(&success),
    );

    if (success == 0) {
        return error.ShaderRejectedBinary;
    }

    return shader;
}

const std = @import("std");
const Simulation = @This();
const gl = @import("gl");
const math = @import("math.zig");
const zmath = @import("zmath");
