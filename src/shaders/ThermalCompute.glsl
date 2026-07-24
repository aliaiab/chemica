#version 460
#extension GL_GOOGLE_include_directive : enable

#include "Common.glsl"

const int KERNEL_SIZE = 8;

layout(local_size_x = KERNEL_SIZE, local_size_y = KERNEL_SIZE, local_size_z = KERNEL_SIZE) in;

layout(std430, binding = 0) restrict readonly buffer Input
{
    float uInput[];
};

layout(std430, binding = 1) restrict buffer Output
{
    float uOutput[];
};

layout(std430, binding = 2) restrict readonly buffer Materials
{
    VoxelMaterial uMaterials[];
};

layout(std430, binding = 4) restrict readonly buffer VoxelMaterials
{
    uint16_t voxel_materials[];
};

void main()
{
    uvec3 position = gl_GlobalInvocationID;
    uint index = position.x + uSize.x * position.y + uSize.x * uSize.y * position.z;

    ivec3 neighbours[] = ivec3[](
            ivec3(-1, 0, 0),
            ivec3(1, 0, 0),
            ivec3(0, -1, 0),
            ivec3(0, 1, 0),
            ivec3(0, 0, -1),
            ivec3(0, 0, 1),

            ivec3(1, 1, 0),
            ivec3(0, 1, 1),
            ivec3(1, 0, 1),
            -ivec3(1, 1, 0),
            -ivec3(0, 1, 1),
            -ivec3(1, 0, 1)
        );

    int temperatureSolidCount = 0;
    float accumulatedTemperature = 0;

    float currentTemperature = uInput[index];

    VoxelMaterial material = uMaterials[uint(voxel_materials[index])];

    uint occluded_faces = 0;

    for (int i = 0; i < neighbours.length(); i++)
    {
        int neighbourIndex = (int(position.x) + neighbours[i].x) + int(uSize.x) * (int(position.y) + neighbours[i].y) + int(uSize.x) * int(uSize.y) * (int(position.z) + neighbours[i].z);

        if (all(greaterThanEqual(position + neighbours[i], ivec3(0))) && all(lessThan(position + neighbours[i], uSize)))
        {
            float difference = float(uInput[neighbourIndex]) - currentTemperature;

            float interface_conductivity = uMaterials[uint(voxel_materials[neighbourIndex])].heat_conductivity * material.heat_conductivity;

            uOutput[index] += difference * 0.025 * interface_conductivity;

            accumulatedTemperature += uInput[neighbourIndex];
            temperatureSolidCount += 1;

            if (uint(voxel_materials[neighbourIndex]) != 0) {
                occluded_faces += 1;
            }
        }
        else {
            // occluded_faces += 1;
        }
    }

    float radiation_rate = 0.0001 * 5.6e-8 * pow(currentTemperature, 4);
    float radiation_factor = 1 - (float(occluded_faces) / float(neighbours.length()));

    uOutput[index] += -radiation_rate * radiation_factor;
    uOutput[index] = max(0, uOutput[index]);
}
