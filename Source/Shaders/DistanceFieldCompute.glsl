#version 460
#extension GL_GOOGLE_include_directive : enable

#include "Common.glsl"

const int KERNEL_SIZE = 8;

layout(local_size_x = KERNEL_SIZE, local_size_y = KERNEL_SIZE, local_size_z = KERNEL_SIZE) in;

layout(std430, binding = 0) restrict buffer Input
{
    Voxel uVoxels[];
};

bool IsEmpty(uvec3 startIdx, uvec3 endIdx) 
{
    uint startIndex = clamp(startIdx.z * uSize.x * uSize.y + startIdx.y * uSize.x + startIdx.x, 0, uVoxels.length() - 1);
    uint endIndex = clamp(endIdx.z * uSize.x * uSize.y + endIdx.y * uSize.x + endIdx.x, 0, uVoxels.length() - 1);

    for (uint i = startIndex; i < endIndex; i++)
    {
        if (uVoxels[i].type != 0)
        {
            return false;
        }
    }

    /*
	for (uint z = startIdx.z; z <= endIdx.z; z++) 
    {
		for (uint y = startIdx.y; y <= endIdx.y; y++) 
        {
			for (uint x = startIdx.x; x <= endIdx.x; x++) 
            {
				uint shapeIdx = z * uSize.x * uSize.y + y * uSize.x + x;

				if (uVoxels[shapeIdx].type != 0) 
                {
					return false;
				}
			}
		}
	}
    */

	return true;
}

uint FindMaxJump(uvec3 idx) 
{
	uint jumpSize = 0;

	while (IsEmpty(idx - jumpSize + 1, idx + jumpSize + 1) && jumpSize < 1) 
    {
		jumpSize++;
	}

	return jumpSize;
}

void main()
{
    /*
    uvec3 position = uvec3(gl_GlobalInvocationID);
    
    uint index = position.z * uSize.x * uSize.y + position.y * uSize.x + position.x;

    Voxel voxel = uVoxels[index];

    if (voxel.type != 0) 
    {
        // uVoxels[index].distanceField = 255;
    }
    else 
    {
        // uVoxels[index].distanceField = FindMaxJump(position);
    }
    */
}