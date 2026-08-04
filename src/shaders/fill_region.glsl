#version 460
#extension GL_GOOGLE_include_directive : enable
#extension GL_EXT_shader_explicit_arithmetic_types : enable

const int KERNEL_SIZE = 8;

layout(local_size_x = KERNEL_SIZE, local_size_y = KERNEL_SIZE, local_size_z = KERNEL_SIZE) in;

layout(std430, binding = 4) restrict buffer InVoxelMaterials
{
    uint16_t in_voxel_lattice[];
};

layout(std430, binding = 0) restrict buffer TemperatureInput
{
    float in_temperature[];
};

#include "sdf.glsl"

vec4 hash43(vec4 p)
{
    vec4 p4 = fract(vec4(p.xyzx) * vec4(.1031, .1030, .0973, .1099));
    p4 += dot(p4, p4.wzxy + 33.33);
    return fract((p4.xxyz + p4.yzzw) * p4.zywx);
}

float atan2(float x, float y) {
    return 2 * atan(length(vec2(x, y)) - x, y);
}

//atan2(x, y) in turns
float argInTurns(float x, float y) {
    float pi = 3.14159265369;
    return (pi + atan2(x, y)) / (2 * pi);
}

shared int fill_finished_semaphore;

void main() {
    ivec3 position_int = csg_bounding_min + ivec3(gl_GlobalInvocationID);
    uint index = position_int.x + uSize.x * position_int.y + uSize.x * uSize.y * position_int.z;

    bool is_in_region = all(greaterThanEqual(position_int, csg_bounding_min)) && all(lessThan(position_int, csg_bounding_max));
    is_in_region = is_in_region && isInBounds(position_int);

    if (!is_in_region) {
        return;
    }

    ivec3 chunk_pos = position_int / CHUNK_SIZE;
    uint chunk_index = chunk_pos.x + chunk_pos.y * chunk_grid_size.x + chunk_pos.z * chunk_grid_size.x * chunk_grid_size.y;

    if (position_int % CHUNK_SIZE == vec3(0)) {
        if (voxel_chunks_allocation[chunk_index].allocation == 0xffffffff) {
            voxel_chunks_allocation[chunk_index].allocation = voxelChunkAlloc(1);
        }
        fill_finished_semaphore = 0;
    }

    while (voxel_chunks_allocation[chunk_index].allocation == 0xffffffff) {}

    vec3 position = vec3(position_int) + 0.5;

    vec3 transformed_point = transformPoint(position, root_transform);
    float transform_scale = root_transform.uniform_scale;

    FieldResult field = executeDistanceProgram(transformed_point, false);
    field.signed_distance *= transform_scale;

    transformed_point = transformPoint(transformed_point, transforms[field.transform]);

    // transform_scale *= transforms[field.transform].uniform_scale;

    vec4 random = hash43(vec4(transformed_point, 0));
    random.r = clamp(random.r, 0, 1);

    if (field.signed_distance < 0) {
        float running_weight = 0;

        for (int i = 0; i < composite_material.length(); i++) {
            running_weight += composite_material[i].weight;

            if (random.r < running_weight) {
                in_voxel_lattice[index] = uint16_t(composite_material[i].material);
                break;
            }
        }

        in_voxel_lattice[mortonEncode(position_int)] = uint16_t(field.material);

        if (true) {
            voxel_chunks_allocation[chunk_index].bit_count = 1;

            uint previous_allocation = atomicCompSwap(voxel_chunks_allocation[chunk_index].allocation, 0xffffffff, 0);

            if (previous_allocation == 0xffffffff) {
                uint chunk_alloc = voxelChunkAlloc(1);

                voxel_chunks_allocation[chunk_index].allocation = chunk_alloc;

                ivec3 heap_pos = voxelChunkAllocationHeapPosition(chunk_alloc);
                uint heap_index = voxelChunkHeapIndexFromHeapPosition(heap_pos);

                imageStore(voxel_chunk_allocations_image, chunk_pos, uvec4(chunk_alloc));

                #if VOXEL_HEAP_MODE == VOXEL_HEAP_MODE_3D_TEXTURE
                imageStore(voxel_chunk_positions_image, chunk_pos, uvec4(heap_index));
                #else
                voxel_chunk_positions_buffer[voxelChunkPosToChunkIndex(ivec3(chunk_pos))] = heap_index;
                #endif
            }
            else {
                uint chunk_alloc = voxel_chunks_allocation[chunk_index].allocation;
                ivec3 heap_pos = voxelChunkAllocationHeapPosition(chunk_alloc);
                uint heap_index = voxelChunkHeapIndexFromHeapPosition(heap_pos);

                imageStore(voxel_chunk_allocations_image, chunk_pos, uvec4(chunk_alloc));

                #if VOXEL_HEAP_MODE == VOXEL_HEAP_MODE_3D_TEXTURE
                imageStore(voxel_chunk_positions_image, chunk_pos, uvec4(heap_index));
                #else
                voxel_chunk_positions_buffer[voxelChunkPosToChunkIndex(ivec3(chunk_pos))] = heap_index;
                #endif
            }
            barrier();

            while (voxel_chunks_allocation[chunk_index].allocation == 0xffffffff) {}

            storeVoxel(position_int, field.material);
        }

        //in_temperature[index] = min(6000, 300 * (1 / transform_scale) + abs(field.signed_distance) * 600);
        //in_temperature[index] = 1000;
        //in_temperature[index] = 0;
        //in_temperature[index] = max(0, 1500 + 1000 * transform_scale * sin(-field.signed_distance * 5));
        in_temperature[mortonEncode(position_int)] = 273 + 200 + 400 * cos(transformed_point.x * 0.25) + 400 * sin(transformed_point.y * 0.25);

        if (false) {
            float u = argInTurns(transformed_point.x, transformed_point.z);
            // float v = argInTurns(transformed_point.x, transformed_point.y);
            float v = 10 / abs(max(1, transformed_point.y));

            // float v = 1;

            in_temperature[index] = 273 + 200 + 100 * (u * v);
            // in_temperature[index] = 273 + 200 + 1000 * sin(30 * u);
            // in_temperature[index] = 273;
        }

        float position_variation = random.r;
        in_deviation_buffer[mortonEncode(position_int)] = int8_t(position_variation * 255);
    }
    else {
        if (false && (any(equal(position_int, csg_bounding_min)) || any(equal(position_int, csg_bounding_max)))) {
            in_voxel_lattice[index] = uint16_t(1);
            float position_variation = random.r;
            in_deviation_buffer[index] = int8_t(position_variation * 255);
        }
        barrier();
        storeVoxel(position_int, 0);
    }
}
