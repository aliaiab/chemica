#pragma once

#include <glm/glm.hpp>
#include <cstdint>

#include "Simulation.h"

constexpr auto CelsiusToKelvin(std::int32_t celsius)
{
    return celsius + 273;
}

constexpr auto KelvinToCelsius(std::uint32_t kelvin)
{
    return kelvin - 273;
}

struct VoxelMaterial
{
    std::uint32_t density = 1;
    float heat_conductivity = 1;
    float heat_capacity = 1;
    float melting_point = 1000;
    float boiling_point = 2000;
};

struct VoxelMaterialVisual
{
    std::uint32_t albedo = 0;
    std::uint32_t roughness_metalness = glm::packUnorm4x8({1, 1, 0, 0});
    float reflectivity = 0;
    float refractive_index = 1.5;
};

enum struct VoxelPhase : std::uint32_t
{
    Solid,
    Liquid,
    Gas
};

#include "csg.h"

enum struct CSGInstructionOp : std::uint32_t
{
    IDENTITY = 0,
    BOX = CSG_BOX,
    SPHERE = CSG_SPHERE,
    PLANE = CSG_PLANE,
    TRIANGLE = CSG_TRIANGLE,
    CYLYNDER = CSG_CYLYNDER,
    CONE = CSG_CONE,
    TORUS = CSG_TORUS,

    BINARY_OP_UNION = CSG_BINARY_OP_UNION,
    BINARY_OP_INTERSECTION = CSG_BINARY_OP_INTERSECTION,
    BINARY_OP_DIFFERENCE = CSG_BINARY_OP_DIFFERENCE,
    BINARY_OP_XOR = CSG_BINARY_OP_XOR,
    BINARY_OP_SMOOTH_UNION = CSG_BINARY_OP_SMOOTH_UNION,
    BINARY_OP_SMOOTH_INTERSECTION = CSG_BINARY_OP_SMOOTH_INTERSECTION,
    BINARY_OP_SMOOTH_DIFFERENCE = CSG_BINARY_OP_SMOOTH_DIFFERENCE,
    UNARY_OP_REVOLVE = CSG_UNARY_OP_REVOLVE,
    UNARY_OP_ELONGATE = CSG_UNARY_OP_ELONGATE,
    UNARY_OP_EXTRUDE_PRE = CSG_UNARY_OP_EXTRUDE_PRE,
    UNARY_OP_EXTRUDE_POST = CSG_UNARY_OP_EXTRUDE_POST,
    POP_DISTANCE = CSG_POP_DISTANCE,
    POP_POSITION = CSG_POP_POSITION,
    TRANSFORM = CSG_TRANSFORM,
    TRANSFORM_POST = CSG_TRANSFORM_POST,
};

struct CSGInstruction
{
    CSGInstructionOp csg_op;
    // Index into the buffer of instructions of type csg_op
    std::uint32_t stream_index;
};

struct CSGInstructionBox
{
    glm::vec3 bounds;
    std::uint32_t rigid_transform;
    std::uint32_t material;
    uint8_t pad[12];
};

struct CSGInstructionSphere
{
    float radius;
    std::uint32_t rigid_transform;
    std::uint32_t material;
};

struct CSGInstructionExtrudePost
{
    float h;
};

struct CSGRigidTransform
{
    glm::vec3 position;
    float uniform_scale = 1;
    glm::vec4 rotation = {0, 0, 0, 1};

    static CSGRigidTransform identity()
    {
        return {
            .position = {0, 0, 0},
            .uniform_scale = 1,
            .rotation = {0, 0, 0, 1}};
    }
};

struct CSGMaterialComponent
{
    std::uint32_t material;
    float density;
};

struct CSGMaterial
{
    std::uint32_t component_start;
    std::uint32_t component_count;
    float min_temperature;
    float max_temperature;
};

struct CSGInvocation
{
    CSGRigidTransform transform;
    glm::ivec3 bound_min;
    glm::ivec3 bound_max;
};

struct PointLight
{
    glm::vec3 position;
    float radiance;
    std::uint32_t colour;
    std::uint32_t pad[3];
};

struct Simulation
{
    GLFWwindow *window;

    std::size_t width = 0;
    std::size_t height = 0;
    std::size_t depth = 0;
    std::size_t bufferLength = 0;

    glm::ivec3 baseVelocity{0, -1, 0};

    VoxelMaterial *voxelMaterials = nullptr;
    VoxelMaterialVisual *voxelMaterialsVisual = nullptr;
    std::size_t voxelMaterialCount = 0;

    std::uint32_t rendererProgram = 0;
    std::uint32_t vertexArray = 0;
    std::uint32_t vertexBuffer = 0;

    std::uint32_t dirtyCuboidShader = 0;

    std::uint32_t heatTexture = 0;
    std::uint32_t heatTextureShader = 0;
    std::uint32_t distanceFieldShader = 0;

    std::uint32_t voxel_allocator_bins_buffer = 0;
    std::uint32_t voxel_pallete_memory_buffer = 0;
    std::uint32_t voxel_bit_buffer_memory_buffer = 0;
    std::uint32_t voxel_pallete_counters_buffer = 0;
    std::uint32_t voxel_temperature_memory_buffer = 0;
    std::uint32_t voxel_allocator_buffer = 0;
    std::uint32_t voxel_chunks_buffer = 0;

    std::uint32_t simulationMaterialBuffers[2]{};
    std::uint32_t simulationDeviationBuffers[2]{};
    std::uint32_t simulationTemperatureBuffers[2]{};

    struct
    {
        glm::ivec3 min{0, 0, 0};
        glm::ivec3 max{1, 1, 1};
    } activeRegion;

    std::uint32_t activeRegionBuffer = 0;

    std::uint32_t voxelMaterialBuffer = 0;
    std::uint32_t voxelMaterialVisualBuffer = 0;

    std::uint32_t simulationShader = 0;
    std::uint32_t thermalShader = 0;
    std::uint32_t grain_simulation_shader = 0;
    std::uint32_t fill_region_shader = 0;

    bool csg_dirty = true;

    std::uint32_t point_light_buffer = 0;
    std::vector<PointLight> point_lights;

    std::uint32_t timestep_index = 0;

    std::uint32_t uniformBuffer = 0;

    std::uint32_t csg_instruction_buffer = 0;
    std::uint32_t csg_instructions_box_buffer = 0;
    std::uint32_t csg_instructions_sphere_buffer = 0;
    std::uint32_t csg_instructions_extrude_post_buffer = 0;
    std::uint32_t csg_transform_buffer = 0;
    std::uint32_t csg_composite_material_buffer = 0;

    CSGInvocation *csg_invocations = nullptr;
    std::size_t csg_invocation_count = 0;

    glm::mat4 model{};
    glm::mat4 view{};
    glm::mat4 projection{};

    void Create();
    void Destroy();

    void Update(bool enable_simulation);
    void Render();

    void UpdateCSGProgram(
        std::vector<CSGRigidTransform> &transforms,
        std::vector<CSGInstruction> &instructions,
        std::vector<CSGInstructionBox> &instructions_box,
        std::vector<CSGInstructionSphere> &instructions_sphere,
        std::vector<CSGInstructionExtrudePost> &instructions_extrude_post,
        std::vector<CSGMaterialComponent> &material,
        bool patch);
};

// Rotate the vector v by the quaternion q
inline glm::vec3 rotateVector(glm::vec4 q, glm::vec3 v)
{
    // return rotated;
    return v + 2.0f * glm::cross(glm::cross(v, glm::vec3(q)) + q.w * v, glm::vec3(q));
}

inline glm::vec3 transformPointForward(glm::vec3 point, CSGRigidTransform rigid_transform)
{
    glm::vec3 result = point * rigid_transform.uniform_scale;
    result = rotateVector(rigid_transform.rotation, result);
    result = result + rigid_transform.position;

    return result;
}

inline glm::vec3 transformPointReverse(glm::vec3 point, CSGRigidTransform rigid_transform)
{
    glm::vec3 result = (point - rigid_transform.position);

    return rotateVector(rigid_transform.rotation, result) * (1 / rigid_transform.uniform_scale);
}

inline CSGRigidTransform transformCompose(CSGRigidTransform lhs, CSGRigidTransform rhs)
{
    CSGRigidTransform result;

    result.position = lhs.position + rotateVector(lhs.rotation, rhs.position * lhs.uniform_scale);
    result.uniform_scale = lhs.uniform_scale * rhs.uniform_scale;
    result.rotation.w = lhs.rotation.w * rhs.rotation.w - glm::dot(glm::vec3(lhs.rotation), glm::vec3(rhs.rotation));
    result.rotation = glm::vec4(lhs.rotation.w * glm::vec3(rhs.rotation) + rhs.rotation.w * glm::vec3(lhs.rotation) - glm::cross(glm::vec3(lhs.rotation), glm::vec3(rhs.rotation)), result.rotation.w);

    return result;
}

struct AABB
{
    glm::vec3 min;
    glm::vec3 max;
};

// Computes the conservative bounding box enclosing the aabb as if it were an oriented box
inline AABB transformAABB(AABB aabb, CSGRigidTransform transform)
{
    glm::vec3 points[8] = {
        aabb.max + glm::vec3(1, 1, 1) * (aabb.min - aabb.max),
        aabb.max + glm::vec3(0, 0, 0) * (aabb.min - aabb.max),
        aabb.max + glm::vec3(1, 1, 0) * (aabb.min - aabb.max),
        aabb.max + glm::vec3(0, 1, 1) * (aabb.min - aabb.max),
        aabb.max + glm::vec3(1, 0, 0) * (aabb.min - aabb.max),
        aabb.max + glm::vec3(0, 1, 0) * (aabb.min - aabb.max),
        aabb.max + glm::vec3(0, 0, 1) * (aabb.min - aabb.max),
        aabb.max + glm::vec3(1, 0, 1) * (aabb.min - aabb.max),
    };

    for (int i = 0; i < 8; i++)
    {
        points[i] = transformPointForward(points[i], transform);
    }

    AABB result = {glm::vec3(INFINITY), glm::vec3(-INFINITY)};

    for (int i = 0; i < 8; i++)
    {
        result.min = glm::min(result.min, points[i]);
        result.max = glm::max(result.max, points[i]);
    }

    return result;
}

inline AABB unionAABB(AABB lhs, AABB rhs)
{
    AABB result;

    result.min = min(lhs.min, rhs.min);
    result.max = max(lhs.max, rhs.max);

    return result;
}

inline AABB intersectAABB(AABB lhs, AABB rhs)
{
    AABB result;

    result.min = max(lhs.min, rhs.min);
    result.max = min(lhs.max, rhs.max);

    return result;
}