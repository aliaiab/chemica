#version 460
#extension GL_GOOGLE_include_directive : enable
#extension GL_EXT_shader_explicit_arithmetic_types : enable

#include "Common.glsl"

const int KERNEL_SIZE = 8;

layout(local_size_x = KERNEL_SIZE, local_size_y = KERNEL_SIZE, local_size_z = KERNEL_SIZE) in;

layout(std430, binding = 2) restrict readonly buffer Materials
{
    VoxelMaterial uMaterials[];
};

layout(std430, binding = 4) restrict readonly buffer InVoxelMaterials
{
    uint16_t in_voxel_lattice[];
};

layout(std430, binding = 5) restrict buffer OutVoxelMaterials
{
    uint16_t out_voxel_lattice[];
};

layout(std430, binding = 6) restrict readonly buffer TemperatureInput
{
    float in_temperature[];
};

layout(std430, binding = 7) restrict writeonly buffer TemperatureOutput
{
    float out_temperature[];
};

layout(std430, binding = 20) restrict buffer InDeviationBuffer {
    int8_t in_deviation_buffer[];
};

layout(std430, binding = 21) restrict buffer OutDeviationBuffer {
    int8_t out_deviation_buffer[];
};

ivec3 getOffset(uint substep) {
    if (false) {
        //traditional margolus neighbourhood
        return ivec3(substep & 1);
    }

    if (true) {
        switch (substep % 8) {
            case 0:
            return ivec3(0, 0, 0);
            case 1:
            return ivec3(1, 1, 1);
            case 2:
            return ivec3(0, 1, 0);
            case 3:
            return ivec3(1, 0, 0);
            case 4:
            return ivec3(0, 0, 1);
            case 5:
            return ivec3(1, 0, 1);
            case 6:
            return ivec3(0, 1, 1);
            case 7:
            return ivec3(1, 1, 0);
        }
    }

    return ivec3(0, 0, 0);
}

bool canSwap(int grid[8], ivec3 from_position, uint i, ivec3 to_delta) {
    uint to_index = to_delta.x + to_delta.y * 2 + to_delta.z * 2 * 2;

    float from_density = uMaterials[in_voxel_lattice[i]].density;
    float to_density = uMaterials[in_voxel_lattice[grid[to_index]]].density;

    bool can_swap = to_density < from_density || in_voxel_lattice[grid[to_index]] == 0;

    return isInBlock(to_delta) && isInBounds(from_position + to_delta) && can_swap;
}

uint computePhase(uint voxel) {
    VoxelMaterial material = uMaterials[in_voxel_lattice[voxel]];

    if (in_temperature[voxel] < material.melting_point) {
        return VOXEL_PHASE_SOLID;
    }

    if (in_temperature[voxel] > material.boiling_point) {
        return VOXEL_PHASE_GAS;
    }

    return VOXEL_PHASE_LIQUID;
}

void swap(inout int grid[8], uint a, uint b)
{
    uint a_index = a;
    uint b_index = b;

    int tmp = grid[a];
    grid[a] = grid[b];
    grid[b] = tmp;
}

vec4 hash43(vec4 p)
{
    vec4 p4 = fract(vec4(p.xyzx) * vec4(.1031, .1030, .0973, .1099));
    p4 += dot(p4, p4.wzxy + 33.33);
    return fract((p4.xxyz + p4.yzzw) * p4.zywx);
}

void simulateSolidGrains(
    inout int grid[8],
    ivec3 pos,
    ivec3 local_pos,
    uint voxel_index,
    uint phase,
    vec4 random
) {
    ivec3 local_pos_below = local_pos + ivec3(0, -1, 0);
    ivec3 below_left = local_pos + ivec3(1 - local_pos.x, -1, 0);
    ivec3 below_right = local_pos + ivec3(0, -1, 1 - local_pos.z);

    if (phase == VOXEL_PHASE_GAS) {
        local_pos_below = local_pos + ivec3(0, 1, 0);
        below_left = local_pos + ivec3(1 - local_pos.x, 1, 0);
        below_right = local_pos + ivec3(0, 1, 1 - local_pos.z);
    }

    uint i_below = local_pos.x + (local_pos_below.y) * 2 + local_pos.z * 2 * 2;
    uint i_below_left = below_left.x + below_left.y * 2 + below_left.z * 2 * 2;
    uint i_below_right = below_right.x + below_right.y * 2 + below_right.z * 2 * 2;

    if (canSwap(grid, pos, 0, local_pos_below)) {
        swap(grid, i_below, voxel_index);
        return;
    }

    bool can_left_swap = canSwap(grid, pos, 0, below_left);
    bool can_right_swap = canSwap(grid, pos, 0, below_right);

    if (can_left_swap && can_right_swap) {
        can_left_swap = random.y > 0.5;
        can_right_swap = random.y < 0.5;
    }

    if (can_left_swap) {
        swap(grid, i_below_left, voxel_index);
        return;
    }

    if (can_right_swap) {
        swap(grid, i_below_right, voxel_index);
        return;
    }
}

void simulateFluid(
    inout int grid[8],
    ivec3 pos,
    uint phase
) {}

void main() {
    uint index = gl_GlobalInvocationID.x + uSize.x * gl_GlobalInvocationID.y + uSize.x * uSize.y * gl_GlobalInvocationID.z;
    ivec3 offset = getOffset(substep_index);

    ivec3 position = ivec3(gl_GlobalInvocationID) + offset;
    //Finds the position of the block
    ivec3 p = (position & 0xfffffffe) - offset;
    //Finds the position within the block
    ivec3 xyz = (position) & 1;
    //Index within the 2x2x2 local neighbourhood
    int local_index = xyz.x + xyz.y * 2 + xyz.z * 2 * 2;

    vec4 random = hash43(vec4(p, substep_index));

    int grid[8];

    for (int z = 0; z < 2; z++) {
        for (int y = 0; y < 2; y++) {
            for (int x = 0; x < 2; x++) {
                ivec3 local_pos = ivec3(x, y, z);
                uint i = x + y * 2 + z * 2 * 2;

                ivec3 global_pos = p + local_pos;

                grid[i] = int(global_pos.x + global_pos.y * uSize.x + global_pos.z * uSize.x * uSize.y);

                if (!isInBounds(global_pos)) {
                    grid[i] = -1;
                }
            }
        }
    }

    for (int z = 0; z < 2; z++) {
        for (int y = 0; y < 2; y++) {
            for (int x = 0; x < 2; x++) {
                ivec3 local_pos = ivec3(x, y, z);

                if (!isInBounds(p + local_pos)) {
                    continue;
                }

                uint i = x + y * 2 + z * 2 * 2;

                if (in_voxel_lattice[grid[i]] == 0) {
                    continue;
                }

                uint phase = computePhase(grid[i]);

                if (phase == VOXEL_PHASE_SOLID) {
                    //continue;
                }

                if (phase == VOXEL_PHASE_LIQUID) {
                    ivec3 local_pos_below = local_pos + ivec3(0, -1, 0);
                    ivec3 left = local_pos + ivec3(1 - x, 0, -x);
                    ivec3 right = local_pos + ivec3(-z, 0, 1 - x);
                    ivec3 below_left = local_pos + ivec3(1 - x, -1, -x);
                    ivec3 below_right = local_pos + ivec3(-z, -1, 1 - z);

                    uint i_below = x + (local_pos_below.y) * 2 + z * 2 * 2;
                    uint i_left = left.x + left.y * 2 + left.z * 2 * 2;
                    uint i_right = right.x + right.y * 2 + right.z * 2 * 2;

                    if (canSwap(grid, p, i, local_pos_below)) {
                        swap(grid, i_below, i);
                        continue;
                    }

                    bool can_left_swap = canSwap(grid, p, i, left);
                    bool can_right_swap = canSwap(grid, p, i, right);

                    if (can_left_swap && can_right_swap) {
                        can_left_swap = random.y > 0.5;
                        can_right_swap = !can_left_swap;
                    }

                    if (can_left_swap) {
                        swap(grid, i_left, i);
                        continue;
                    }

                    if (can_right_swap) {
                        swap(grid, i_right, i);
                        continue;
                    }

                    continue;
                }

                ivec3 local_pos_below = local_pos + ivec3(0, -1, 0);
                ivec3 below_left = local_pos + ivec3(1 - x, -1, -x);
                ivec3 below_right = local_pos + ivec3(-z, -1, 1 - z);

                if (phase == VOXEL_PHASE_GAS) {
                    local_pos_below = local_pos + ivec3(0, 1, 0);
                    below_left = local_pos + ivec3(1 - x, 1, 0);
                    below_right = local_pos + ivec3(0, 1, 1 - z);
                }

                uint i_below = x + (local_pos_below.y) * 2 + z * 2 * 2;
                uint i_below_left = below_left.x + below_left.y * 2 + below_left.z * 2 * 2;
                uint i_below_right = below_right.x + below_right.y * 2 + below_right.z * 2 * 2;

                if (canSwap(grid, p, i, local_pos_below)) {
                    swap(grid, i_below, i);
                    continue;
                }

                bool can_left_swap = canSwap(grid, p, i, below_left);
                bool can_right_swap = canSwap(grid, p, i, below_right);

                if (can_left_swap && can_right_swap) {
                    can_left_swap = random.y > 0.5;
                    can_right_swap = random.y < 0.5;
                }

                if (can_left_swap) {
                    swap(grid, i_below_left, i);
                    continue;
                }

                if (can_right_swap) {
                    swap(grid, i_below_right, i);
                    continue;
                }
            }
        }
    }

    out_voxel_lattice[index] = in_voxel_lattice[grid[local_index]];
    out_temperature[index] = in_temperature[grid[local_index]];
    out_deviation_buffer[index] = in_deviation_buffer[grid[local_index]];
}
