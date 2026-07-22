#include <glad/glad.h>
#include <GLFW/glfw3.h>
#include <cstdio>
#include <cstring>
#include <glm/gtc/type_ptr.hpp>
#include <vector>

#include "Shaders/Include/BlackBodyCompute.h"
#include "Shaders/Include/RendererFragment.h"
#include "Shaders/Include/RendererVertex.h"
#include "Shaders/Include/SimulationCompute.h"
#include "Shaders/Include/DistanceFieldCompute.h"
#include "Shaders/Include/ThermalCompute.h"
#include "Shaders/Include/GrainSimulation.h"
#include "Shaders/Include/FillRegion.h"
#include "Simulation.h"
#include "shader.h"

static constexpr auto dirtyCuboidVertexSource = R"(
    #version 450

    layout(location = 0) in vec3 aPosition;

    layout(location = 0) uniform mat4 model;
    layout(location = 1) uniform mat4 view;
    layout(location = 2) uniform mat4 projection;

    void main()
    {
        gl_Position = projection * view * model * vec4(aPosition, 1.0);
    }
)";

static constexpr auto dirtyCuboidFragmentSource = R"(
    #version 450

    layout(location = 0) out vec4 aColor;

    void main()
    {
        aColor = vec4(0.0, 1.0, 0.0, 0.5);
    }
)";

struct ShaderData
{
    glm::mat4 uModel;
    glm::mat4 uView;
    glm::mat4 uProjection;
    glm::uvec3 uSize;
    std::uint32_t padding0 = 0;
    glm::ivec3 uBaseVelocity;
    std::uint32_t substep_index;
    // CSG parameters
    CSGRigidTransform root_transform;
    glm::ivec3 csg_bounding_min;
    std::uint32_t padding1 = 0;
    glm::ivec3 csg_bounding_max;
    std::uint32_t padding2 = 0;
    float delta_time;
    glm::uvec2 window_size;
};

struct VoxelAllocatorBins
{
    // Indexed by bit count - 1
    // Contains indices into voxel_allocators
    std::int32_t voxel_allocator_bin[15];
    std::uint32_t allocators_bump;
    std::uint32_t voxel_temperature_bump;
    std::uint32_t voxel_pallete_bump;
    std::uint32_t voxel_pallete_counters_bump;
    std::uint32_t voxel_bit_buffer_bump;
    // Index of the chunk grid used as input (t0), 0 or 1,
    // output_chunk_grid = 1 - input_chunk_grid
    std::uint32_t input_chunk_grid;
    std::uint32_t pad[3];
    // The position of the chunk containing 0, 0, 0 within the chunk grid
    glm::uvec3 chunk_grid_size;
    std::uint32_t allocation_lock;
};

struct VoxelChunkAllocator
{
    std::int32_t next_allocator;

    std::uint32_t pallete_memory_start;
    std::uint32_t pallete_counters_start;
    std::uint32_t bit_buffer_memory_start;
    std::uint32_t temperature_buffer_start;
    std::uint32_t deviation_buffer_start;

    std::uint32_t memory_allocated_bits;
};

void Simulation::Create()
{
    bufferLength = width * height * depth;

    ShaderSource rendererShaders[2]{
        {GL_VERTEX_SHADER, rendererVertexBinary, sizeof(rendererVertexBinary)},
        {GL_FRAGMENT_SHADER, rendererFragmentBinary, sizeof(rendererFragmentBinary)}};

    ShaderSource blackbodyShader{GL_COMPUTE_SHADER, blackBodyComputeBinary, sizeof(blackBodyComputeBinary)};
    ShaderSource simulationShaderSource{GL_COMPUTE_SHADER, simulationComputeBinary, sizeof(simulationComputeBinary)};
    ShaderSource distanceFieldShaderSource{GL_COMPUTE_SHADER, distanceFieldComputeBinary, sizeof(distanceFieldComputeBinary)};
    ShaderSource thermalShaderSource{GL_COMPUTE_SHADER, thermalComputeBinary, sizeof(thermalComputeBinary)};
    ShaderSource grain_simulation_shader_source{GL_COMPUTE_SHADER, grainSimulationBinary, sizeof(grainSimulationBinary)};
    ShaderSource fill_region_shader_source{GL_COMPUTE_SHADER, fillRegionBinary, sizeof(fillRegionBinary)};

    rendererProgram = LoadProgram(rendererShaders, 2);
    heatTextureShader = LoadProgram(&blackbodyShader, 1);
    simulationShader = LoadProgram(&simulationShaderSource, 1);
    distanceFieldShader = LoadProgram(&distanceFieldShaderSource, 1);
    thermalShader = LoadProgram(&thermalShaderSource, 1);
    grain_simulation_shader = LoadProgram(&grain_simulation_shader_source, 1);
    fill_region_shader = LoadProgram(&fill_region_shader_source, 1);

    glCreateBuffers(1, &activeRegionBuffer);

    glNamedBufferStorage(activeRegionBuffer, sizeof(activeRegion), &activeRegion, GL_DYNAMIC_STORAGE_BIT);

    glCreateVertexArrays(1, &vertexArray);
    glCreateBuffers(1, &vertexBuffer);

    glVertexArrayVertexBuffer(vertexArray, 0, vertexBuffer, 0, sizeof(glm::vec3));

    glEnableVertexArrayAttrib(vertexArray, 0);

    glVertexArrayAttribFormat(vertexArray, 0, 3, GL_FLOAT, GL_FALSE, 0);

    glVertexArrayAttribBinding(vertexArray, 0, 0);

    const float vertices[]{
        0.0f, 0.0f, 0.0f,
        1.0f, 1.0f, 0.0f,
        1.0f, 0.0f, 0.0f,
        1.0f, 1.0f, 0.0f,
        0.0f, 0.0f, 0.0f,
        0.0f, 1.0f, 0.0f,
        0.0f, 0.0f, 1.0f,
        1.0f, 0.0f, 1.0f,
        1.0f, 1.0f, 1.0f,
        1.0f, 1.0f, 1.0f,
        0.0f, 1.0f, 1.0f,
        0.0f, 0.0f, 1.0f,
        0.0f, 1.0f, 1.0f,
        0.0f, 1.0f, 0.0f,
        0.0f, 0.0f, 0.0f,
        0.0f, 0.0f, 0.0f,
        0.0f, 0.0f, 1.0f,
        0.0f, 1.0f, 1.0f,
        1.0f, 1.0f, 1.0f,
        1.0f, 0.0f, 0.0f,
        1.0f, 1.0f, 0.0f,
        1.0f, 0.0f, 0.0f,
        1.0f, 1.0f, 1.0f,
        1.0f, 0.0f, 1.0f,
        0.0f, 0.0f, 0.0f,
        1.0f, 0.0f, 0.0f,
        1.0f, 0.0f, 1.0f,
        1.0f, 0.0f, 1.0f,
        0.0f, 0.0f, 1.0f,
        0.0f, 0.0f, 0.0f,
        0.0f, 1.0f, 0.0f,
        1.0f, 1.0f, 1.0f,
        1.0f, 1.0f, 0.0f,
        1.0f, 1.0f, 1.0f,
        0.0f, 1.0f, 0.0f,
        0.0f, 1.0f, 1.0f};

    glNamedBufferStorage(vertexBuffer, sizeof(vertices), vertices, GL_DYNAMIC_STORAGE_BIT);

    {
        dirtyCuboidShader = glCreateProgram();

        const auto dirtyCuboidVertexShader = glCreateShader(GL_VERTEX_SHADER);
        const auto dirtyCuboidFragmentShader = glCreateShader(GL_FRAGMENT_SHADER);

        glShaderSource(dirtyCuboidVertexShader, 1, &dirtyCuboidVertexSource, nullptr);
        glShaderSource(dirtyCuboidFragmentShader, 1, &dirtyCuboidFragmentSource, nullptr);

        glAttachShader(dirtyCuboidShader, dirtyCuboidVertexShader);
        glAttachShader(dirtyCuboidShader, dirtyCuboidFragmentShader);

        glLinkProgram(dirtyCuboidShader);

        glDetachShader(dirtyCuboidShader, dirtyCuboidFragmentShader);
        glDetachShader(dirtyCuboidShader, dirtyCuboidVertexShader);

        glDeleteShader(dirtyCuboidFragmentShader);
        glDeleteShader(dirtyCuboidVertexShader);
    }

    glCreateTextures(GL_TEXTURE_3D, 1, &heatTexture);

    glTextureStorage3D(heatTexture, 1, GL_RGBA8, width, height, depth);

    glCreateBuffers(1, &uniformBuffer);

    ShaderData uniforms;

    uniforms.uSize = {width, height, depth};
    uniforms.uBaseVelocity = baseVelocity;

    glNamedBufferStorage(uniformBuffer, sizeof(uniforms), &uniforms, GL_DYNAMIC_STORAGE_BIT);

    glCreateBuffers(2, simulationMaterialBuffers);
    glCreateBuffers(2, simulationTemperatureBuffers);
    glCreateBuffers(2, simulationDeviationBuffers);

    glCreateBuffers(1, &csg_instruction_buffer);
    glCreateBuffers(1, &csg_instructions_box_buffer);
    glCreateBuffers(1, &csg_instructions_sphere_buffer);
    glCreateBuffers(1, &csg_instructions_extrude_post_buffer);
    glCreateBuffers(1, &csg_transform_buffer);

    glCreateBuffers(1, &voxel_allocator_bins_buffer);
    glCreateBuffers(1, &voxel_pallete_memory_buffer);
    glCreateBuffers(1, &voxel_pallete_counters_buffer);
    glCreateBuffers(1, &voxel_bit_buffer_memory_buffer);
    glCreateBuffers(1, &voxel_temperature_memory_buffer);
    glCreateBuffers(1, &voxel_allocator_buffer);
    glCreateBuffers(1, &voxel_chunks_buffer);

    const GLbitfield storageFlags = GL_DYNAMIC_STORAGE_BIT;

    VoxelAllocatorBins initial_bins{};

    for (int i = 0; i < 15; i++)
    {
        initial_bins.voxel_allocator_bin[i] = -1;
    }

    initial_bins.chunk_grid_size = glm::uvec3(64);
    initial_bins.allocation_lock = 0;

    glNamedBufferStorage(voxel_allocator_bins_buffer, sizeof(VoxelAllocatorBins), &initial_bins, storageFlags);
    glNamedBufferStorage(voxel_pallete_memory_buffer, 32 * 1024 * sizeof(uint16_t), nullptr, storageFlags);
    glNamedBufferStorage(voxel_pallete_counters_buffer, 4 * 1024 * sizeof(uint32_t), nullptr, storageFlags);
    glNamedBufferStorage(voxel_bit_buffer_memory_buffer, 32 * 1024 * sizeof(uint32_t), nullptr, storageFlags);
    glNamedBufferStorage(voxel_temperature_memory_buffer, 16 * 1024 * sizeof(uint16_t), nullptr, storageFlags);
    glNamedBufferStorage(voxel_allocator_buffer, 1024 * sizeof(VoxelChunkAllocator), nullptr, storageFlags);
    glNamedBufferStorage(voxel_chunks_buffer, 2 * 64 * 64 * 64 * sizeof(uint64_t), nullptr, storageFlags);

    std::uint32_t chunk_allocation_fill = 0xffffffff;

    glClearNamedBufferData(voxel_chunks_buffer, GL_RG32UI, GL_RED, GL_UNSIGNED_INT, &chunk_allocation_fill);

    glNamedBufferStorage(simulationMaterialBuffers[0], bufferLength * sizeof(std::uint16_t), nullptr, storageFlags);
    glNamedBufferStorage(simulationMaterialBuffers[1], bufferLength * sizeof(std::uint16_t), nullptr, storageFlags);

    glNamedBufferStorage(simulationTemperatureBuffers[0], bufferLength * sizeof(float), nullptr, storageFlags);
    glNamedBufferStorage(simulationTemperatureBuffers[1], bufferLength * sizeof(float), nullptr, storageFlags);

    glNamedBufferStorage(simulationDeviationBuffers[0], bufferLength * sizeof(std::uint8_t), nullptr, storageFlags);
    glNamedBufferStorage(simulationDeviationBuffers[1], bufferLength * sizeof(std::uint8_t), nullptr, storageFlags);

    glCreateBuffers(1, &voxelMaterialBuffer);

    glNamedBufferData(voxelMaterialBuffer, sizeof(VoxelMaterial) * voxelMaterialCount, voxelMaterials, GL_DYNAMIC_DRAW);

    glCreateBuffers(1, &voxelMaterialVisualBuffer);

    glNamedBufferData(voxelMaterialBuffer, sizeof(VoxelMaterialVisual) * voxelMaterialCount, voxelMaterialsVisual, GL_DYNAMIC_DRAW);

    glCreateBuffers(1, &csg_composite_material_buffer);
    glCreateBuffers(1, &this->point_light_buffer);
}

void Simulation::Destroy()
{
    glDeleteProgram(rendererProgram);
    glDeleteProgram(heatTextureShader);
    glDeleteProgram(simulationShader);
    glDeleteProgram(distanceFieldShader);
    glDeleteProgram(dirtyCuboidShader);

    glDeleteBuffers(2, simulationMaterialBuffers);
    glDeleteTextures(1, &heatTexture);

    glDeleteBuffers(1, &vertexBuffer);
    glDeleteVertexArrays(1, &vertexArray);
}

void Simulation::UpdateCSGProgram(
    std::vector<CSGRigidTransform> &transforms,
    std::vector<CSGInstruction> &instructions,
    std::vector<CSGInstructionBox> &instructions_box,
    std::vector<CSGInstructionSphere> &instructions_sphere,
    std::vector<CSGInstructionExtrudePost> &instructions_extrude_post,
    std::vector<CSGMaterialComponent> &material,
    bool patch)
{
    if (instructions.size() == 0)
        return;

    assert(transforms.size() != 0);

    AABB bounding_box_stack[16];
    uint32_t stack_pointer = 0;

    const auto root_transform = this->csg_invocations[0].transform;

    for (const auto instruction : instructions)
    {
        switch (instruction.csg_op)
        {
        case CSGInstructionOp::BOX:
        {
            const auto box = instructions_box[instruction.stream_index];
            const auto transform = transforms[box.rigid_transform];

            auto bounding_box = transformAABB({-box.bounds, box.bounds}, transform);

            bounding_box_stack[stack_pointer++] = bounding_box;

            break;
        }
        case CSGInstructionOp::SPHERE:
        {
            const auto sphere = instructions_sphere[instruction.stream_index];
            const auto transform = transforms[sphere.rigid_transform];

            auto bounding_box = transformAABB({-glm::vec3(sphere.radius), glm::vec3(sphere.radius)}, transform);

            bounding_box_stack[stack_pointer++] = bounding_box;

            break;
        }
        case CSGInstructionOp::BINARY_OP_UNION:
        case CSGInstructionOp::BINARY_OP_DIFFERENCE:
        {
            const auto rhs = bounding_box_stack[--stack_pointer];
            const auto lhs = bounding_box_stack[--stack_pointer];

            bounding_box_stack[stack_pointer++] = unionAABB(lhs, rhs);

            break;
        }
        case CSGInstructionOp::BINARY_OP_INTERSECTION:
        {
            const auto rhs = bounding_box_stack[--stack_pointer];
            const auto lhs = bounding_box_stack[--stack_pointer];

            bounding_box_stack[stack_pointer++] = intersectAABB(lhs, rhs);

            break;
        }
        }
    }

    bounding_box_stack[stack_pointer - 1] = transformAABB(bounding_box_stack[stack_pointer - 1], root_transform);

    // this->csg_invocations[0].bound_min = bounding_box_stack[stack_pointer - 1].min;
    // this->csg_invocations[0].bound_max = bounding_box_stack[stack_pointer - 1].max;

    this->csg_invocations[0].bound_min = glm::vec3(0);
    this->csg_invocations[0].bound_max = glm::vec3(this->width, this->height, this->depth);

    glNamedBufferData(csg_instruction_buffer, instructions.size() * sizeof(CSGInstruction), &instructions[0], GL_DYNAMIC_DRAW);
    if (instructions_box.size() > 0)
    {
        glNamedBufferData(csg_instructions_box_buffer, instructions_box.size() * sizeof(CSGInstructionBox), &instructions_box[0], GL_DYNAMIC_DRAW);
    }

    if (instructions_sphere.size() > 0)
    {
        glNamedBufferData(csg_instructions_sphere_buffer, instructions_sphere.size() * sizeof(CSGInstructionSphere), &instructions_sphere[0], GL_DYNAMIC_DRAW);
    }

    if (instructions_extrude_post.size() > 0)
    {

        glNamedBufferData(csg_instructions_extrude_post_buffer, instructions_extrude_post.size() * sizeof(CSGInstructionExtrudePost), &instructions_extrude_post[0], GL_DYNAMIC_DRAW);
    }

    glNamedBufferData(csg_transform_buffer, transforms.size() * sizeof(CSGRigidTransform), &transforms[0], GL_DYNAMIC_DRAW);
    glNamedBufferData(csg_composite_material_buffer, material.size() * sizeof(CSGMaterialComponent), &material[0], GL_DYNAMIC_DRAW);
}

void Simulation::Update(bool enable_simulation)
{
    glNamedBufferData(voxelMaterialBuffer, sizeof(VoxelMaterial) * voxelMaterialCount, voxelMaterials, GL_DYNAMIC_DRAW);
    glNamedBufferData(voxelMaterialVisualBuffer, sizeof(VoxelMaterialVisual) * voxelMaterialCount, voxelMaterialsVisual, GL_DYNAMIC_DRAW);

    ShaderData uniforms;

    uniforms.uSize = {width, height, depth};
    uniforms.uBaseVelocity = baseVelocity;
    uniforms.uModel = model;
    uniforms.uView = view;
    uniforms.uProjection = projection;
    uniforms.root_transform = csg_invocations[0].transform;
    uniforms.csg_bounding_min = csg_invocations[0].bound_min;
    uniforms.csg_bounding_max = csg_invocations[0].bound_max;

    std::int32_t window_x;
    std::int32_t window_y;

    glfwGetFramebufferSize(window, &window_x, &window_y);

    uniforms.window_size = {window_x, window_y};

    glNamedBufferSubData(uniformBuffer, 0, sizeof(uniforms), &uniforms);
    glNamedBufferSubData(activeRegionBuffer, 0, sizeof(activeRegion), &activeRegion);
    glNamedBufferData(this->point_light_buffer, this->point_lights.size() * sizeof(PointLight), &this->point_lights[0], GL_DYNAMIC_DRAW);

    glBindBufferBase(GL_UNIFORM_BUFFER, 0, uniformBuffer);

    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, simulationTemperatureBuffers[0]);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, simulationTemperatureBuffers[1]);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 2, voxelMaterialBuffer);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 23, voxelMaterialVisualBuffer);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 3, activeRegionBuffer);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 4, simulationMaterialBuffers[0]);

    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 10, csg_transform_buffer);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 11, csg_instruction_buffer);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 12, csg_instructions_box_buffer);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 13, csg_instructions_sphere_buffer);

    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 30, csg_instructions_extrude_post_buffer);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 14, csg_composite_material_buffer);

    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 20, simulationDeviationBuffers[0]);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 21, simulationDeviationBuffers[1]);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 22, this->point_light_buffer);

    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 24, this->voxel_pallete_memory_buffer);
    // glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 31, this->voxel_pallete_counters_buffer);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 25, this->voxel_bit_buffer_memory_buffer);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 26, this->voxel_temperature_memory_buffer);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 27, this->voxel_allocator_buffer);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 28, this->voxel_allocator_bins_buffer);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 29, this->voxel_chunks_buffer);

    glUseProgram(fill_region_shader);

    if (!enable_simulation && csg_dirty)
    {
        csg_dirty = false;

        uint32_t material_clear = 0;
        float temperature_clear = 0;
        int8_t deviation_clear = 0;

        glClearNamedBufferData(simulationMaterialBuffers[0], GL_R32UI, GL_RED, GL_UNSIGNED_INT, &material_clear);
        glClearNamedBufferData(simulationTemperatureBuffers[0], GL_R32UI, GL_RED, GL_FLOAT, &temperature_clear);
        glClearNamedBufferData(simulationDeviationBuffers[0], GL_R8I, GL_RED, GL_BYTE, &deviation_clear);

        glm::ivec3 fill_bound = uniforms.csg_bounding_max - uniforms.csg_bounding_min;

        glm::ivec3 fill_extents = glm::min(glm::ivec3{width, height, depth}, uniforms.csg_bounding_max - uniforms.csg_bounding_min);

        // Compute the divCeil(fill_extents, 8)
        fill_extents = (fill_extents + glm::ivec3(8) - 1) / glm::ivec3(8);

        if (fill_bound.x * fill_bound.y * fill_bound.z != 0)
        {
            glDispatchCompute(fill_extents.x, fill_extents.y, fill_extents.z);
        }
    }

    glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT);

    if (enable_simulation)
    {
        glUseProgram(thermalShader);

        glDispatchCompute(width / 8, height / 8, depth / 8);

        glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT);

        const auto grain_passes = 1;

        uint32_t input_buffer_index = 0;

        glUseProgram(this->grain_simulation_shader);
        glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 2, voxelMaterialBuffer);

        for (int n = 0; n < grain_passes; n += 1)
        {
            const auto output_buffer_index = 1 - input_buffer_index;

            glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 4, this->simulationMaterialBuffers[input_buffer_index]);
            glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 5, this->simulationMaterialBuffers[output_buffer_index]);
            glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 6, this->simulationTemperatureBuffers[input_buffer_index]);
            glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 7, this->simulationTemperatureBuffers[output_buffer_index]);
            uniforms.substep_index = timestep_index * grain_passes + n;
            glNamedBufferSubData(uniformBuffer, 0, sizeof(uniforms), &uniforms);

            glDispatchCompute(width / 8, height / 8, depth / 8);

            input_buffer_index = 1 - input_buffer_index;
        }

        glMemoryBarrier(GL_SHADER_STORAGE_BARRIER_BIT);

        glGetNamedBufferSubData(activeRegionBuffer, 0, sizeof(activeRegion), &activeRegion);

        glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 3, 0);
        glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 2, 0);
        glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, 0);
        glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, 0);

        glBindBufferBase(GL_UNIFORM_BUFFER, 0, 0);
    }

    {
        const auto temporary = simulationMaterialBuffers[0];

        simulationMaterialBuffers[0] = simulationMaterialBuffers[1];
        simulationMaterialBuffers[1] = simulationMaterialBuffers[0];
    }

    {
        const auto temporary = simulationTemperatureBuffers[0];

        simulationTemperatureBuffers[0] = simulationTemperatureBuffers[1];
        simulationTemperatureBuffers[1] = simulationTemperatureBuffers[0];
    }

    {
        const auto temporary = simulationDeviationBuffers[0];

        simulationDeviationBuffers[0] = simulationDeviationBuffers[1];
        simulationDeviationBuffers[1] = simulationDeviationBuffers[0];
    }

    timestep_index += 1;
}

void Simulation::Render()
{
    ShaderData uniforms;

    uniforms.uSize = {width, height, depth};
    uniforms.uBaseVelocity = baseVelocity;
    uniforms.uModel = model;
    uniforms.uView = view;
    uniforms.uProjection = projection;

    std::int32_t window_x;
    std::int32_t window_y;

    glfwGetFramebufferSize(window, &window_x, &window_y);

    uniforms.window_size = {window_x, window_y};

    glNamedBufferSubData(uniformBuffer, 0, sizeof(uniforms), &uniforms);

    glBindBufferBase(GL_UNIFORM_BUFFER, 0, uniformBuffer);

    glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT);

    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, voxelMaterialBuffer);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, simulationMaterialBuffers[0]);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 2, simulationTemperatureBuffers[0]);

    glUseProgram(rendererProgram);
    glBindVertexArray(vertexArray);
    glBindTextureUnit(2, heatTexture);

    glCullFace(GL_FRONT);
    glEnable(GL_CULL_FACE);

    glDrawArrays(GL_TRIANGLES, 0, 36);
    glEnable(GL_CULL_FACE);
    glCullFace(GL_BACK);

    glBindTextureUnit(2, 0);
    glBindVertexArray(0);
    glUseProgram(0);

    glBindBufferBase(GL_UNIFORM_BUFFER, 0, 0);

    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 1, 0);
    glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, 0);

    auto dirtyCuboidTransform = glm::identity<glm::mat4>();

    dirtyCuboidTransform = glm::translate(dirtyCuboidTransform, glm::vec3(activeRegion.min));
    dirtyCuboidTransform = glm::scale(dirtyCuboidTransform, glm::vec3(activeRegion.max));
}