#version 460
#extension GL_GOOGLE_include_directive : enable
#extension GL_EXT_shader_explicit_arithmetic_types : enable

#include "Common.glsl"

const int KERNEL_SIZE = 8;

layout(local_size_x = KERNEL_SIZE, local_size_y = KERNEL_SIZE, local_size_z = KERNEL_SIZE) in;

layout(std430, binding = 4) restrict buffer InVoxelMaterials
{
    uint in_voxel_lattice[];
};

layout(std430, binding = 0) restrict buffer TemperatureInput
{
    float in_temperature[];
};

float sdBox(vec3 p, vec3 b) {
    vec3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float sdSphere(vec3 p, float radius) {
    return length(p) - radius;
}

float sdTorus(vec3 p, vec2 t) {
    vec2 q = vec2(length(p.xz) - t.x, p.y);
    return length(q) - t.y;
}

float sdHexPrism(vec3 p, vec2 h) {
    const vec3 k = vec3(-0.8660254, 0.5, 0.57735);
    p = abs(p);
    p.xy -= 2.0 * min(dot(k.xy, p.xy), 0.0) * k.xy;
    vec2 d = vec2(
            length(p.xy - vec2(clamp(p.x, -k.z * h.x, k.z * h.x), h.x)) * sign(p.y - h.x),
            p.z - h.y);
    return min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
}

float sdCutHollowSphere(vec3 p, float r, float h, float t) {
    // sampling independent computations (only depend on shape)
    float w = sqrt(r * r - h * h);

    // sampling dependant computations
    vec2 q = vec2(length(p.xz), p.y);
    return ((h * q.x < w * q.y) ? length(q - vec2(w, h)) :
    abs(length(q) - r)) - t;
}

float sdPlane(vec3 p, vec3 n, float h) {
    // n must be normalized
    return dot(p, n) + h;
}

float sdCylinder(vec3 p, vec3 c) {
    return length(p.xz - c.xy) - c.z;
}

float sdfUnion(float x, float y) {
    return min(x, y);
}

float sdfIntersect(float x, float y) {
    return max(x, y);
}

float sdfDifference(float x, float y) {
    return max(x, -y);
}

// sigmoid
float smin(float a, float b, float k)
{
    k *= log(2.0);
    float x = b - a;
    return a + x / (1.0 - exp2(x / k));
}

float sdfSmoothUnion(float x, float y) {
    return smin(x, y, 5);
}

//primitives
#include "../csg.h"

struct CSGInstruction {
    uint csg_op;
    //Index into the buffer of instructions of type csg_op
    uint stream_index;
};

struct CSGInstructionBox {
    vec3 bounds;
    uint rigid_transform;
    uint material;
};

struct CSGInstructionSphere {
    float radius;
    uint rigid_transform;
    uint material;
};

struct CSGInstructionTorus {
    vec2 radii;
    uint rigid_transform;
    uint material;
};

struct CSGInstructionExtrudePost {
    float h;
};

struct MaterialComponent {
    uint material;
    float weight;
};

layout(std430, binding = 10) restrict buffer Transforms {
    RigidTransform transforms[];
};

layout(std430, binding = 11) restrict buffer Instructions {
    CSGInstruction instructions[];
};

layout(std430, binding = 12) restrict buffer InstructionsBox {
    CSGInstructionBox instructions_box[];
};

layout(std430, binding = 13) restrict buffer InstructionsSphere {
    CSGInstructionSphere instructions_sphere[];
};

layout(std430, binding = 30) restrict buffer InstructionsExtrudePost {
    CSGInstructionExtrudePost instructions_extrude_post[];
};

layout(std430, binding = 14) restrict buffer CompositeMaterial {
    MaterialComponent composite_material[];
};

layout(std430, binding = 20) restrict buffer InDeviationBuffer {
    int8_t in_deviation_buffer[];
};

layout(std430, binding = 21) restrict buffer OutDeviationBuffer {
    int8_t out_deviation_buffer[];
};

layout(binding = 22) uniform sampler2D test_texture;

//Rotate the vector v by the quaternion q
vec3 rotateVector(vec4 q, vec3 v) {
    // return rotated;
    return v + 2.0 * cross(cross(v, q.xyz) + q.w * v, q.xyz);
}

RigidTransform transformCompose(RigidTransform lhs, RigidTransform rhs) {
    RigidTransform result;

    result.position = lhs.position + rhs.position;
    result.uniform_scale = lhs.uniform_scale * rhs.uniform_scale;
    result.rotation.w = lhs.rotation.w * rhs.rotation.w - dot(lhs.rotation.xyz, rhs.rotation.xyz);
    result.rotation.xyz = lhs.rotation.w * rhs.rotation.xyz + rhs.rotation.w * lhs.rotation.xyz - cross(lhs.rotation.xyz, rhs.rotation.xyz);

    return result;
}

//Transforms the point by the inverse of the rigid transform (as is needed for sdf eval)
vec3 transformPoint(vec3 point, RigidTransform rigid_transform) {
    vec3 result = (point - rigid_transform.position);

    return rotateVector(vec4(rigid_transform.rotation.xyz, -rigid_transform.rotation.w), result) * (1 / rigid_transform.uniform_scale);
}

struct FieldResult {
    float signed_distance;
    uint material;
    uint transform;
};

///Returns the sign distance function at the position
FieldResult executeDistanceProgram(vec3 in_position) {
    float distance_stack[16];
    uint material_stack[16];
    uint transform_stack[16];

    vec3 position_stack[16];

    position_stack[0] = in_position;

    uint stack_pointer = 0;
    uint position_stack_pointer = 0;

    for (int i = 0; i < instructions.length(); i += 1) {
        vec3 position = position_stack[position_stack_pointer];

        CSGInstruction inst = instructions[i];

        switch (inst.csg_op) {
            case CSG_BOX:
            {
                RigidTransform transform = transforms[instructions_box[inst.stream_index].rigid_transform];

                vec3 point = transformPoint(position, transform);

                transform_stack[stack_pointer] = instructions_box[inst.stream_index].rigid_transform;
                distance_stack[stack_pointer++] = sdBox(point, instructions_box[inst.stream_index].bounds) * transform.uniform_scale;

                break;
            }
            ;
            case CSG_SPHERE:
            {
                RigidTransform transform = transforms[instructions_sphere[inst.stream_index].rigid_transform];

                vec3 point = transformPoint(position, transform);

                transform_stack[stack_pointer] = instructions_box[inst.stream_index].rigid_transform;
                distance_stack[stack_pointer++] = sdSphere(point, instructions_sphere[inst.stream_index].radius) * transform.uniform_scale;

                break;
            }
            ;
            case CSG_BINARY_OP_UNION:
            {
                float d1 = distance_stack[--stack_pointer];
                uint transform_1 = transform_stack[stack_pointer];
                float d0 = distance_stack[--stack_pointer];
                uint transform_0 = transform_stack[stack_pointer];

                if (d0 < d1) {
                    transform_stack[stack_pointer] = transform_0;
                }
                else {
                    transform_stack[stack_pointer] = transform_1;
                }

                distance_stack[stack_pointer++] = sdfUnion(d0, d1);

                break;
            }
            ;
            case CSG_BINARY_OP_INTERSECTION:
            {
                float d1 = distance_stack[--stack_pointer];
                uint transform_1 = transform_stack[stack_pointer];
                float d0 = distance_stack[--stack_pointer];
                uint transform_0 = transform_stack[stack_pointer];

                if (d0 > d1) {
                    transform_stack[stack_pointer] = transform_0;
                }
                else {
                    transform_stack[stack_pointer] = transform_1;
                }

                distance_stack[stack_pointer++] = sdfIntersect(d0, d1);

                break;
            }
            ;
            case CSG_BINARY_OP_DIFFERENCE:
            {
                float d1 = distance_stack[--stack_pointer];
                float d0 = distance_stack[--stack_pointer];

                distance_stack[stack_pointer++] = sdfDifference(d0, d1);

                break;
            }
            ;
            case CSG_BINARY_OP_SMOOTH_UNION:
            {
                float d1 = distance_stack[--stack_pointer];
                float d0 = distance_stack[--stack_pointer];

                distance_stack[stack_pointer++] = sdfSmoothUnion(d0, d1);
                break;
            }
            ;
            case CSG_UNARY_OP_EXTRUDE_PRE:
            {
                position_stack_pointer += 1;
                position_stack[position_stack_pointer] = vec3(position.xy, 0);
            }
            ;
            case CSG_UNARY_OP_EXTRUDE_POST:
            {
                float h = instructions_extrude_post[inst.stream_index].h;

                vec2 w = vec2(distance_stack[--stack_pointer], abs(position.z) - h);

                distance_stack[stack_pointer++] = min(max(w.x, w.y), 0.0) + length(max(w, 0.0));
                position_stack_pointer -= 1;
                break;
            }
            ;
            case CSG_UNARY_OP_REVOLVE:
            {
                position_stack_pointer += 1;

                float revolution_factor = 20;

                position_stack[position_stack_pointer] = vec3(
                        length(position.xz) - revolution_factor,
                        position.y,
                        0
                    );

                break;
            }
            case CSG_POP_POSITION:
            {
                position_stack_pointer -= 1;
                break;
            }
            ;
            case CSG_TRANSFORM:
            {
                RigidTransform transform = transforms[inst.stream_index];

                position_stack_pointer += 1;
                position_stack[position_stack_pointer] = transformPoint(position, transform);
                break;
            }
            case CSG_TRANSFORM_POST:
            {
                RigidTransform transform = transforms[inst.stream_index];
                distance_stack[stack_pointer] *= transform.uniform_scale;

                break;
            }
        }
    }

    FieldResult result;

    result.signed_distance = distance_stack[stack_pointer - 1];
    result.transform = transform_stack[stack_pointer - 1];
    result.material = 0;

    return result;
}

vec4 hash43(vec4 p)
{
    vec4 p4 = fract(vec4(p.xyzx) * vec4(.1031, .1030, .0973, .1099));
    p4 += dot(p4, p4.wzxy + 33.33);
    return fract((p4.xxyz + p4.yzzw) * p4.zywx);
}

float atan2(float x, float y) {
    return 2 * atan(length(vec2(x, y)) - x, y);
}

//atan2(x, y) in turns
float argInTurns(float x, float y) {
    float pi = 3.14159265369;
    return (pi + atan2(x, y)) / (2 * pi);
}

void main() {
    ivec3 position_int = csg_bounding_min + ivec3(gl_GlobalInvocationID);
    uint index = position_int.x + uSize.x * position_int.y + uSize.x * uSize.y * position_int.z;

    bool is_in_region = all(greaterThanEqual(position_int, csg_bounding_min)) && all(lessThan(position_int, csg_bounding_max));
    is_in_region = is_in_region && isInBounds(position_int);

    if (!is_in_region) {
        return;
    }

    vec3 position = vec3(position_int) + 0.5;

    vec3 transformed_point = transformPoint(position, root_transform);
    float transform_scale = root_transform.uniform_scale;

    FieldResult field = executeDistanceProgram(transformed_point);
    field.signed_distance *= transform_scale;

    // transformed_point = transformPoint(transformed_point, transforms[field.transform]);

    // transform_scale *= transforms[field.transform].uniform_scale;

    vec4 random = hash43(vec4(transformed_point, 0));
    random.r = clamp(random.r, 0, 1);

    if (field.signed_distance < 0) {
        float running_weight = 0;

        for (int i = 0; i < composite_material.length(); i++) {
            running_weight += composite_material[i].weight;

            if (random.r < running_weight) {
                in_voxel_lattice[index] = composite_material[i].material;
                break;
            }
        }

        in_temperature[index] = min(6000, 300 * (1 / transform_scale) + abs(field.signed_distance) * 600);
        //in_temperature[index] = max(0, 1500 + 1000 * transform_scale * sin(-field.signed_distance * 5));
        //in_temperature[index] = 273 + 200 + 400 * cos(transformed_point.x * 0.25) + 400 * sin(transformed_point.y * 0.25);

        if (false) {
            float u = argInTurns(transformed_point.x, transformed_point.z);
            // float v = argInTurns(transformed_point.x, transformed_point.y);
            float v = 10 / abs(max(1, transformed_point.y));

            // float v = 1;

            in_temperature[index] = 273 + 200 + 10000 * (u * v);
            // in_temperature[index] = 273 + 200 + 1000 * sin(30 * u);
            // in_temperature[index] = 273;
        }

        float position_variation = random.r;
        in_deviation_buffer[index] = int8_t(position_variation * 255);
    }
    else {
        if (any(equal(position_int, csg_bounding_min)) || any(equal(position_int, csg_bounding_max))) {
            // in_voxel_lattice[index] = 1;
            // float position_variation = random.r;
            // in_deviation_buffer[index] = int8_t(position_variation * 255);
        }
    }
}
