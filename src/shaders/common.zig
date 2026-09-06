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

pub const SimulationState = extern struct {
    voxel_material_ids: GpuPointer(VoxelMaterialId),
    voxel_temperatures: GpuPointer(f32),
    voxel_deviations: GpuPointer(i8),
    voxel_materials: GpuPointer(VoxelMaterial),

    voxel_bit_buffer_sampler: spirv_ext.SamplerHeap.Index,
    voxel_chunk_positions_sampler: spirv_ext.SamplerHeap.Index,

    enable_radiative_cooling: bool,
    substep_index: u32,
    size: [3]u32,
    filled_bounds_min: [3]i32,
    filled_bounds_max: [3]i32,

    voxel_allocator: VoxelChunkAllocator,

    pub const LoadStoreToken = packed struct(u64) {
        load_offset: u32,
        store_offset: u32,
    };

    pub fn loadVoxelMaterial(
        self: *addrspace(address_space) SimulationState,
        voxel_material_id: VoxelMaterialId,
    ) VoxelMaterial {
        return self.voxel_materials.toPointerMulti()[@backingInt(voxel_material_id)];
    }

    pub fn loadVoxelMaterialId(
        self: *addrspace(address_space) SimulationState,
        pos: @Vector(3, i32),
    ) VoxelMaterialId {
        const heap_pos = self.voxelWorldPosToHeapPos(pos);

        return self.loadVoxelMaterialIdHeapPos(heap_pos);
    }

    pub fn loadVoxelTemperature(
        self: *addrspace(address_space) SimulationState,
        pos: @Vector(3, i32),
    ) f32 {
        const heap_pos = self.voxelWorldPosToHeapPos(pos);

        return self.loadVoxelTemperatureHeapPos(heap_pos);
    }

    pub fn loadVoxelMaterialIdHeapPos(
        self: *addrspace(address_space) SimulationState,
        pos: @Vector(3, i32),
    ) VoxelMaterialId {
        const heap_index = voxelHeapIndexFromHeapPos(pos);

        return self.voxel_material_ids.toPointerMulti()[heap_index];
    }

    pub fn loadVoxelTemperatureHeapPos(
        self: *addrspace(address_space) SimulationState,
        pos: @Vector(3, i32),
    ) f32 {
        const heap_index = voxelHeapIndexFromHeapPos(pos);

        return self.voxel_temperatures.toPointerMulti()[heap_index];
    }

    pub fn voxelWorldPosToHeapPos(
        self: *addrspace(address_space) SimulationState,
        pos: @Vector(3, i32),
    ) @Vector(3, i32) {
        _ = self; // autofix
        return pos;
    }

    pub fn voxelHeapIndexFromHeapPos(pos: [3]i32) u32 {
        return mortonEncode(@bitCast(pos));
    }

    fn morton1ExpandPartBy2(value: u32) u32 {
        var x: u32 = value;
        x &= 0x000003ff; // x = ---- ---- ---- ---- ---- --98 7654 3210
        x = (x ^ (x << 16)) & 0xff0000ff; // x = ---- --98 ---- ---- ---- ---- 7654 3210
        x = (x ^ (x << 8)) & 0x0300f00f; // x = ---- --98 ---- ---- 7654 ---- ---- 3210
        x = (x ^ (x << 4)) & 0x030c30c3; // x = ---- --98 ---- 76-- --54 ---- 32-- --10
        x = (x ^ (x << 2)) & 0x09249249; // x = ---- 9--8 --7- -6-- 5--4 --3- -2-- 1--0
        return x;
    }

    fn mortonCompact1PartBy2(value: u32) u32 {
        var x = value;
        x &= 0x09249249; // x = ---- 9--8 --7- -6-- 5--4 --3- -2-- 1--0
        x = (x ^ (x >> 2)) & 0x030c30c3; // x = ---- --98 ---- 76-- --54 ---- 32-- --10
        x = (x ^ (x >> 4)) & 0x0300f00f; // x = ---- --98 ---- ---- 7654 ---- ---- 3210
        x = (x ^ (x >> 8)) & 0xff0000ff; // x = ---- --98 ---- ---- ---- ---- 7654 3210
        x = (x ^ (x >> 16)) & 0x000003ff; // x = ---- ---- ---- ---- ---- --98 7654 3210
        return x;
    }

    ///Morton code calculation as shown by https://fgiesen.wordpress.com/2009/12/13/decoding-morton-codes/
    fn mortonEncode(position: [3]u32) u32 {
        return (morton1ExpandPartBy2(position[2]) << 2) + (morton1ExpandPartBy2(position[1]) << 1) + morton1ExpandPartBy2(position[0]);
    }

    fn mortonDecode(morton: u32) [3]i32 {
        const x = mortonCompact1PartBy2(morton >> 0);
        const y = mortonCompact1PartBy2(morton >> 1);
        const z = mortonCompact1PartBy2(morton >> 2);
        return .{ @intCast(x), @intCast(y), @intCast(z) };
    }
};

pub const SimulationRenderingState = extern struct {
    view_projection: [4][4]f32,
    renderer_mode: u32,

    draws: GpuPointer(RasterDrawCommand),

    voxel_materials_visual: GpuPointer(VoxelMaterialVisual),
    point_lights: GpuSlice(PointLight),
    spot_lights: GpuSlice(SpotLight),
};

pub const VoxelChunkAllocator = extern struct {
    slabs: GpuPointer(VoxelChunkSlab),
    slab_bins: [15]i32,
    slab_bump: u32,

    allocations: GpuPointer(ChunkAllocation),

    temperature_bump: u32,
    pallete_bump: u32,
    pallete_counters_bump: u32,
    bit_buffer_bump: u32,
    chunk_grid_size: [3]u32,
    allocation_lock: u32,
};

///Slab of 32 chunks
pub const VoxelChunkSlab = extern struct {
    next_allocator: i32,
    pallete_memory_start: u32,
    pallete_counters_start: u32,
    bit_buffer_memory_start: u32,
    temperature_buffer_start: u32,
    deviation_buffer_start: u32,

    ///Bitfield where each bit represents a chunk
    chunk_allocated_bits: u32,
};

pub const ChunkAllocation = packed struct(u64) {
    allocation_index: u32,
    bit_count: u32,

    //TODO move this somewhere else?
    pub const chunk_volume = chunk_size * chunk_size * chunk_size;
    pub const voxels_in_a_metre = 500.0;
    pub const voxel_side_length = 1.0 / voxels_in_a_metre;
    pub const voxel_face_area = voxel_side_length * voxel_side_length;
    pub const voxel_volume = voxel_face_area * voxel_side_length;
    pub const carbon_molar_mass = 12.0 / 1000.0;
    pub const carbon_graphite_density = 2267.0;
    pub const voxel_molarity = voxel_volume * (carbon_graphite_density / carbon_molar_mass);
};

pub const RayStats = extern struct {
    total_primary_rays: u32,
    total_primary_ray_hits: u32,
    total_primary_ray_steps: u32,
    max_primary_ray_steps: u32,
    min_primary_ray_steps: u32,
    total_secondary_rays: u32,
    total_secondary_ray_steps: u32,
    max_secondary_ray_steps: u32,
    min_secondary_ray_steps: u32,
};

pub const VoxelMaterialId = enum(u16) {
    air = 0,
    _,
};

pub const VoxelMaterial = extern struct {
    molar_mass: f32,
    density: f32,
    heat_conductivity: f32,
    thermal_emissivity: f32,
    heat_capacity: f32,
    melting_point: f32,
    boiling_point: f32,
};

pub const VoxelMaterialVisual = extern struct {
    albedo: u32,
    roughness_metalness: u32,
    reflectivity: f32,
    refractive_index: f32,
};

pub const PointLight = extern struct {
    position: [3]f32,
    radiance: f32,
    color: u32,
};

pub const SpotLight = extern struct {
    position: [3]f32,
    radiance: f32,
    orientation: [3]f32,
    color: u32,
    inner_angle: f32,
    outer_angle: f32,
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
    simulation_read_offset: u32,
    simulation_write_offset: u32,
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

pub const RasterDrawCommand = extern struct {
    count: u32,
    instance_count: u32,
    first: u32,
    base_instance: u32,
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

const address_space: std.builtin.AddressSpace = switch (@import("builtin").cpu.arch) {
    .spirv32, .spirv64 => .physical_storage_buffer,
    else => std.builtin.AddressSpace.generic,
};

const GpuPointer = spirv_ext.GpuPointer;
const GpuSlice = spirv_ext.GpuSlice;
const spirv_ext = @import("spirv_ext.zig");
const math = @import("../math.zig");
const std = @import("std");
const zmath = @import("zmath");
