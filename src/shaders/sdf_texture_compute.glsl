#version 460
#extension GL_GOOGLE_include_directive : enable
#extension GL_EXT_shader_explicit_arithmetic_types : enable

#include "sdf.glsl"

const int KERNEL_SIZE = 8;

layout(local_size_x = KERNEL_SIZE, local_size_y = KERNEL_SIZE, local_size_z = KERNEL_SIZE) in;

layout(binding = 5, rgba8) restrict writeonly uniform image2D out_image;

void main() {
    ivec3 tex_pos = ivec3(gl_GlobalInvocationID);
    vec2 image_size = vec2(imageSize(out_image));
    vec2 sample_pos = vec2(tex_pos.xy);
    sample_pos /= image_size;
    sample_pos -= 0.5;
    sample_pos *= 100;

    SDFResult3D field = evaluateSDF(sdf_texture_root, vec3(sample_pos, 0), vec3(-100), vec3(100));

    if (field.sdf_gradient.x < 0) {
        imageStore(out_image, tex_pos.xy, vec4(field.sdf_gradient.yzw, 1));
    }
    else {
        imageStore(out_image, tex_pos.xy, vec4(vec3(0), 1));
    }
}
