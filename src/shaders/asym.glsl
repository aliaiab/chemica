
#extension GL_EXT_shader_16bit_storage : enable

const uint PrimitiveType_triangle_list_3d = 0;
const uint PrimitiveType_triangle_list_2d = PrimitiveType_triangle_list_3d + 1;
const uint PrimitiveType_line_list_3d = PrimitiveType_triangle_list_2d + 1;
const uint PrimitiveType_line_list_2d = PrimitiveType_line_list_3d + 1;
const uint PrimitiveType_box = PrimitiveType_line_list_2d + 1;
const uint PrimitiveType_line = PrimitiveType_box + 1;
const uint PrimitiveType_sphere = PrimitiveType_line + 1;
const uint PrimitiveType_circle = PrimitiveType_sphere + 1;
const uint PrimitiveType_text = PrimitiveType_circle + 1;

struct DrawCommand {
    uint count;
    uint instance_count;
    uint first;
    uint base_instance;

    uint primitive_type;
    uint materials_begin;
    uint transforms_begin;
    uint parameters_begin;
};

struct AffineTransform3D {
    vec3 position;
    float scale;
    vec4 rotation;
};

struct Material {
    uint colour;
};

layout(binding = 0) readonly restrict buffer Uniforms {
    mat4 view_projection;
    float time;
} uniforms;

layout(binding = 1) readonly restrict buffer Draws {
    DrawCommand data[];
} draws;

layout(binding = 2) readonly restrict buffer Transforms {
    AffineTransform3D data[];
} transforms;

layout(binding = 3) readonly restrict buffer Materials {
    Material data[];
} materials;

layout(binding = 4) readonly restrict buffer Parameters {
    float data[];
} parameters;

layout(binding = 5) readonly restrict buffer Vertices {
    vec3 data[];
} vertices;

struct GraphemeBuffer {
    uint buffer_begin;
    ///Width and height in pidgeon holes
    uint width;
    uint height;
};

struct GraphemeBufferSampler {
    float spacing_x;
    float spacing_y;
    float global_ordering;
};

layout(binding = 6) readonly restrict buffer GraphemeBuffers {
    GraphemeBuffer data[];
} grapheme_buffers;

struct GraphemePidgeonHole {
    ///4 bits count + 28 bits address
    uint grapheme_slice;
};

layout(binding = 7) readonly restrict buffer GlyphPidgeonHoles {
    GraphemePidgeonHole data[];
} grapheme_pidgeon_holes;

const uint GraphemeLineFlags_centred = 1 << 16;
const uint GraphemeLineFlags_left_justified = 1 << 15;
const uint GraphemeLineFlags_right_justified = 1 << 14;

#if 0
struct GraphemeLine {
    ///The length of the line that has glyphs committed to them
    uint32_t buffer_begin;
    uint8_t flags;
    uint8_t bin_start;
    uint8_t bins_length;
};

layout(binding = 13) readonly restrict buffer GlyphLines {
    GraphemeLine data[];
} grapheme_lines;
#endif

struct Grapheme {
    uint16_t glyph_index;
};

struct GrahpemeKerning {
    float16_t kern;
};

layout(binding = 8) readonly restrict buffer GlyphInstances {
    Grapheme data[];
} graphemes;

struct GraphemeMaterial {
    uint colour;
};

layout(binding = 9) readonly restrict buffer GraphemeMaterialBuffers {
    GraphemeMaterial data[];
} grapheme_materials;

struct GlyphMetric {
    float width;
    float height;
    float advance;
    float bearing_x;
    float bearing_y;
};

struct TypeFace {
    uint glyph_metrics_begin;
    uint glyph_metrics_count;
    float baseline;
    float ascent;
    float descent;
    float line_gap;
};

layout(binding = 10) readonly restrict buffer GlyphMetrics {
    GlyphMetric data[];
} glyph_metrics;

layout(binding = 11) readonly restrict buffer TransformOffsetsByType {
    uint data[];
} transform_offsets_by_type;

layout(binding = 12) readonly restrict buffer ParameterOffsetsByType {
    uint data[];
} parameter_offsets_by_type;

#if 0
layout(binding = 11) readonly restrict buffer TypeFace {
    TypeFace data[];
} typefaces;
#endif

layout(binding = 0) uniform sampler2DArray glyph_atlas;

void graphemeBufferSample(
    GraphemeBuffer grapheme_buffer,
    TypeFace typeface,
    vec2 uv
) {}
