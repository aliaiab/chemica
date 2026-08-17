#version 450
#extension GL_GOOGLE_include_directive : enable
#extension GL_ARB_shader_draw_parameters : enable

#include "asym.glsl"

#define SHEETMAP_TEXEL_SAMPLER
#define SHEETMAP_BINDING_START 20
#include "sheetmap.glsl"
#include "sheetmap_ts_msdf_array.glsl"

layout(location = 0) out vec4 colour;

layout(location = 0) in Out
{
    vec3 position;
    vec4 colour;
    vec2 uv;
    flat uint draw_id;
    flat uint instance_id;
} vertex_in;

void main() {
    DrawCommand draw = draws.data[vertex_in.draw_id];

    switch (draw.primitive_type) {
        case PrimitiveType_circle:
        {
            float radius = 0.2;

            if (dot(vertex_in.position, vertex_in.position) <= radius * radius) {
                colour = vertex_in.colour;
            }
            else {
                discard;
            }

            break;
        }
        case PrimitiveType_text:
        {
            colour = vertex_in.colour;

            vec2 uv = vertex_in.uv;

            SheetmapSampler sheetmap_sampler;

            sheetmap_sampler.typeface = 0;
            sheetmap_sampler.background_colour = packUnorm4x8(vec4(1, 1, 1, 1));
            sheetmap_sampler.foreground_colour = packUnorm4x8(vec4(0, 0, 0, 0));

            colour = sheetmapSampleTexel(CombinedSheetmapSampler(sheetmaps.data[vertex_in.instance_id], sheetmap_sampler), uv);

            break;
        }
        default:
        {
            colour = vertex_in.colour;
            break;
        }
    }
}
