#version 460

#extension GL_GOOGLE_include_directive : enable
layout(location = 0) in vec3 inPos;
layout(location = 0) out vec3 localPos;

#include "common.glsl"

vec3 vertex_positions[36] = vec3[36](
        vec3(-1.0, 1.0, -1.0),
        vec3(-1.0, -1.0, -1.0),
        vec3(1.0, -1.0, -1.0),
        vec3(1.0, -1.0, -1.0),
        vec3(1.0, 1.0, -1.0),
        vec3(-1.0, 1.0, -1.0),

        vec3(-1.0, -1.0, 1.0),
        vec3(-1.0, -1.0, -1.0),
        vec3(-1.0, 1.0, -1.0),
        vec3(-1.0, 1.0, -1.0),
        vec3(-1.0, 1.0, 1.0),
        vec3(-1.0, -1.0, 1.0),

        vec3(1.0, -1.0, -1.0),
        vec3(1.0, -1.0, 1.0),
        vec3(1.0, 1.0, 1.0),
        vec3(1.0, 1.0, 1.0),
        vec3(1.0, 1.0, -1.0),
        vec3(1.0, -1.0, -1.0),

        vec3(-1.0, -1.0, 1.0),
        vec3(-1.0, 1.0, 1.0),
        vec3(1.0, 1.0, 1.0),
        vec3(1.0, 1.0, 1.0),
        vec3(1.0, -1.0, 1.0),
        vec3(-1.0, -1.0, 1.0),

        vec3(-1.0, 1.0, -1.0),
        vec3(1.0, 1.0, -1.0),
        vec3(1.0, 1.0, 1.0),
        vec3(1.0, 1.0, 1.0),
        vec3(-1.0, 1.0, 1.0),
        vec3(-1.0, 1.0, -1.0),

        vec3(-1.0, -1.0, -1.0),
        vec3(-1.0, -1.0, 1.0),
        vec3(1.0, -1.0, -1.0),
        vec3(1.0, -1.0, -1.0),
        vec3(-1.0, -1.0, 1.0),
        vec3(1.0, -1.0, 1.0)
    );

void main()
{
    localPos = (inPos - vec3(0.5)) * 1000;

    mat4 rot_view = mat4(mat3(uView));

    gl_Position = (uProjection * rot_view * vec4(localPos, 1.0));
}
