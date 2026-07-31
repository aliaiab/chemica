#version 450

const int KERNEL_SIZE = 8;

layout(local_size_x = KERNEL_SIZE, local_size_y = KERNEL_SIZE, local_size_z = KERNEL_SIZE) in;

struct Interaction {
    float enthalpy_change;
    float activation_energy;
    uint product;
};

layout(std430, binding = 33) buffer InteractionMatrix {
    int interaction_indices[];
};

layout(std430, binding = 33) buffer InteractionTable {
    Interaction interactions[];
};

//JK^-1mol^-1
const float universal_gas_constant = 8.31446261815324;

vec4 sampleRandom(vec4 p)
{
    vec4 p4 = fract(vec4(p.xyzx) * vec4(.1031, .1030, .0973, .1099));
    p4 += dot(p4, p4.wzxy + 33.33);
    return fract((p4.xxyz + p4.yzzw) * p4.zywx);
}

void main() {
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

    for (int i = 0; i < neighbours.length(); i++) {
        float dt = 0.016;
        float e_a = 1;
        float absoloute_temp = 1;

        float v_c = (1.0 / VOXEL_MOLARITY) * exp(-e_a / (universal_gas_constant * absoloute_temp)) * dt;

        float probability_of_interaction = v_c;

        vec4 random = sampleRandom(vec4(position, timestep_index));

        if (random.r < v_c) {
            //Do chemistry
        }
    }
}
