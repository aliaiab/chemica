
#extension GL_EXT_shader_16bit_storage : enable
#extension GL_ARB_gpu_shader_int64 : enable
#extension GL_EXT_shader_atomic_int64 : enable
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require
#extension GL_EXT_shader_explicit_arithmetic_types : enable

#ifndef _BUFFERS
#define _BUFFERS

const uint buffer_binding_start = 16;

#define ChunkAllocation uint

struct AffineTransform3D {
    //TODO: store inverse position, inverse rotation and inverse scale(maybe)
    vec3 position;
    float uniform_scale;
    //Quaternion rotation
    vec4 rotation;
};

struct ChunkBufferAllocation {
    ChunkAllocation allocation;
    uint bit_count;
};

struct VoxelChunkAllocator {
    int next_allocator;

    uint pallete_memory_start;
    uint pallete_counters_start;
    uint bit_buffer_memory_start;
    uint temperature_buffer_start;
    uint deviation_buffer_start;

    //TODO: seperate this into a seperate struct as these are only accessed when allocating
    //Bit sets containing whether an allocation is free or not
    uint memory_allocated_bits;
};

layout(std140, binding = buffer_binding_start) restrict readonly buffer Uniforms {
    //Rendering Parameters
    mat4 uModel;
    mat4 uView;
    mat4 uProjection;

    //Simulation Parameters
    uvec3 uSize;
    ivec3 uBaseVelocity;
    uint substep_index;

    //CSG parameters
    AffineTransform3D root_transform;
    ivec3 csg_bounding_min;
    ivec3 csg_bounding_max;
    float delta_time;
    uvec2 window_size;
    bool enable_radiative_cooling;
    uint renderer_mode;
    uint sdf_texture_root;
    //Indices which represent which part of the double buffered voxel data to read/write to
    //Measured in voxels
    uint simulation_read_offset;
    uint simulation_write_offset;
};

layout(std430, binding = buffer_binding_start + 1) restrict buffer VoxelPalleteCounters
{
    int voxel_pallete_counters[];
};

layout(std430, binding = buffer_binding_start + 2) restrict buffer VoxelChunkTemperatureMemory
{
    float16_t voxel_chunk_temperature_memory[];
};

layout(std430, binding = buffer_binding_start + 3) restrict coherent buffer VoxelAllocatorBuffer
{
    VoxelChunkAllocator voxel_allocators[];
};

layout(std430, binding = buffer_binding_start + 4) restrict coherent buffer VoxelAllocatorBins {
    //Indexed by bit count - 1
    //Contains indices into voxel_allocators
    int voxel_allocator_bin[15];
    uint allocators_bump;
    uint voxel_temperature_bump;
    uint voxel_pallete_bump;
    uint voxel_pallete_counters_bump;
    uint voxel_bit_buffer_bump;
    //Index of the chunk grid used as input (t0), 0 or 1,
    //output_chunk_grid = 1 - input_chunk_grid
    uint input_chunk_grid;
    uvec3 chunk_grid_size;
    uint allocation_lock;
};

layout(std430, binding = buffer_binding_start + 5) restrict coherent buffer VoxelChunkBufferAllocation
{
    ChunkBufferAllocation voxel_chunks_allocation[];
};

#if 0
layout(std430, binding = buffer_binding_start + 6) restrict buffer VoxelHeapBitBuffer
{
    uint16_t voxel_heap_bit_buffer[];
};

layout(std430, binding = buffer_binding_start + 7) restrict buffer VoxelChunkPositionsBuffer
{
    uint voxel_chunk_positions_buffer[];
};

layout(std430, binding = buffer_binding_start + 8) restrict buffer VoxelChunkPalleteMemory
{
    uint16_t voxel_chunk_pallete_memory[];
};
#endif
#endif
