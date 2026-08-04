#version 450

#extension GL_GOOGLE_include_directive : enable

#include "sdf.glsl"

layout(location = 0) in Out
{
    vec3 position;
    vec3 eye;
} vIn;

layout(location = 0) out vec4 out_colour;

layout(early_fragment_tests) in;

void main() {
    vec3 eye = vIn.eye;
    vec3 end_pos = vIn.position;

    vec3 ray_origin = eye;
    vec3 ray_end = end_pos;

    vec3 ray_direction = normalize(ray_end - ray_origin);

    uint max_steps = 40;
    float t = 0;
    bool hit = false;
    FieldResult field;

    for (int i = 0; i < max_steps; i++) {
        vec3 sample_point = ray_origin + ray_direction * t;

        field = executeDistanceProgram(sample_point, true);

        if (field.signed_distance < 0.01) {
            hit = true;
            break;
        }

        t += field.signed_distance;
    }

    if (hit) {
        out_colour.xyz = vec3(1);
        out_colour.xyz = field.gradient;

        out_colour.a = 1;
    }
    else {
        discard;
    }
}
