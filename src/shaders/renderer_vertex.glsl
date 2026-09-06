#version 460
#extension GL_GOOGLE_include_directive : enable

#include "common.glsl"

layout(location = 0) out Out
{
    vec3 position;
    vec3 eye;
} vOut;

const vec2 triangle[3] = vec2[3](
        vec2(0, 0),
        vec2(2, 0),
        vec2(0, 2)
    );

layout(std430, binding = buffer_binding_start + 10) readonly buffer RendererVertexInPositions {
    vec4 renderer_vertex_in_positions[];
};

layout(binding = buffer_binding_start + 12) readonly buffer SimBounds {
    ivec3 sim_bounds_min;
    ivec3 sim_bounds_max;
};

void main()
{
    mat4 mv = uView * uModel;

    vec3 pos = sim_bounds_min * CHUNK_SIZE + renderer_vertex_in_positions[gl_VertexIndex].xyz * vec3((sim_bounds_max - sim_bounds_min) * CHUNK_SIZE);

    gl_Position = uProjection * mv * vec4(pos, 1.0);
    //gl_Position = vec4(triangle[gl_VertexID], 0.1, 1);

    vOut.eye = vec3(inverse(uView) * vec4(0, 0, 0, 1));
    vOut.position = vec3(uModel * vec4(pos, 1));
}
