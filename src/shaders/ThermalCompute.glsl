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

layout(std430, binding = 32) restrict buffer TotalEnergyBuffer {
    int total_energy;
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
    float heat_differential = 0;
    float temperature_differential = 0;

    float specific_heat_capacity = uMaterials[voxel_materials[index]].heat_capacity;
    float voxel_mass = VOXEL_MOLARITY * uMaterials[voxel_materials[index]].molar_mass;

    for (int i = 0; i < neighbours.length(); i++)
    {
        int neighbourIndex = (int(position.x) + neighbours[i].x) + int(uSize.x) * (int(position.y) + neighbours[i].y) + int(uSize.x) * int(uSize.y) * (int(position.z) + neighbours[i].z);

        if (all(greaterThanEqual(position + neighbours[i], ivec3(0))) && all(lessThan(position + neighbours[i], uSize)))
        {
            float difference = float(uInput[neighbourIndex]) - currentTemperature;

            float interface_conductivity = uMaterials[uint(voxel_materials[neighbourIndex])].heat_conductivity;

            if (voxel_materials[neighbourIndex] == 0) {
                continue;
            }

            float dt = 0.016;

            heat_differential += interface_conductivity * (VOXEL_FACE_AREA / (VOXEL_SIDE_LENGTH)) * difference * dt;

            accumulatedTemperature += uInput[neighbourIndex];
            temperatureSolidCount += 1;

            if (uint(voxel_materials[neighbourIndex]) != 0) {
                occluded_faces += 1;
            }
        }
    }

    float stefan_boltzman_constant = 5.67e-8;

    float radiation_rate = stefan_boltzman_constant * pow(currentTemperature, 4) * 0.016;
    float radiation_factor = uMaterials[voxel_materials[index]].thermal_emissivity * (neighbours.length() - float(occluded_faces)) * VOXEL_FACE_AREA;

    if (enable_radiative_cooling) {
        heat_differential += -radiation_rate * radiation_factor;
    }

    temperature_differential = (heat_differential / specific_heat_capacity) / voxel_mass * 0.1;

    uOutput[index] = uInput[index] + temperature_differential;

    atomicAdd(total_energy, int(uOutput[index] * specific_heat_capacity * voxel_mass));
    uOutput[index] = max(0, uOutput[index]);
}
