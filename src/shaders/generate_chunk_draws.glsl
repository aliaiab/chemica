#version 450

#extension GL_GOOGLE_include_directive : enable
#extension GL_EXT_shader_explicit_arithmetic_types : enable
#extension GL_EXT_shader_atomic_float2 : enable

#include "common.glsl"

const int KERNEL_SIZE = 8;

layout(local_size_x = KERNEL_SIZE, local_size_y = KERNEL_SIZE, local_size_z = KERNEL_SIZE) in;

layout(binding = 40) restrict writeonly buffer OutIndices {
    uint16_t out_indices[];
};

layout(binding = 41) restrict writeonly buffer OutVertices {
    vec4 out_vertices[];
};

struct DrawArraysIndirectCommand {
    uint count;
    uint instance_count;
    uint first;
    uint base_instance;
};

layout(binding = 42) restrict coherent buffer OutDraws {
    DrawArraysIndirectCommand out_draws[];
};

layout(binding = 43) restrict coherent buffer OutBounds {
    ivec3 sim_bounds_min;
    ivec3 sim_bounds_max;
};

void main() {
    ivec3 chunk_pos = ivec3(gl_GlobalInvocationID);

    uint heap_index = texelFetch(voxel_chunk_positions_sampler, chunk_pos, 0).r;

    ivec3 neighbours[] = ivec3[](
            ivec3(0, 1, 0),
            ivec3(0, -1, 0),
            ivec3(0, 0, 1),
            ivec3(0, 0, -1),
            ivec3(1, 0, 0),
            ivec3(-1, 0, 0)
        );

    ivec3 vertex_positions_for_face[6][4] = ivec3[6][4](
            ivec3[4](
                ivec3(0, 16, 0),
                ivec3(16, 16, 0),
                ivec3(0, 16, 16),
                ivec3(16, 16, 16)
            ),
            ivec3[4](
                ivec3(16, 0, 0),
                ivec3(0, 0, 0),
                ivec3(16, 0, 16),
                ivec3(0, 0, 16)
            ),
            ivec3[4](
                ivec3(16, 0, 16),
                ivec3(0, 0, 16),
                ivec3(16, 16, 16),
                ivec3(0, 16, 16)
            ),
            ivec3[4](
                ivec3(0, 0, 0),
                ivec3(16, 0, 0),
                ivec3(0, 16, 0),
                ivec3(16, 16, 0)
            ),
            ivec3[4](
                ivec3(16, 0, 0), //bottom right
                ivec3(16, 0, 16), //bottom left
                ivec3(16, 16, 0), //top left
                ivec3(16, 16, 16) //top right
            ),
            ivec3[4](
                ivec3(0, 0, 16), //bottom left
                ivec3(0, 0, 0), //bottom right
                ivec3(0, 16, 16), //top right
                ivec3(0, 16, 0) //top left
            )
        );

    if (gl_GlobalInvocationID == uvec3(0)) {
        out_draws[0].count = 0;
        out_draws[0].instance_count = 1;
        out_draws[0].first = 0;
        out_draws[0].base_instance = 0;

        sim_bounds_min = ivec3(0xffff);
        sim_bounds_max = ivec3(0);
    }

    if (heap_index != NULL_HEAP_INDEX) {
        while (out_draws[0].count != 0) {}

        //generate faces
        ivec3 chunk_begin = chunk_pos * CHUNK_SIZE;
        ivec3 chunk_end = chunk_begin + ivec3(CHUNK_SIZE);

        int emitted_face_count = 0;

        for (int i = 0; i < neighbours.length(); i++) {
            ivec3 neighbour_pos = chunk_pos + neighbours[i];

            uint heap_index = texelFetch(voxel_chunk_positions_sampler, neighbour_pos, 0).r;

            if (!isInBoundsInclusive(neighbour_pos * CHUNK_SIZE)) {
                heap_index = NULL_HEAP_INDEX;
            }

            if (heap_index == NULL_HEAP_INDEX) {
                //generate face
                emitted_face_count += 1;

                ivec3 face_verts[4] = vertex_positions_for_face[i];

                for (int j = 0; j < 4; j++) {
                    face_verts[j] += chunk_pos * CHUNK_SIZE;
                }

                uint v_i = atomicAdd(out_draws[0].count, 6);

                out_vertices[v_i++].xyz = face_verts[2];
                out_vertices[v_i++].xyz = face_verts[1];
                out_vertices[v_i++].xyz = face_verts[0];
                out_vertices[v_i++].xyz = face_verts[3];
                out_vertices[v_i++].xyz = face_verts[1];
                out_vertices[v_i++].xyz = face_verts[2];
            }
        }

        if (emitted_face_count != 0) {
            atomicMin(sim_bounds_min.x, chunk_pos.x);
            atomicMin(sim_bounds_min.y, chunk_pos.y);
            atomicMin(sim_bounds_min.z, chunk_pos.z);

            atomicMax(sim_bounds_max.x, chunk_pos.x + 1);
            atomicMax(sim_bounds_max.y, chunk_pos.y + 1);
            atomicMax(sim_bounds_max.z, chunk_pos.z + 1);
        }
    }
}
