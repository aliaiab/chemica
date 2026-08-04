#version 460
#extension GL_GOOGLE_include_directive : enable

#include "common.glsl"

layout(location = 0) in vec4 aPosition;

void main()
{
    mat4 mv = uView * uModel;

    vec3 pos = aPosition.xyz;

    gl_Position = uProjection * mv * vec4(pos, 1.0);
}
