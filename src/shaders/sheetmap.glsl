
#extension GL_EXT_shader_explicit_arithmetic_types : enable

#ifdef SHEETMAP_BINDING_START
const uint sheetmap_sheetmaps_binding = SHEETMAP_BINDING_START;
#else
const uint sheetmap_sheetmaps_binding = 0;
#endif

#ifdef SHEETMAP_BINDING_STRIDE
const uint sheetmap_binding_stride = SHEETMAP_BINDING_STRIDE;
#else
const uint sheetmap_binding_stride = 1;
#endif

const uint sheetmap_quadrats_binding = sheetmap_sheetmaps_binding + sheetmap_binding_stride;
const uint sheetmap_lines_binding = sheetmap_quadrats_binding + sheetmap_binding_stride;

const uint sheetmap_binding_end = sheetmap_lines_binding;

struct Sheetmap {
    uint quadrat_buffer_begin;
    uint kern_buffer_begin;
    uint foreground_buffer_begin;
    uint background_buffer_begin;
    ///Width and height in ems
    uint width;
    uint height;
};

struct SheetmapSampler {
    ///X spacing (glyph spacing) in ems
    float spacing_x;
    ///Y spacing (line spacing) in ems
    float spacing_y;
    //The rotation applied from uv -> quadrat space
    vec2 uv_rotation_quadrat;
    //The rotation applied from quadrat space -> glyph space
    vec2 uv_rotation_glyph;
    //Global colour of the text
    uint foreground_colour;
    //Global colour of the background sheet
    uint background_colour;
    //The backing texel sampler for this sheetmap sampler
    uint typeface_texel_sampler;
    //The typeface for this sheetmap sampler
    uint typeface;
};

struct CombinedSheetmapSampler {
    Sheetmap sheetmap;
    SheetmapSampler sheetmap_sampler;
};

layout(binding = sheetmap_sheetmaps_binding) readonly restrict buffer Sheetmaps {
    Sheetmap data[];
} sheetmaps;

struct SheetmapQuadrat {
    ///4 bits count + 28 bits address
    uint grapheme_slice;
};

layout(binding = sheetmap_quadrats_binding) readonly restrict buffer SheetmapQuadrats {
    SheetmapQuadrat data[];
} sheetmap_quadrats;

const uint SheetmapLineFlags_centred = 1 << 16;
const uint SheetmapLineFlags_left_justified = 1 << 15;
const uint SheetmapLineFlags_right_justified = 1 << 14;

struct GraphemeLine {
    //The length of the line that has glyphs committed to them
    uint32_t buffer_begin;
    uint8_t flags;
    uint8_t bin_start;
    uint8_t bins_length;
};

layout(binding = sheetmap_quadrats_binding + 1) readonly restrict buffer GlyphLines {
    GraphemeLine data[];
} grapheme_lines;

struct Glyph {
    uint16_t glyph_index;
};

struct GlyphKerning {
    float16_t kern;
};

layout(binding = sheetmap_quadrats_binding + 2) readonly restrict buffer GlyphInstances {
    Glyph data[];
} glyphs;

struct GraphemeMaterial {
    uint colour;
};

layout(binding = sheetmap_quadrats_binding + 3) readonly restrict buffer GraphemeMaterialBuffers {
    GraphemeMaterial data[];
} grapheme_materials;

struct GlyphMetric {
    float width;
    float height;
    float advance;
    float bearing_x;
    float bearing_y;
};

struct SheetmapTypeface {
    uint glyph_metrics_begin;
    uint glyph_metrics_count;
    float baseline;
    float ascent;
    float descent;
    float line_gap;
};

layout(binding = sheetmap_quadrats_binding + 4) readonly restrict buffer GlyphMetrics {
    GlyphMetric data[];
} glyph_metrics;

//Sample a glyph from the sheetmap at uv
Glyph sheetmapSampleGlyph(
    CombinedSheetmapSampler sheetmap,
    vec2 uv
) {
    return Glyph(uint16_t(0));
}

Glyph sheetmapLoadGlyph(
    Sheetmap sheetmap,
    uvec2 location
) {
    return Glyph(uint16_t(0));
}

void sheetmapStoreGlyph(
    Sheetmap sheetmap,
    uvec2 location,
    Glyph glyph
) {}

#ifdef SHEETMAP_TEXEL_SAMPLER

vec4 sheetmapSampleGlyphTexelLod(
    CombinedSheetmapSampler sampler,
    Glyph glyph,
    vec2 uv,
    uint lod
);

vec4 sheetmapSampleGlyphTexel(
    CombinedSheetmapSampler sampler,
    Glyph glyph,
    vec2 uv
);

//Sample a texel from the sheetmap at uv at the specified level of detail
vec4 sheetmapSampleTexelLod(
    CombinedSheetmapSampler sheetmap,
    vec2 uv,
    uint lod
) {
    return vec4(0);
}

//Sample a texel from the sheetmap at uv
vec4 sheetmapSampleTexel(
    CombinedSheetmapSampler sheetmap_sampler,
    vec2 uv
) {
    vec2 texCoord = uv;
    //TODO: apply wrapping modes
    texCoord = texCoord - floor(texCoord);

    Sheetmap sheetmap = sheetmap_sampler.sheetmap;

    texCoord.y = 1 - texCoord.y;

    vec2 grapheme_buffer_loc = texCoord * vec2(sheetmap.width, sheetmap.height);
    vec2 glyph_uv = grapheme_buffer_loc - floor(grapheme_buffer_loc);
    uint grapheme_bin_index = uint(grapheme_buffer_loc.x) + uint(grapheme_buffer_loc.y) * sheetmap.width;

    SheetmapQuadrat bin = sheetmap_quadrats.data[sheetmap.quadrat_buffer_begin + grapheme_bin_index];

    uint glyph_index = bin.grapheme_slice;

    GlyphMetric metrics = glyph_metrics.data[glyph_index];

    vec4 texel = sheetmapSampleGlyphTexel(sheetmap_sampler, Glyph(uint16_t(glyph_index)), glyph_uv);

    return texel;
}

#endif
