#version 450
#extension GL_GOOGLE_include_directive : enable
#extension GL_ARB_shader_draw_parameters : enable

#include "asym.glsl"

layout(location = 0) out Out
{
    vec3 position;
    vec4 colour;
    vec2 uv;
    flat uint draw_id;
} vertex_out;

const vec2 triangle_vertices[3] = vec2[3](
        vec2(-0.5, -0.5),
        vec2(0.5, -0.5),
        vec2(0, 0.5)
    );

const vec2 quad_vertices[4] = vec2[4](
        vec2(-0.5, -0.5),
        vec2(0.5, -0.5),
        vec2(0.5, 0.5),
        vec2(-0.5, 0.5)
    );

const vec2 quad_uv[4] = vec2[4](
        vec2(0, 0),
        vec2(1, 0),
        vec2(1, 1),
        vec2(0, 1)
    );

const uint quad_indices[6] = uint[6](
        0,
        1,
        2,
        0,
        3,
        2
    );

void main() {
    vec3 vertex_position = vec3(0);

    vertex_out.draw_id = gl_DrawIDARB;

    DrawCommand draw = draws.data[gl_DrawIDARB];

    switch (draw.primitive_type) {
        case PrimitiveType_circle:
        {
            vertex_position = vec3(triangle_vertices[gl_VertexID], 0);
            break;
        }
        case PrimitiveType_box:
        {
            vertex_position = vec3(quad_vertices[quad_indices[gl_VertexID]], 0);
            break;
        }
        case PrimitiveType_text:
        {
            vertex_position = vec3(quad_vertices[quad_indices[gl_VertexID]], 0);
            vertex_out.uv = quad_uv[quad_indices[gl_VertexID]];
        }
        default:
        {
            vertex_position = vec3(triangle_vertices[gl_VertexID], 0);
            vertex_position = vec3(quad_vertices[quad_indices[gl_VertexID]], 0);
            vertex_out.uv = quad_uv[quad_indices[gl_VertexID]];
            break;
        }
    }

    float bounds_x = parameters.data[draw.parameters_begin];
    float bounds_y = parameters.data[draw.parameters_begin + 1];

    vertex_position.x *= bounds_x / 4;
    vertex_position.y *= bounds_y / 2;

    vertex_out.position = vec3(uniforms.view_projection * vec4(vertex_position, 1.0));

    Material material = materials.data[draw.materials_begin + gl_InstanceID];
    AffineTransform3D transform = transforms.data[draw.transforms_begin + gl_InstanceID];

    vertex_out.colour = unpackUnorm4x8(material.colour);

    vertex_position *= transform.scale;
    vertex_position += transform.position;

    gl_Position = uniforms.view_projection * vec4(vertex_position, 1.0);
}
