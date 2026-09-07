#include "common.glsl"

vec4 sdBoxGradient(in vec3 p, in vec3 b)
{
    vec3 w = abs(p) - (b);
    float g = max(w.x, max(w.y, w.z));
    vec3 q = max(w, 0.0);
    float l = length(q);
    vec4 f = (g > 0.0) ? vec4(l, q / l) :
        vec4(g, w.x == g ? 1.0 : 0.0,
            w.y == g ? 1.0 : 0.0,
            w.z == g ? 1.0 : 0.0);
    return vec4(f.x, f.yzw * sign(p));
}

vec4 sdSphereGradient(in vec3 p, in float r)
{
    float l = length(p);
    return vec4(l - r, p / l);
}

vec4 sdfCylinderGradient(in vec3 p, in float he, in float r)
{
    float l = length(p.xz);
    vec2 e = vec2(l - r, abs(p.y) - he / 2.0);
    vec2 h = max(e, 0.0);
    float f = length(h);
    float g = max(e.x, e.y);
    vec3 du = vec3(p.x / l, 0.0, p.z / l);
    vec3 dv = vec3(0.0, p.y < 0.0 ? -1.0 : 1.0, 0.0);
    return (g <= 0.0) ? vec4(g, (e.x > e.y) ? du : dv) :
    vec4(f, (h.x * du + h.y * dv) / f);
}

vec3 sdfPentagonGradient(in vec2 p, in float r)
{
    const vec3 m = vec3(0.80901699, 0.58778525, 0.72654253);
    const vec2 n = vec2(m.x * m.x - m.y * m.y, 2.0 * m.x * m.y);
    float s = sign(p.x);
    p.x = abs(p.x);
    float w1 = p.x * m.x + p.y * m.y;
    float w2 = p.x * n.x - p.y * n.y;
    p -= 2.0 * max(w1, 0.0) * vec2(m.x, m.y);
    p -= 2.0 * min(w2, 0.0) * vec2(m.x, -m.y);
    p -= vec2(clamp(p.x, -r * m.z, r * m.z), -r);
    float d = length(p) * sign(-p.y);
    vec2 g = (w2 < 0.0) ? mat2x2(-m.x, m.y, -m.y, -m.x) * p :
        (w1 > 0.0) ? mat2x2(-n.x, -n.y, -n.y, n.x) * p :
        p;
    g.x *= s;
    return vec3(d, g / d);
}

uint sdfUnionSelectInt(vec4 lhs, vec4 rhs, uint lhs_value, uint rhs_value) {
    uint t = uint(step(lhs.x, rhs.x));
    uint res = lhs_value * t + rhs_value * (1 - t);
    return res;
}

uint sdfIntersectionSelectInt(vec4 lhs, vec4 rhs, uint lhs_value, uint rhs_value) {
    uint t = uint(step(lhs.x, rhs.x));
    uint res = lhs_value * (1 - t) + rhs_value * t;
    return res;
}

uint sdfDifferenceSelectInt(vec4 lhs, vec4 rhs, uint lhs_value, uint rhs_value) {
    rhs.x = -rhs.x;
    return sdfIntersectionSelectInt(lhs, rhs, lhs_value, rhs_value);
}

vec4 sdfGradientUnion(vec4 lhs, vec4 rhs) {
    vec4 res;

    res.x = min(lhs.x, rhs.x);
    float t = step(lhs.x, rhs.x);
    res.yzw = lhs.yzw * t + rhs.yzw * (1 - t);
    return res;
}

vec4 sdfGradientIntersection(vec4 lhs, vec4 rhs) {
    vec4 res;

    res.x = max(lhs.x, rhs.x);
    float t = step(lhs.x, rhs.x);
    res.yzw = lhs.yzw * (1 - t) + rhs.yzw * t;
    return res;
}

vec4 sdfGradientDifference(vec4 lhs, vec4 rhs) {
    rhs.x = -rhs.x;
    return sdfGradientIntersection(lhs, rhs);
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

const uint SDF_ELEMENT_3D_TYPE_MASK = 0x00ff;
const uint SDF_ELEMENT_3D_MODIFIERS_MASK = 0xff00;

const uint SDF_ELEMENT_3D_UNION = 0;
const uint SDF_ELEMENT_3D_INTERSECTION = SDF_ELEMENT_3D_UNION + 1;
const uint SDF_ELEMENT_3D_DIFFERENCE = SDF_ELEMENT_3D_INTERSECTION + 1;
const uint SDF_ELEMENT_3D_BOX = SDF_ELEMENT_3D_DIFFERENCE + 1;
const uint SDF_ELEMENT_3D_CYLINDER = SDF_ELEMENT_3D_BOX + 1;
const uint SDF_ELEMENT_3D_SPHERE = SDF_ELEMENT_3D_CYLINDER + 1;
const uint SDF_ELEMENT_3D_EXTRUDE = SDF_ELEMENT_3D_SPHERE + 1;
const uint SDF_ELEMENT_3D_REVOLVE = SDF_ELEMENT_3D_EXTRUDE + 1;
const uint SDF_ELEMENT_3D_N_GON = SDF_ELEMENT_3D_REVOLVE + 1;

const uint SDF_ELEMENT_3D_MODIFIER_ROUNDING = (1 << 8);
const uint SDF_ELEMENT_3D_MODIFIER_EXTRUSION = SDF_ELEMENT_3D_MODIFIER_ROUNDING << 1;
const uint SDF_ELEMENT_3D_MODIFIER_REPITITION = SDF_ELEMENT_3D_MODIFIER_EXTRUSION << 1;
const uint SDF_ELEMENT_3D_MODIFIER_REVOLUTION = SDF_ELEMENT_3D_MODIFIER_REPITITION << 1;
const uint SDF_ELEMENT_3D_MODIFIER_ELONGATION = SDF_ELEMENT_3D_MODIFIER_REVOLUTION << 1;
const uint SDF_ELEMENT_3D_MODIFIER_MATERIAL = SDF_ELEMENT_3D_MODIFIER_ELONGATION << 1;

struct SdfElement3D {
    uint16_t type;
    uint16_t params_start;
    uint16_t children_start;
    uint16_t children_count;
};

layout(std430, binding = buffer_binding_start + 20) restrict readonly buffer SdfElements3D {
    SdfElement3D sdf_elements_3d[];
};

layout(std430, binding = buffer_binding_start + 21) restrict readonly buffer SdfElements3DTransforms {
    AffineTransform3D sdf_elements_3d_transforms[];
};

layout(std430, binding = buffer_binding_start + 22) restrict readonly buffer SdfElement3DParamBuffer {
    float sdf_elements_3d_params[];
};

layout(std430, binding = buffer_binding_start + 23) restrict readonly buffer SdfElements3DBounds {
    vec3 sdf_elements_3d_bounds[];
};

vec3 sdf3DLoadParamVec3(uint index) {
    vec3 vec;

    vec.x = sdf_elements_3d_params[index];
    vec.y = sdf_elements_3d_params[index + 1];
    vec.z = sdf_elements_3d_params[index + 2];

    return vec;
}

//Rotate the vector v by the quaternion q
vec3 rotateVector(vec4 q, vec3 v) {
    // return rotated;
    return v + 2.0 * cross(cross(v, q.xyz) + q.w * v, q.xyz);
}

AffineTransform3D transformCompose(AffineTransform3D lhs, AffineTransform3D rhs) {
    AffineTransform3D result;

    result.position = lhs.position + rhs.position;
    result.uniform_scale = lhs.uniform_scale * rhs.uniform_scale;
    result.rotation.w = lhs.rotation.w * rhs.rotation.w - dot(lhs.rotation.xyz, rhs.rotation.xyz);
    result.rotation.xyz = lhs.rotation.w * rhs.rotation.xyz + rhs.rotation.w * lhs.rotation.xyz - cross(lhs.rotation.xyz, rhs.rotation.xyz);

    return result;
}

//Transforms the point by the inverse of the rigid transform (as is needed for sdf eval)
vec3 transformPoint(vec3 point, AffineTransform3D rigid_transform) {
    vec3 result = (point - rigid_transform.position);

    return rotateVector(vec4(rigid_transform.rotation.xyz, -rigid_transform.rotation.w), result) * (1 / rigid_transform.uniform_scale);
}

struct SDFResult3D {
    vec4 sdf_gradient;
    uint transform;
    uint material;
};

vec4 evaluateSdfElement3D(
    uint element_index,
    uint params_index,
    vec3 sample_position
) {
    SdfElement3D child_element = sdf_elements_3d[element_index];

    AffineTransform3D child_transform = sdf_elements_3d_transforms[element_index];

    vec3 transformed_point = transformPoint(sample_position, child_transform);
    vec4 rhs_sdf_gradient;

    uint modifiers = uint(child_element.type) & SDF_ELEMENT_3D_MODIFIERS_MASK;
    uint modifier_param_bump = 1;

    if ((modifiers & SDF_ELEMENT_3D_MODIFIER_ROUNDING) != 0) {
        modifier_param_bump += 1;
    }

    if ((modifiers & SDF_ELEMENT_3D_MODIFIER_EXTRUSION) != 0) {
        transformed_point = vec3(transformed_point.xz, 0);
        modifier_param_bump += 1;
    }

    if ((modifiers & SDF_ELEMENT_3D_MODIFIER_REVOLUTION) != 0) {
        float o = sdf_elements_3d_params[child_element.params_start - modifier_param_bump];
        transformed_point = vec3(length(transformed_point.xz) - 0, transformed_point.y, 0);
        modifier_param_bump += 1;
    }

    if ((modifiers & SDF_ELEMENT_3D_MODIFIER_ELONGATION) != 0) {
        vec3 h = sdf3DLoadParamVec3(child_element.params_start - modifier_param_bump - 2);
        transformed_point = transformed_point - clamp(transformed_point, -h, h);
        modifier_param_bump += 3;
    }

    switch (int(child_element.type) & SDF_ELEMENT_3D_TYPE_MASK) {
        case SDF_ELEMENT_3D_BOX:
        {
            vec3 bounds = sdf3DLoadParamVec3(child_element.params_start);
            rhs_sdf_gradient = sdBoxGradient(transformed_point, bounds);

            break;
        }
        case SDF_ELEMENT_3D_CYLINDER:
        {
            float extrusion_height = sdf_elements_3d_params[child_element.params_start];
            float radius = sdf_elements_3d_params[child_element.params_start + 1];

            rhs_sdf_gradient = sdfCylinderGradient(transformed_point, extrusion_height, radius);

            break;
        }
        case SDF_ELEMENT_3D_SPHERE:
        {
            float radius = sdf_elements_3d_params[child_element.params_start];
            rhs_sdf_gradient = sdSphereGradient(transformed_point, radius);

            break;
        }
        case SDF_ELEMENT_3D_N_GON:
        {
            float radius = sdf_elements_3d_params[child_element.params_start];
            vec3 sdf_grad_2d = sdfPentagonGradient(transformed_point.xy, radius);
            rhs_sdf_gradient.x = sdf_grad_2d.x;
            rhs_sdf_gradient.yzw = vec3(sdf_grad_2d.yz, 0);

            break;
        }
        default:
        {
            break;
        }
    }

    modifier_param_bump = 1;

    if ((modifiers & SDF_ELEMENT_3D_MODIFIER_ROUNDING) != 0) {
        float rounding = sdf_elements_3d_params[child_element.params_start - modifier_param_bump];

        rhs_sdf_gradient.x -= rounding;

        modifier_param_bump += 1;
    }

    if ((modifiers & SDF_ELEMENT_3D_MODIFIER_EXTRUSION) != 0) {
        float extrusion_height = sdf_elements_3d_params[child_element.params_start - modifier_param_bump];

        vec2 w = vec2(rhs_sdf_gradient.x, abs(transformed_point.z) - extrusion_height);
        rhs_sdf_gradient.x = min(max(w.x, w.y), 0.0) + length(max(w, 0.0));

        modifier_param_bump += 1;
    }

    rhs_sdf_gradient.x *= child_transform.uniform_scale;

    return rhs_sdf_gradient;
}

SDFResult3D evaluateSDF(
    uint root_element_index,
    vec3 sample_position,
    //The bounds in which the evaluation is occuring
    vec3 evaluation_bounds_min,
    vec3 evaluation_bounds_max
) {
    const uint stack_size = 8;

    uint element_stack[stack_size];
    uint element_child_index_stack[stack_size];
    uint element_sdf_transform_stack[stack_size];
    vec4 element_sdf_gradient_stack[stack_size];

    for (int i = 0; i < stack_size; i++) {
        element_child_index_stack[i] = 0;
    }

    uint element_stack_pointer = 1;

    element_stack[0] = root_element_index;

    while (element_stack_pointer != 0) {
        element_stack_pointer -= 1;
        uint element_index = element_stack[element_stack_pointer];
        SdfElement3D element = sdf_elements_3d[element_index];
        AffineTransform3D element_transform = sdf_elements_3d_transforms[element_index];

        vec3 element_bounds_min = element_transform.position;
        vec3 element_bounds_max = element_transform.position + sdf_elements_3d_bounds[element_index];

        element_bounds_min = max(element_bounds_min, evaluation_bounds_min);
        element_bounds_max = min(element_bounds_max, evaluation_bounds_max);

        if (any(lessThan(sample_position, element_bounds_min)) || any(greaterThan(sample_position, element_bounds_max))) {
            //continue;
        }

        vec4 lhs_sdf_gradient = element_sdf_gradient_stack[element_stack_pointer];
        vec4 rhs_sdf_gradient = vec4(0);

        uint lhs_transform = element_sdf_transform_stack[element_stack_pointer];
        uint rhs_transform = 0xffffffff;

        for (uint child_index = element_child_index_stack[element_stack_pointer]; child_index < element.children_count; child_index++) {
            uint child_element_index = element.children_start + child_index;
            SdfElement3D child_element = sdf_elements_3d[child_element_index];
            vec3 child_element_bounds_min = sdf_elements_3d_transforms[child_element_index].position;
            vec3 child_element_bounds_max = child_element_bounds_min + sdf_elements_3d_bounds[child_element_index];

            child_element_bounds_min = max(child_element_bounds_min, evaluation_bounds_min);
            child_element_bounds_max = min(child_element_bounds_max, evaluation_bounds_max);

            if (any(lessThan(sample_position, child_element_bounds_min)) || any(greaterThan(sample_position, child_element_bounds_max))) {
                //continue;
            }

            rhs_sdf_gradient = evaluateSdfElement3D(child_element_index, child_element.params_start, sample_position);
            rhs_transform = child_element_index;

            if (child_element.children_count != 0) {
                element_child_index_stack[element_stack_pointer] = child_index + 1;
                element_sdf_gradient_stack[element_stack_pointer] = lhs_sdf_gradient;
                element_sdf_transform_stack[element_stack_pointer] = lhs_transform;

                element_stack_pointer += 1;
                element_stack[element_stack_pointer] = element.children_start + child_index;
                element_child_index_stack[element_stack_pointer] = 0;
                element_sdf_transform_stack[element_stack_pointer] = 0;
                element_stack_pointer += 1;

                break;
            }

            if (child_index == 0) {
                lhs_sdf_gradient = rhs_sdf_gradient;
                lhs_transform = rhs_transform;
                continue;
            }

            switch (int(element.type) & SDF_ELEMENT_3D_TYPE_MASK) {
                case SDF_ELEMENT_3D_UNION:
                {
                    lhs_sdf_gradient = sdfGradientUnion(lhs_sdf_gradient, rhs_sdf_gradient);
                    lhs_transform = sdfUnionSelectInt(lhs_sdf_gradient, rhs_sdf_gradient, lhs_transform, rhs_transform);

                    break;
                }
                case SDF_ELEMENT_3D_INTERSECTION:
                {
                    lhs_sdf_gradient = sdfGradientIntersection(lhs_sdf_gradient, rhs_sdf_gradient);
                    lhs_transform = sdfIntersectionSelectInt(lhs_sdf_gradient, rhs_sdf_gradient, lhs_transform, rhs_transform);

                    break;
                }
                case SDF_ELEMENT_3D_DIFFERENCE:
                {
                    lhs_sdf_gradient = sdfGradientDifference(lhs_sdf_gradient, rhs_sdf_gradient);
                    lhs_transform = sdfDifferenceSelectInt(lhs_sdf_gradient, rhs_sdf_gradient, lhs_transform, rhs_transform);

                    break;
                }
                default:
                {
                    break;
                }
            }
        }

        element_sdf_gradient_stack[element_stack_pointer] = lhs_sdf_gradient;
        element_sdf_transform_stack[element_stack_pointer] = lhs_transform;

        switch (int(element.type) & SDF_ELEMENT_3D_TYPE_MASK) {
            case SDF_ELEMENT_3D_UNION:
            case SDF_ELEMENT_3D_INTERSECTION:
            case SDF_ELEMENT_3D_DIFFERENCE:
            {
                element_sdf_gradient_stack[element_stack_pointer] = lhs_sdf_gradient;
                break;
            }
            default:
            {
                vec4 lhs = evaluateSdfElement3D(element_index, element.params_start, sample_position);
                element_sdf_gradient_stack[element_stack_pointer] = sdfGradientUnion(lhs, lhs_sdf_gradient);
                break;
            }
        }
    }

    SDFResult3D result;

    result.sdf_gradient = element_sdf_gradient_stack[element_stack_pointer];
    result.transform = element_sdf_transform_stack[element_stack_pointer];
    result.material = 1;

    return result;
}
