pub const Simulation = struct {
    renderer_program: u32 = 0,
    vertex_array: u32 = 0,
    vertex_buffer: u32 = 0,

    simulation_material_buffers: [2]u32 = .{ 0, 0 },
    simulation_deviation_buffers: [2]u32 = .{ 0, 0 },
    simulation_temperature_buffers: [2]u32 = .{ 0, 0 },

    heat_measurement_buffer: u32 = 0,

    voxel_materials_buffer: u32 = 0,
    voxel_materials_visual_buffer: u32 = 0,

    simulation_shader: u32 = 0,
    thermal_shader: u32 = 0,
    grain_simulation_shader: u32 = 0,
    fill_region_shader: u32 = 0,

    point_light_buffer: u32 = 0,

    uniform_buffer: u32 = 0,

    csg_instruction_buffer: u32 = 0,
    csg_instructions_box_buffer: u32 = 0,
    csg_instructions_sphere_buffer: u32 = 0,
    csg_instructions_extrude_post_buffer: u32 = 0,
    csg_transform_buffer: u32 = 0,
    csg_composite_material_buffer: u32 = 0,

    pub fn init(arena: std.mem.Allocator) !Simulation {
        var sim: Simulation = undefined;

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
    }

    pub fn deinit() void {}

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

    pub fn update(sim: Simulation) void {
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

    pub fn render(sim: Simulation, shader_uniforms: ShaderUniforms, render_texture: ?*Texture) void {
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
                @intFromPtr(texture),
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

const ShaderUniforms = @import("../Simulation.zig").ShaderUniforms;
const VoxelMaterial = @import("../Simulation.zig").VoxelMaterial;
const VoxelMaterialVisual = @import("../Simulation.zig").VoxelMaterialVisual;
const PointLight = @import("../Simulation.zig").PointLight;
const CSGProgram = @import("../Simulation.zig").CSGProgram;
const CSGRigidTransform = @import("../Simulation.zig").CSGRigidTransform;
const CSGInstruction = @import("../Simulation.zig").CSGInstruction;
const CSGInstructionBox = @import("../Simulation.zig").CSGInstructionBox;
const CSGInstructionSphere = @import("../Simulation.zig").CSGInstructionSphere;
const CSGInstructionExtrudePost = @import("../Simulation.zig").CSGInstructionExtrudePost;
const std = @import("std");
const Texture = @import("../gpu.zig").Texture;
const gl = @import("gl");
