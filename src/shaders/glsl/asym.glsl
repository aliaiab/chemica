
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
    uint instance_ids_begin;
};

struct AffineTransform3D {
    vec3 position;
    float scale;
    vec4 rotation;
};

struct Material {
    uint colour;
};

const uint asym_binding_start = 16 + 70;

layout(binding = asym_binding_start) readonly restrict buffer Uniforms {
    mat4 view_projection;
    float time;
} uniforms;

layout(binding = asym_binding_start + 1) readonly restrict buffer Draws {
    DrawCommand data[];
} draws;

layout(binding = asym_binding_start + 2) readonly restrict buffer Transforms {
    AffineTransform3D data[];
} transforms;

layout(binding = asym_binding_start + 3) readonly restrict buffer Materials {
    Material data[];
} materials;

layout(binding = asym_binding_start + 4) readonly restrict buffer Parameters {
    float data[];
} parameters;

layout(binding = asym_binding_start + 5) readonly restrict buffer Vertices {
    vec3 data[];
} vertices;

layout(binding = asym_binding_start + 6) readonly restrict buffer TransformOffsetsByType {
    uint data[];
} transform_offsets_by_type;

layout(binding = asym_binding_start + 7) readonly restrict buffer ParameterOffsetsByType {
    uint data[];
} parameter_offsets_by_type;
