
struct TexelSamplerMsdfArray {
    float pixel_range;
};

const uint sheetmap_msdf_array_binding = sheetmap_sampler_binding_start;

layout(binding = sheetmap_msdf_array_binding) uniform sampler2DArray sheetmap_msdf_array;

const float pxRange = 8; // set to distance field's pixel range

vec2 msdfArrayVec2Sqr(vec2 x) {
    return x * x;
} // squares vector components

float msdfArrayCalculateManualMipLevel(vec2 uv, vec2 textureSize) {
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
    vec2 unitRange = vec2(pxRange) / vec2(textureSize(sheetmap_msdf_array, int(msdfArrayCalculateManualMipLevel(texCoord, vec2(textureSize(sheetmap_msdf_array, 0))))));
    // If inversesqrt is not available, use vec2(1.0)/sqrt
    vec2 screenTexSize = inversesqrt(msdfArrayVec2Sqr(dFdx(texCoord)) + msdfArrayVec2Sqr(dFdy(texCoord)));
    // Can also be approximated as screenTexSize = vec2(1.0)/fwidth(texCoord);
    return max(0.5 * dot(unitRange, screenTexSize), 1.0);
}

float median(float r, float g, float b) {
    return max(min(r, g), min(max(r, g), b));
}

vec4 sheetmapSampleGlyphTexelLod(
    CombinedSheetmapSampler sheetmap_sampler,
    Glyph glyph,
    vec2 uv,
    uint lod
) {
    return vec4(0);
}

vec4 sheetmapSampleGlyphTexel(
    CombinedSheetmapSampler sheetmap_sampler,
    Glyph glyph,
    vec2 uv
) {
    vec4 colour;

    GlyphMetric metrics = glyph_metrics.data[glyph.glyph_index];

    vec2 texCoord = uv;
    texCoord.y += 0.25;
    //texCoord.y *= 4;
    //texCoord.y = 1 - texCoord.y;
    texCoord.y += metrics.bearing_y;

    //texCoord.x /= float(metrics.width) / float(textureSize(glyph_atlas, 0).x);
    //texCoord.y /= float(metrics.height) / float(textureSize(glyph_atlas, 0).y);

    float em_width = glyph_metrics.data[77].width;
    texCoord.x *= em_width;
    texCoord.x /= textureSize(sheetmap_msdf_array, 0).x;

    float glyph_deadspace = em_width - metrics.width;
    glyph_deadspace *= 0.5;

    texCoord.x -= glyph_deadspace / em_width;

    vec3 msd = texture(sheetmap_msdf_array, vec3(texCoord, glyph.glyph_index)).rgb;
    float sd = median(msd.r, msd.g, msd.b);
    float screenPxDistance = screenPxRange(texCoord) * (sd - 0.5);
    float opacity = clamp(screenPxDistance + 0.5, 0.0, 1.0);
    vec4 bgColor = unpackUnorm4x8(sheetmap_sampler.sheetmap_sampler.background_colour);
    vec4 fgColor = unpackUnorm4x8(sheetmap_sampler.sheetmap_sampler.foreground_colour);

    if (opacity == 0) {}

    colour = mix(bgColor, fgColor, opacity);

    //helium, and
    //There's

    float border_width = 0.02;
    bool is_border = uv.x < border_width || uv.x > (1 - border_width);
    is_border = is_border || (uv.y > (1 - border_width) || uv.y < border_width);

    bool visualize_quadrats = false;

    if (is_border && visualize_quadrats) {
        colour = vec4(1, 0, 0, 1);
    }

    return colour;
}
