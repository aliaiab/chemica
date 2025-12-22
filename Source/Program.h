#pragma once

#include "GLFW/glfw3.h"
#include "Simulation.h"
#include "glm/glm.hpp"

struct Camera
{
    glm::vec3 eye = glm::vec3 { 180.000, 180.000, 180.000 } * 0.5f; 
    glm::vec3 target { };

    float fov = glm::radians(70.0f);
    float zoom = 1.0f;
    float near = 0.1f;
    float far = 1000.0f;

    glm::mat4 projection { 1.0f };
    glm::mat4 view { 1.0f }; 
};

struct ProgramConfig
{
    bool devMode = false;
};

struct Program
{
    ProgramConfig config { };
    Simulation simulation { };
    VoxelMaterial materials[6];
    bool enableSimulation = false;
    GLFWwindow* window = nullptr;
    Camera camera { };
    glm::mat4 simulationTransform { 1.0f };

    //csg program
    std::size_t csg_instructions_count = 0;
    CSGInstruction* csg_instructions = nullptr;
    CSGInstructionBox* csg_instructions_box = nullptr;
    CSGInstructionSphere* csg_instructions_sphere = nullptr;
    std::size_t csg_transforms_count = 0;
    CSGRigidTransform* csg_transforms = nullptr;
    CSGMaterialComponent* csg_material = nullptr;
    std::size_t csg_material_comp_count = 0; 

    float last_mouse_x = 0;
    float last_mouse_y = 0;

    float mouse_scroll = 0;

    struct RenderSettings
    {
        glm::vec4 clearColor = glm::unpackUnorm4x8(0xFF9B7C70);
        bool wireframe = false;
        bool gammaCorrect = false;
    } renderSettings { };

    int displayWidth = 0;
    int displayHeight = 0;

    void Initialize();
    void Shutdown();
    void OnImGuiRender();
    void Render();
    void Run();
};