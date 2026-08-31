#version 460
#extension GL_GOOGLE_include_directive : enable

#include "buffers.glsl"

layout(std430, binding = buffer_binding_start + 13) restrict buffer VoxelMaterials
{
    uint16_t uVoxelMaterials[];
};

layout(std430, binding = buffer_binding_start + 14) restrict buffer VoxelTemperature
{
    float uVoxelTemperatures[];
};

layout(std430, binding = buffer_binding_start + 15) restrict buffer DeviationBuffer {
    int8_t deviation_buffer[];
};

#include "common.glsl"

const int KERNEL_SIZE = 8;

layout(local_size_x = KERNEL_SIZE, local_size_y = KERNEL_SIZE, local_size_z = KERNEL_SIZE) in;

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

    float currentTemperature = loadVoxelTemperature(ivec3(position));

    VoxelMaterial material = uMaterials[loadVoxelMaterial(ivec3(position))];

    uint occluded_faces = 0;
    float heat_differential = 0;
    float temperature_differential = 0;

    float specific_heat_capacity = uMaterials[loadVoxelMaterial(ivec3(position))].heat_capacity;
    float voxel_mass = VOXEL_MOLARITY * uMaterials[loadVoxelMaterial(ivec3(position))].molar_mass;

    for (int i = 0; i < neighbours.length(); i++)
    {
        ivec3 neighbour_pos = neighbours[i];
        int neighbourIndex = (int(position.x) + neighbours[i].x) + int(uSize.x) * (int(position.y) + neighbours[i].y) + int(uSize.x) * int(uSize.y) * (int(position.z) + neighbours[i].z);

        if (all(greaterThanEqual(position + neighbours[i], ivec3(0))) && all(lessThan(position + neighbours[i], uSize)))
        {
            float neighbour_temp = loadVoxelTemperature(neighbour_pos);
            float difference = neighbour_temp - currentTemperature;

            float interface_conductivity = uMaterials[loadVoxelMaterial(neighbour_pos)].heat_conductivity;

            if (loadVoxelMaterial(neighbour_pos) == 0) {
                continue;
            }

            float dt = 0.016;

            heat_differential += interface_conductivity * (VOXEL_FACE_AREA / (VOXEL_SIDE_LENGTH)) * difference * dt;

            accumulatedTemperature += neighbour_temp;
            temperatureSolidCount += 1;

            if (loadVoxelMaterial(neighbour_pos) != 0) {
                occluded_faces += 1;
            }
        }
    }

    float stefan_boltzman_constant = 5.67e-8;

    float radiation_rate = stefan_boltzman_constant * pow(currentTemperature, 4) * 0.016;
    float radiation_factor = uMaterials[loadVoxelMaterial(ivec3(position))].thermal_emissivity * (neighbours.length() - float(occluded_faces)) * VOXEL_FACE_AREA;

    if (enable_radiative_cooling) {
        heat_differential += -radiation_rate * radiation_factor;
    }

    temperature_differential = (heat_differential / specific_heat_capacity) / voxel_mass * 0.1;

    float result_temperature = currentTemperature + temperature_differential;
    result_temperature = max(0, result_temperature);

    storeVoxelTemperature(ivec3(position), result_temperature);
    atomicAdd(total_energy, int(result_temperature * specific_heat_capacity * voxel_mass));
}
