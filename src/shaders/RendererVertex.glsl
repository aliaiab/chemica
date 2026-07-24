#version 460
#extension GL_GOOGLE_include_directive : enable

#include "Common.glsl"

layout(location = 0) in vec3 aPosition;

layout(location = 0) out Out
{
    vec3 position;
    vec3 eye;
} vOut;

void main()
{
    mat4 mv = uView * uModel;

    vec3 pos = aPosition * vec3(uSize);

    gl_Position = uProjection * mv * vec4(pos, 1.0);

    vOut.eye = vec3(inverse(uView) * vec4(0, 0, 0, 1));
    vOut.position = vec3(uModel * vec4(pos, 1));
}
