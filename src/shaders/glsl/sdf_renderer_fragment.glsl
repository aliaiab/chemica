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

vec2 hash(in vec2 x) // this hash is not production ready, please
{ // replace this by something better
    const vec2 k = vec2(0.3183099, 0.3678794);
    x = x * k + k.yx;
    return -1.0 + 2.0 * fract(16.0 * k * fract(x.x * x.y * (x.x + x.y)));
}

// returns 3D gradient noise (in .x) and its derivatives (in .yz)
vec3 noised(in vec2 x)
{
    vec2 i = floor(x);
    vec2 f = fract(x);

    vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);

    vec2 ga = hash(i + vec2(0.0, 0.0));
    vec2 gb = hash(i + vec2(1.0, 0.0));
    vec2 gc = hash(i + vec2(0.0, 1.0));
    vec2 gd = hash(i + vec2(1.0, 1.0));

    float va = dot(ga, f - vec2(0.0, 0.0));
    float vb = dot(gb, f - vec2(1.0, 0.0));
    float vc = dot(gc, f - vec2(0.0, 1.0));
    float vd = dot(gd, f - vec2(1.0, 1.0));

    return vec3(va + u.x * (vb - va) + u.y * (vc - va) + u.x * u.y * (va - vb - vc + vd), // value
        ga + u.x * (gb - ga) + u.y * (gc - ga) + u.x * u.y * (ga - gb - gc + gd) + // derivatives
            du * (u.yx * (va - vb - vc + vd) + vec2(vb, vc) - va));
}

layout(std430, binding = 22) restrict readonly buffer PointLights {
    PointLight point_lights[];
};

vec3 sampleTexture(uint sdf_tex, vec2 pos) {
    SDFResult3D field = evaluateSDF(sdf_tex, vec3(pos, 0), vec3(0), vec3(128));

    if (true) {
        return noised(pos);
    }

    if (field.sdf_gradient.x <= 0) {
        return field.sdf_gradient.yzw;
    }

    return vec3(1);
}

void main() {
    vec3 eye = vIn.eye;
    vec3 end_pos = vIn.position;

    vec3 ray_origin = eye;
    vec3 ray_end = end_pos;

    vec3 ray_direction = normalize(ray_end - ray_origin);

    uint max_steps = 100;
    float t = 0;
    bool hit = false;
    vec4 sdf_grad;
    SDFResult3D field;
    vec3 sample_point;

    for (int i = 0; i < max_steps; i++) {
        sample_point = ray_origin + ray_direction * t;

        field = evaluateSDF(sdf_texture_root, sample_point, vec3(0), vec3(128));

        if (field.sdf_gradient.x < 0.01) {
            hit = true;
            break;
        }

        t += field.sdf_gradient.x;
    }

    if (hit) {
        out_colour.xyz = vec3(1);

        vec3 normal = field.sdf_gradient.yzw;

        vec3 texture_sample_point = transformPoint(sample_point, sdf_elements_3d_transforms[field.transform]);

        vec3 tex_0 = sampleTexture(0, texture_sample_point.xy);
        vec3 tex_1 = sampleTexture(0, texture_sample_point.yz);
        vec3 tex_2 = sampleTexture(0, texture_sample_point.xz);

        vec3 tex = tex_0 * normal.z + tex_1 * normal.x + tex_2 * normal.y;

        vec3 light_radiance = vec3(0);

        for (int i = 0; i < point_lights.length(); i++) {
            PointLight light = point_lights[i];

            vec3 L = light.position - sample_point;

            vec3 radiance = unpackUnorm4x8(light.colour).rgb * light.radiance * 0.1 * max(0, dot(normal, L));
            //radiance /= dot(L, L);
            light_radiance += tex;
        }

        out_colour.xyz = field.sdf_gradient.yzw;
        out_colour.xyz = tex;

        out_colour.a = 1;
    }
    else {
        discard;
    }
}
