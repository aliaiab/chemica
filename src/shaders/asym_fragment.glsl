#version 450
#extension GL_GOOGLE_include_directive : enable
#extension GL_ARB_shader_draw_parameters : enable

#include "asym.glsl"

layout(location = 0) out vec4 colour;

layout(location = 0) in Out
{
    vec3 position;
    vec4 colour;
    vec2 uv;
    flat uint draw_id;
} vertex_in;

float median(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}

const float pxRange = 8; // set to distance field's pixel range

vec2 sqr(vec2 x) {
    return x * x;
} // squares vector components

float calculateManualMipLevel(vec2 uv, vec2 textureSize) {
    // Scale UVs to texel space
    vec2 dx = dFdx(uv * textureSize);
    vec2 dy = dFdy(uv * textureSize);

    // Find the maximum squared length (or vector length) in screen space
    float px = dot(dx, dx);
    float py = dot(dy, dy);
    float maxTexelChange = max(px, py);

    // Mip level formula: log2(sqrt(maxTexelChange)) = 0.5 * log2(maxTexelChange)
    float mipLevel = 0.5 * log2(maxTexelChange);

    return max(mipLevel, 0.0);
}

float screenPxRange(vec2 texCoord) {
    vec2 unitRange = vec2(pxRange) / vec2(textureSize(glyph_atlas, int(calculateManualMipLevel(texCoord, vec2(textureSize(glyph_atlas, 0))))));
    // If inversesqrt is not available, use vec2(1.0)/sqrt
    vec2 screenTexSize = inversesqrt(sqr(dFdx(texCoord)) + sqr(dFdy(texCoord)));
    // Can also be approximated as screenTexSize = vec2(1.0)/fwidth(texCoord);
    return max(0.5 * dot(unitRange, screenTexSize), 1.0);
}

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

            bool reorder_x = false;

            vec2 texCoord = vertex_in.uv;
            //texCoord.x = 1 - texCoord.x;
            texCoord.y += uniforms.time * -0.25 * 0.1;
            texCoord = texCoord - floor(texCoord);

            if (reorder_x) {
                texCoord.x = 1 - texCoord.x;
            }

            GraphemeBuffer grapheme_buffer = grapheme_buffers.data[0];

            texCoord.y = 1 - texCoord.y;
            vec2 grapheme_buffer_loc = texCoord * vec2(grapheme_buffer.width, grapheme_buffer.height);
            vec2 glyph_uv = grapheme_buffer_loc - floor(grapheme_buffer_loc);
            uint grapheme_bin_index = uint(grapheme_buffer_loc.x) + uint(grapheme_buffer_loc.y) * grapheme_buffer.width;

            GraphemePidgeonHole bin = grapheme_pidgeon_holes.data[grapheme_buffer.buffer_begin + grapheme_bin_index];

            uint glyph_index = bin.grapheme_slice;

            GlyphMetric metrics = glyph_metrics.data[glyph_index];

            texCoord = glyph_uv;
            texCoord.y += 0.25;
            //texCoord.y *= 4;
            //texCoord.y = 1 - texCoord.y;
            texCoord.y += metrics.bearing_y;

            if (reorder_x) {
                texCoord.x = 1 - texCoord.x;
            }

            //texCoord.x /= float(metrics.width) / float(textureSize(glyph_atlas, 0).x);
            //texCoord.y /= float(metrics.height) / float(textureSize(glyph_atlas, 0).y);

            vec3 msd = texture(glyph_atlas, vec3(texCoord, glyph_index)).rgb;
            float sd = median(msd.r, msd.g, msd.b);
            float screenPxDistance = screenPxRange(texCoord) * (sd - 0.5);
            float opacity = clamp(screenPxDistance + 0.5, 0.0, 1.0);
            vec4 bgColor = vec4(0, 0, 0, 1);
            vec4 fgColor = vec4(1);

            fgColor = vec4(0, 0, 0, 1);
            bgColor = vec4(1);

            if (opacity == 0) {}

            colour = mix(bgColor, fgColor, opacity);

            break;
        }
        default:
        {
            colour = vertex_in.colour;
            break;
        }
    }
}
