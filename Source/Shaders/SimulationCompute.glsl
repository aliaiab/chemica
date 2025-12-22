#version 460
#extension GL_GOOGLE_include_directive : enable

#include "Common.glsl"

const int KERNEL_SIZE = 8;

layout(local_size_x = KERNEL_SIZE, local_size_y = KERNEL_SIZE, local_size_z = KERNEL_SIZE) in;

layout(std430, binding = 0) restrict coherent buffer Input
{
    Voxel uInput[];
};

layout(std430, binding = 1) restrict coherent buffer Output
{
    Voxel uOutput[];
};

layout(std430, binding = 2) restrict readonly buffer Materials
{
    VoxelMaterial uMaterials[];
};

layout(std430, binding = 3) restrict coherent buffer ActiveRegion
{
    uvec3 minimum;
    uvec3 maximum;
} uActiveRegion;

/*
Voxel currentVoxel;

bool GetVoxel(in ivec3 position, out Voxel voxel)
{
    uvec3 clampedPosition = clamp(uvec3(position), uvec3(0), uSize - 1);

    uint index = clampedPosition.x + uSize.x * clampedPosition.y + uSize.x * uSize.y * clampedPosition.z;

    bool exists = all(greaterThan(position, ivec3(-1))) && all(lessThan(position, ivec3(uSize)));

    voxel = exists ? uInput[index] : voxel;

    return exists;
}

bool SetVoxel(in ivec3 position, in Voxel voxel)
{
    uvec3 clampedPosition = clamp(uvec3(position), uvec3(0), uSize - 1);

    uint index = clampedPosition.x + uSize.x * clampedPosition.y + uSize.x * uSize.y * clampedPosition.z;

    bool move = all(greaterThan(position, ivec3(-1))) && all(lessThan(position, ivec3(uSize)));

    if (move)
    {
        uOutput[index] = voxel;
    }    

    return move;
}

bool move_to(in ivec3 to)
{
    Voxel toVoxel;

    bool toVoxelExists = GetVoxel(to, toVoxel);

    bool isEmpty = toVoxel.type == 0;
    bool moved = false;

    if (toVoxelExists && isEmpty)
    {
        moved = SetVoxel(to, currentVoxel);

        if (moved)
        {
            SetVoxel(ivec3(gl_GlobalInvocationID), toVoxel);
        }
    }

    return moved;
}

bool move_by(in ivec3 by)
{
    return move_to(ivec3(gl_GlobalInvocationID) + by);
}

bool velocity_move()
{   
    currentVoxel.velocity += uBaseVelocity;
    
    return move_by(currentVoxel.velocity);
}
*/

void main()
{
    /*
    ivec3 position = ivec3(gl_GlobalInvocationID);
    
    int x = int(position.x);
    int y = int(position.y);
    int z = int(position.z);

    int index = x + int(uSize.x) * y + int(uSize.x) * int(uSize.y) * z;

    currentVoxel = uInput[index];

    if (currentVoxel.type == 0) return;

    VoxelMaterial material = uMaterials[currentVoxel.type];

    switch (currentVoxel.phase)
    {
        case VOXEL_PHASE_SOLID:
            {
                // velocity_move();

                break;

                ivec3 down = ivec3(0, -1, 0);
                ivec3 downLeft = ivec3(-1, -1, 0);
                ivec3 downRight = ivec3(1, -1, 0);
                ivec3 downFront = ivec3(0, -1, -1);
                ivec3 downBack = ivec3(0, -1, 1);

                if (!move_by(down))
                {
                    if (!move_by(downLeft));
                    else if (!move_by(downRight));
                    else if (!move_by(downFront));
                    else if (!move_by(downBack));
                }
            }

            break;
        case VOXEL_PHASE_LIQUID:
            {
                velocity_move();
            }

            break;
        case VOXEL_PHASE_GAS:
            {
                velocity_move();
            }

            break;
    }
    */
}