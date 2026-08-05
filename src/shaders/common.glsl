#extension GL_EXT_shader_16bit_storage : enable
#extension GL_ARB_gpu_shader_int64 : enable
#extension GL_EXT_shader_atomic_int64 : enable
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require
#extension GL_EXT_shader_explicit_arithmetic_types : enable

#define VOXEL_PHASE_SOLID 0
#define VOXEL_PHASE_LIQUID 1
#define VOXEL_PHASE_GAS 2

//TODO: Make material data SOA/data oriented
struct VoxelMaterial
{
    float molar_mass;
    float density;
    float heat_conductivity;
    float thermal_emissivity;
    float heat_capacity;
    float melting_point;
    float boiling_point;
};

//The visual material
struct VoxelMaterialVisual
{
    uint albedo;
    //x = roughness, y = metalness
    uint roughness_metalness;
    float reflectivity;
    float refractive_index;
};

#if 0
layout(std430, binding = 24) restrict buffer VoxelChunkPalleteMemory
{
    uint16_t voxel_chunk_pallete_memory[];
};
#endif

layout(std430, binding = 31) restrict buffer VoxelPalleteCounters
{
    int voxel_pallete_counters[];
};

layout(std430, binding = 26) restrict buffer VoxelChunkTemperatureMemory
{
    float16_t voxel_chunk_temperature_memory[];
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

layout(std430, binding = 27) restrict coherent buffer VoxelAllocatorBuffer
{
    VoxelChunkAllocator voxel_allocators[];
};

layout(std430, binding = 28) restrict coherent buffer VoxelAllocatorBins {
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

//TODO: make this a specialization constant
#define VOXELS_IN_A_METRE 500.0f
//The side length of a voxel in metres
#define VOXEL_SIDE_LENGTH (1.0f / VOXELS_IN_A_METRE)
#define VOXEL_FACE_AREA VOXEL_SIDE_LENGTH * VOXEL_SIDE_LENGTH
#define VOXEL_VOLUME VOXEL_FACE_AREA * VOXEL_SIDE_LENGTH

//kgmol^-1
#define CARBON_MOLAR_MASS (12.0f / 1000.0f)
//kgm^-3
#define CARBON_GRAPHITE_DENSITY (2267.0f)
//The number of moles in a (solid or liquid) voxel
#define VOXEL_MOLARITY (VOXEL_VOLUME * (CARBON_GRAPHITE_DENSITY / CARBON_MOLAR_MASS))

#define CHUNK_SIZE 16
#define CHUNK_VOLUME (CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE)

#define ChunkAllocation uint

struct ChunkBufferAllocation {
    ChunkAllocation allocation;
    uint bit_count;
};

layout(std430, binding = 29) restrict coherent buffer VoxelChunkBufferAllocation
{
    ChunkBufferAllocation voxel_chunks_allocation[];
};

int bitScanForward(uint x) {
    x = x & -x;

    int count = 0;

    if ((x & 0xffff0000) != 0) count += 16;
    if ((x & 0xff00ff00) != 0) count += 8;
    if ((x & 0xf0f0f0f0) != 0) count += 4;
    if ((x & 0xcccccccc) != 0) count += 2;
    if ((x & 0xaaaaaaaa) != 0) count += 1;
    return count;
}

struct AffineTransform3D {
    //TODO: store inverse position, inverse rotation and inverse scale(maybe)
    vec3 position;
    float uniform_scale;
    //Quaternion rotation
    vec4 rotation;
};

layout(std140, binding = 0) uniform Uniforms
{
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
};

#define RENDERER_MODE_PBR 0
#define RENDERER_MODE_ALBEDO 1
#define RENDERER_MODE_ROUGHNESS 2
#define RENDERER_MODE_METALNESS 3
#define RENDERER_MODE_AMBIENT_OCCLUSION 4
#define RENDERER_MODE_NORMAL 5
#define RENDERER_MODE_MATERIAL 6
#define RENDERER_MODE_DEVIATION 7
#define RENDERER_MODE_TEMPERATURE 8
#define RENDERER_MODE_RAY_STEPS 9

bool isInBounds(ivec3 position) {
    return all(greaterThanEqual(position, ivec3(0))) && all(lessThan(position, uSize));
}

bool isInBoundsInclusive(ivec3 position) {
    return all(greaterThanEqual(position, ivec3(0))) && all(lessThanEqual(position, uSize));
}

bool isInBlock(ivec3 local_position) {
    return all(greaterThanEqual(local_position, ivec3(0))) && all(lessThan(local_position, ivec3(2)));
}

struct PointLight {
    vec3 position;
    float radiance;
    uint colour;
};

struct SpotLight {
    vec3 position;
    float radiance;
    vec3 orientation;
    uint colour;
    float inner_angle;
    float outer_angle;
};

int newAllocator(uint bit_count) {
    uint allocator = atomicAdd(allocators_bump, 1);
    voxel_allocators[allocator].memory_allocated_bits = 0xffffffff;
    voxel_allocators[allocator].next_allocator = -1;

    voxel_allocators[allocator].pallete_counters_start = atomicAdd(voxel_pallete_counters_bump, 32);
    //voxel_allocators[allocator].bit_buffer_memory_start = atomicAdd(voxel_bit_buffer_bump, bit_count * (CHUNK_SIZE * CHUNK_SIZE / 2) * 32);
    voxel_allocators[allocator].pallete_memory_start = atomicAdd(voxel_pallete_bump, (1 << bit_count) * 32);
    voxel_allocators[allocator].temperature_buffer_start = atomicAdd(voxel_temperature_bump, CHUNK_VOLUME * 32);

    voxel_allocators[allocator].bit_buffer_memory_start = atomicAdd(voxel_bit_buffer_bump, CHUNK_VOLUME * 32);

    return int(allocator);
}

ChunkAllocation voxelChunkAlloc(uint bit_count) {
    while (atomicCompSwap(allocation_lock, 0, 1) != 0) {}

    int allocator_index = voxel_allocator_bin[bit_count - 1];

    if (allocator_index == -1) {
        voxel_allocator_bin[bit_count - 1] = newAllocator(bit_count);
    }

    VoxelChunkAllocator alloc = voxel_allocators[allocator_index];

    //If allocated bits == 0 then it is full
    while (voxel_allocators[allocator_index].memory_allocated_bits == 0) {
        if (voxel_allocators[allocator_index].next_allocator == -1) {
            //Create new allocator and push it to the front of the bin
            int new_allocator = newAllocator(bit_count);
            voxel_allocator_bin[bit_count - 1] = new_allocator;
            voxel_allocators[new_allocator].next_allocator = allocator_index;
            allocator_index = new_allocator;
            break;
        }

        allocator_index = alloc.next_allocator;
    }

    alloc = voxel_allocators[allocator_index];

    int allocation_index = bitScanForward(alloc.memory_allocated_bits);
    voxel_allocators[allocator_index].memory_allocated_bits = alloc.memory_allocated_bits ^ (1 << allocation_index);

    memoryBarrier();

    atomicExchange(allocation_lock, 0);

    ChunkAllocation allocation = 0;

    allocation = bitfieldInsert(allocation, allocator_index, 5, 27);
    allocation = bitfieldInsert(allocation, allocation_index, 0, 5);

    return allocation;
}

void voxelChunkFree(ChunkAllocation allocation) {
    uint allocator_index = bitfieldExtract(allocation, 5, 27);
    uint allocation_index = bitfieldExtract(allocation, 0, 5);

    atomicOr(voxel_allocators[allocator_index].memory_allocated_bits, 1 << allocator_index);

    if (voxel_allocators[allocation_index].memory_allocated_bits == 0xffffffff) {
        //TODO: free the allocator
    }
}

#define VOXEL_HEAP_MODE_SSBO 0
#define VOXEL_HEAP_MODE_3D_TEXTURE 1

#define VOXEL_HEAP_MODE VOXEL_HEAP_MODE_3D_TEXTURE
#define USE_CHUNKING 1

uniform layout(binding = 0, r16ui) restrict uimage3D voxel_bit_buffer_texture;
uniform layout(binding = 1, r32ui) restrict uimage3D voxel_chunk_allocations_image;
//Stores positions as linearized indicies into the flat space of the voxel bit buffer image
uniform layout(binding = 2, r16ui) restrict uimage3D voxel_chunk_positions_image;

uniform layout(binding = 3, r32ui) restrict uimage3D voxel_temperature_image;
uniform layout(binding = 4, r8ui) restrict uimage3D voxel_deviation_image;

uniform layout(binding = 10) usampler3D voxel_bit_buffer_sampler;
uniform layout(binding = 11) usampler3D voxel_chunk_positions_sampler;
uniform layout(binding = 12) sampler3D voxel_temperature_sampler;
uniform layout(binding = 13) isampler3D voxel_deviation_sampler;

#if VOXEL_HEAP_MODE == VOXEL_HEAP_MODE_SSBO
layout(std430, binding = 35) restrict buffer VoxelHeapBitBuffer
{
    uint16_t voxel_heap_bit_buffer[];
};

layout(std430, binding = 36) restrict buffer VoxelChunkPositionsBuffer
{
    uint voxel_chunk_positions_buffer[];
};
#endif

uint voxelChunkHeapIndexFromHeapPosition(ivec3 heap_position) {
    ivec3 brickmap_size = imageSize(voxel_bit_buffer_texture) / CHUNK_SIZE;

    return heap_position.x + heap_position.y * brickmap_size.x + heap_position.z * (brickmap_size.x * brickmap_size.y);
}

#define USE_MORTON_ORDER 1

uint morton1ExpandPartBy2(uint value) {
    uint x = value;
    x &= 0x000003ff; // x = ---- ---- ---- ---- ---- --98 7654 3210
    x = (x ^ (x << 16)) & 0xff0000ff; // x = ---- --98 ---- ---- ---- ---- 7654 3210
    x = (x ^ (x << 8)) & 0x0300f00f; // x = ---- --98 ---- ---- 7654 ---- ---- 3210
    x = (x ^ (x << 4)) & 0x030c30c3; // x = ---- --98 ---- 76-- --54 ---- 32-- --10
    x = (x ^ (x << 2)) & 0x09249249; // x = ---- 9--8 --7- -6-- 5--4 --3- -2-- 1--0
    return x;
}

uint mortonCompact1PartBy2(uint value) {
    uint x = value;
    x &= 0x09249249; // x = ---- 9--8 --7- -6-- 5--4 --3- -2-- 1--0
    x = (x ^ (x >> 2)) & 0x030c30c3; // x = ---- --98 ---- 76-- --54 ---- 32-- --10
    x = (x ^ (x >> 4)) & 0x0300f00f; // x = ---- --98 ---- ---- 7654 ---- ---- 3210
    x = (x ^ (x >> 8)) & 0xff0000ff; // x = ---- --98 ---- ---- ---- ---- 7654 3210
    x = (x ^ (x >> 16)) & 0x000003ff; // x = ---- ---- ---- ---- ---- --98 7654 3210
    return x;
}

///Morton code calculation as shown by https://fgiesen.wordpress.com/2009/12/13/decoding-morton-codes/
uint mortonEncode(ivec3 position) {
    return (morton1ExpandPartBy2(position.z) << 2) + (morton1ExpandPartBy2(position.y) << 1) + morton1ExpandPartBy2(position.x);
}

ivec3 mortonDecode(uint morton) {
    uint x = mortonCompact1PartBy2(morton >> 0);
    uint y = mortonCompact1PartBy2(morton >> 1);
    uint z = mortonCompact1PartBy2(morton >> 2);
    return ivec3(uvec3(x, y, z));
}

uint voxelHeapIndexFromHeapPosition(ivec3 heap_position) {
    ivec3 brickmap_size = imageSize(voxel_bit_buffer_texture);

    #if USE_MORTON_ORDER
    return mortonEncode(heap_position);
    #else
    return heap_position.x + heap_position.y * brickmap_size.x + heap_position.z * (brickmap_size.x * brickmap_size.y);
    #endif
}

ivec3 voxelChunkHeapPositionFromHeapIndex(uint heap_index) {
    int voxel_count_length = imageSize(voxel_bit_buffer_texture).x / CHUNK_SIZE;

    #if !USE_CHUNKING
    return mortonDecode(heap_index);
    #endif

    #if !USE_MORTON_ORDER
    uint x = heap_index / (voxel_count_length * voxel_count_length);
    uint y = (heap_index / voxel_count_length) & (voxel_count_length - 1);
    uint z = heap_index & (voxel_count_length - 1);

    return ivec3(uvec3(x, y, z));
    #else
    return mortonDecode(heap_index);
    #endif
}

///Returns the position of the allocation within the voxel heap in chunk space
ivec3 voxelChunkAllocationHeapPosition(ChunkAllocation allocation) {
    uint allocator_index = bitfieldExtract(allocation, 5, 27);
    uint allocation_index = bitfieldExtract(allocation, 0, 5);

    VoxelChunkAllocator allocator = voxel_allocators[allocator_index];

    uint heap_index = allocator.bit_buffer_memory_start / CHUNK_VOLUME + allocation_index;

    return voxelChunkHeapPositionFromHeapIndex(heap_index);
}

#define NULL_HEAP_INDEX 0xffff
#define NULL_HEAP_POS ivec3(2147483647)

uint voxelChunkPosToChunkIndex(ivec3 chunk_pos) {
    ivec3 size = imageSize(voxel_chunk_allocations_image);
    return chunk_pos.x + chunk_pos.y * size.x + chunk_pos.z * size.x * size.y;
}

ivec3 voxelWorldPosToHeapPos(ivec3 voxel_world_pos) {
    uvec3 chunk_pos = voxel_world_pos / CHUNK_SIZE;
    uvec3 chunk_offset = voxel_world_pos - chunk_pos * CHUNK_SIZE;

    #ifdef DISABLE_CHUNKING
    return voxel_world_pos;
    #endif

    #if (VOXEL_HEAP_MODE != VOXEL_HEAP_MODE_SSBO)
    uint heap_index = texelFetch(voxel_chunk_positions_sampler, ivec3(chunk_pos), 0).r;
    #else
    uint heap_index = voxel_chunk_positions_buffer[voxelChunkPosToChunkIndex(ivec3(chunk_pos))];
    #endif

    if (heap_index == NULL_HEAP_INDEX) {
        return NULL_HEAP_POS;
    }
    ivec3 heap_pos = voxelChunkHeapPositionFromHeapIndex(heap_index);

    return heap_pos * CHUNK_SIZE + ivec3(chunk_offset);
}

uint loadVoxelMaterialHeapPos(ivec3 heap_pos) {
    if (heap_pos == NULL_HEAP_POS) {
        return 0;
    }

    #ifdef DISABLE_CHUNKING
    return uVoxelMaterials[voxelHeapIndexFromHeapPosition(heap_pos)];
    #endif

    #if VOXEL_HEAP_MODE == VOXEL_HEAP_MODE_SSBO
    return voxel_heap_bit_buffer[voxelHeapIndexFromHeapPosition(heap_pos)];
    #else
    return texelFetch(voxel_bit_buffer_sampler, heap_pos, 0).r;
    #endif
}

//Fetches the voxel material index at the given voxel position
uint loadVoxelMaterial(ivec3 pos) {
    ivec3 heap_pos = voxelWorldPosToHeapPos(pos);

    return loadVoxelMaterialHeapPos(heap_pos);
}

//Fetches the voxel material index at the given voxel position
float loadVoxelTemperatureHeapPos(ivec3 heap_pos) {
    if (heap_pos == NULL_HEAP_POS) {
        return 0;
    }

    #ifdef DISABLE_CHUNKING
    return uVoxelTemperatures[mortonEncode(heap_pos)];
    #endif

    #if VOXEL_HEAP_MODE == VOXEL_HEAP_MODE_SSBO
    return 0;
    #else
    return texelFetch(voxel_temperature_sampler, heap_pos, 0).r;
    #endif
}

//Fetches the voxel material index at the given voxel position
float loadVoxelTemperature(ivec3 pos) {
    ivec3 heap_pos = voxelWorldPosToHeapPos(pos);

    return loadVoxelTemperatureHeapPos(heap_pos);
}

//Fetches the voxel material index at the given voxel position
int loadVoxelDeviationHeapPos(ivec3 heap_pos) {
    if (heap_pos == NULL_HEAP_POS) {
        return 0;
    }

    #ifdef DISABLE_CHUNKING
    return out_deviation_buffer[mortonEncode(heap_pos)];
    #endif

    #if VOXEL_HEAP_MODE == VOXEL_HEAP_MODE_SSBO
    return 0;
    #else
    return texelFetch(voxel_deviation_sampler, heap_pos, 0).r;
    #endif
}

//Fetches the voxel material index at the given voxel position
int loadVoxelDeviation(ivec3 pos) {
    ivec3 heap_pos = voxelWorldPosToHeapPos(pos);

    return loadVoxelDeviationHeapPos(heap_pos);
}

void storeVoxel(ivec3 pos, uint material_index) {
    ivec3 heap_pos = voxelWorldPosToHeapPos(pos);

    #if VOXEL_HEAP_MODE == VOXEL_HEAP_MODE_SSBO
    voxel_heap_bit_buffer[voxelHeapIndexFromHeapPosition(heap_pos)] = material_index;
    #else

    imageStore(voxel_bit_buffer_texture, heap_pos, uvec4(material_index));
    #endif
}
