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
    uint density;
    float heat_conductivity;
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

layout(std430, binding = 24) restrict buffer VoxelChunkPalleteMemory
{
    uint16_t voxel_chunk_pallete_memory[];
};

layout(std430, binding = 31) restrict buffer VoxelPalleteCounters
{
    int voxel_pallete_counters[];
};

layout(std430, binding = 25) restrict buffer VoxelChunkBitBufferMemory
{
    uint voxel_chunk_bit_buffer_memory[];
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

layout(std430, binding = 27) restrict buffer VoxelAllocatorBuffer
{
    VoxelChunkAllocator voxel_allocators[];
};

layout(std430, binding = 28) restrict buffer VoxelAllocatorBins {
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
    //The position of the chunk containing 0, 0, 0 within the chunk grid
    uvec3 zero_chunk_pos;
    uvec3 chunk_grid_size;
};

#define CHUNK_SIZE 32
#define CHUNK_VOLUME (CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE)

#define ChunkAllocation uint

struct ChunkBufferAllocation {
    ChunkAllocation allocation;
    uint bit_count;
};

layout(std430, binding = 28) restrict buffer VoxelChunkBufferAllocation
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

struct Voxel
{
    uint16_t type;
    float temperature;
    //TODO: just use int8_t here
    int deviation;
};

struct RigidTransform {
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
    RigidTransform root_transform;
    ivec3 csg_bounding_min;
    ivec3 csg_bounding_max;
    float delta_time;
    uvec2 window_size;
};

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

int newAllocator(uint bit_count) {
    uint allocator = atomicAdd(allocators_bump, 1);
    voxel_allocators[allocator].memory_allocated_bits = 0xffffffff;
    voxel_allocators[allocator].next_allocator = -1;

    voxel_allocators[allocator].pallete_counters_start = atomicAdd(voxel_pallete_counters_bump, 1);
    voxel_allocators[allocator].bit_buffer_memory_start = atomicAdd(voxel_bit_buffer_bump, bit_count * CHUNK_SIZE * CHUNK_SIZE);
    voxel_allocators[allocator].pallete_memory_start = atomicAdd(voxel_pallete_bump, 1 << bit_count);
    voxel_allocators[allocator].temperature_buffer_start = atomicAdd(voxel_temperature_bump, CHUNK_VOLUME);

    return int(allocator);
}

ChunkAllocation voxelChunkAlloc(uint bit_count) {
    int allocator_index = voxel_allocator_bin[bit_count - 1];

    if (allocator_index == -1) {
        voxel_allocator_bin[bit_count - 1] = newAllocator(bit_count);
    }

    VoxelChunkAllocator alloc = voxel_allocators[allocator_index];

    //If allocated bits == 0 then it is full
    while (alloc.memory_allocated_bits == 0) {
        if (alloc.next_allocator == -1) {
            //Create new allocator and push it to the front of the bin
            int new_allocator = newAllocator(bit_count);
            voxel_allocator_bin[bit_count - 1] = new_allocator;
            voxel_allocators[new_allocator].next_allocator = allocator_index;

            alloc = voxel_allocators[new_allocator];
        }

        voxel_allocators[allocator_index].next_allocator = alloc.next_allocator;

        allocator_index = alloc.next_allocator;
        alloc = voxel_allocators[allocator_index];
    }

    int allocation_index = bitScanForward(alloc.memory_allocated_bits);
    voxel_allocators[allocation_index].memory_allocated_bits = alloc.memory_allocated_bits ^ (1 << allocation_index);

    ChunkAllocation allocation = 0;

    allocation = bitfieldInsert(allocation, allocator_index, 5, 32);
    allocation = bitfieldInsert(allocation, allocation_index, 0, 5);

    return allocation;
}

void voxelChunkFree(ChunkAllocation allocation) {
    uint allocator_index = bitfieldExtract(allocation, 5, 32);
    uint allocation_index = bitfieldExtract(allocation, 0, 5);

    voxel_allocators[allocation_index].memory_allocated_bits = voxel_allocators[allocator_index].memory_allocated_bits | (1 << allocation_index);
}

//Fetches the voxel material index at the given voxel position
uint loadVoxelMaterial(ivec3 pos) {
    uvec3 chunk_pos = (zero_chunk_pos + pos) / CHUNK_SIZE;
    uvec3 chunk_offset = pos - chunk_pos;

    uint chunk_index = chunk_pos.x + chunk_pos.y * chunk_grid_size.y + chunk_pos.z * chunk_grid_size.y * chunk_grid_size.z;
    uint index_into_chunk = chunk_offset.x + chunk_offset.y * CHUNK_SIZE + chunk_offset.z * CHUNK_SIZE * CHUNK_SIZE;

    ChunkAllocation chunk_allocation = voxel_chunks_allocation[chunk_index].allocation;
    uint chunk_bit_count = voxel_chunks_allocation[chunk_index].bit_count;

    uint allocator_index = bitfieldExtract(chunk_allocation, 5, 32);
    uint allocation_index = bitfieldExtract(chunk_allocation, 0, 5);

    VoxelChunkAllocator allocator = voxel_allocators[allocator_index];

    uint bit_offset = index_into_chunk * chunk_bit_count;

    uint chunk_begin = allocation_index * chunk_bit_count * CHUNK_SIZE * CHUNK_SIZE;

    uint bit_buffer_index = allocator.bit_buffer_memory_start + chunk_begin + bit_offset / 32;

    uint first_int = voxel_chunk_bit_buffer_memory[bit_buffer_index];
    uint second_int = voxel_chunk_bit_buffer_memory[bit_buffer_index + 1];

    int64_t packed_integer = int64_t(first_int) | int64_t(second_int) << 32;

    int64_t unpacked = bitfieldExtract(first_int, int(bit_offset), int(chunk_bit_count));

    uint material_index = uint(voxel_chunk_pallete_memory[allocator.pallete_memory_start + allocation_index * (1 << chunk_bit_count) + int(unpacked)]);

    return material_index;
}

void storeVoxel(ivec3 pos, uint16_t material_index) {
    uvec3 chunk_pos = (zero_chunk_pos + pos) / CHUNK_SIZE;
    uvec3 chunk_offset = pos - chunk_pos;

    uint chunk_index = chunk_pos.x + chunk_pos.y * chunk_grid_size.y + chunk_pos.z * chunk_grid_size.y * chunk_grid_size.z;
    uint index_into_chunk = chunk_offset.x + chunk_offset.y * CHUNK_SIZE + chunk_offset.z * CHUNK_SIZE * CHUNK_SIZE;

    ChunkAllocation chunk_allocation = voxel_chunks_allocation[chunk_index].allocation;
    uint chunk_bit_count = voxel_chunks_allocation[chunk_index].bit_count;

    uint allocator_index = bitfieldExtract(chunk_allocation, 5, 32);
    uint allocation_index = bitfieldExtract(chunk_allocation, 0, 5);

    VoxelChunkAllocator allocator = voxel_allocators[allocator_index];

    uint bit_offset = index_into_chunk * chunk_bit_count;

    uint chunk_begin = allocation_index * chunk_bit_count * CHUNK_SIZE * CHUNK_SIZE;
    uint pallete_begin = allocator.pallete_memory_start + allocation_index * (1 << chunk_bit_count);

    int pallete_end = -1;
    int pallete_index = -1;

    for (int i = 0; i < (1 << chunk_bit_count); i++) {
        uint pallete_material = voxel_chunk_pallete_memory[pallete_begin + i];
        if (pallete_material == material_index) {
            pallete_index = i;
        }

        if (i != 0 && pallete_material == 0) {
            pallete_end = i;
            break;
        }
    }

    if (pallete_index == -1) {
        pallete_end = atomicAdd(voxel_pallete_counters[allocator.pallete_counters_start], 1);
        voxel_chunk_pallete_memory[pallete_begin + pallete_end] = material_index;
        pallete_index = pallete_end;
    }

    uint bit_buffer_index = allocator.bit_buffer_memory_start + chunk_begin + bit_offset / 32;

    int64_t packed_integer = bitfieldInsert(0, pallete_index, int(bit_offset), int(chunk_bit_count));

    voxel_chunk_bit_buffer_memory[bit_buffer_index] |= uint(packed_integer);
    voxel_chunk_bit_buffer_memory[bit_buffer_index + 1] |= uint(packed_integer >> 32);
}
