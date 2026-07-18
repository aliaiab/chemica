#pragma once

#include <vector>
#include "GLFW/glfw3.h"
#include "Simulation.h"
#include "glm/glm.hpp"

struct Camera
{
    glm::vec3 eye = glm::vec3{180.000, 180.000, 180.000} * 0.5f;
    glm::vec3 target{};

    float fov = glm::radians(70.0f);
    float zoom = 1.0f;
    float near = 0.1f;
    float far = 1000.0f;

    glm::mat4 projection{1.0f};
    glm::mat4 view{1.0f};

    bool is_orthographic = false;
};

struct ProgramConfig
{
    bool devMode = false;
};

enum class CSGTreeType
{
    non_leaf,

    box,
    sphere,
};

union CSGTreeData
{
    struct
    {
        glm::vec3 bounds = glm::vec3(10);
    } box;
    struct
    {
        float radius = 10;
    } sphere;
};

struct CSGTree;

struct CSGTree
{
    CSGRigidTransform transform = CSGRigidTransform::identity();
    // zero = no shape
    CSGTreeType sdf_type;
    CSGTreeData data{};
    char name[16];
    union
    {
        struct
        {
            float h;
        } extrude;
    } unary_op_data;
    // Operation applied to the aggregate children before unioning with the parent
    CSGInstructionOp unary_op = CSGInstructionOp::IDENTITY;
    // Operation applied between children
    CSGInstructionOp child_op = CSGInstructionOp::BINARY_OP_UNION;
    std::vector<CSGTree> children;

    inline void intiializeCopy(const CSGTree &copy_from)
    {
        *this = copy_from;
        this->children = {};

        for (const auto child : copy_from.children)
        {
            auto &new_child = this->children.emplace_back();
            new_child.intiializeCopy(child);
        }
    }
};

struct CSGTreeReparentCommand
{
    CSGTree *source;
    CSGTree *source_parent;
    CSGTree *destination;
};

struct Program
{
    ProgramConfig config{};
    Simulation simulation{};
    VoxelMaterial materials[6];
    bool enableSimulation = false;
    GLFWwindow *window = nullptr;
    Camera camera{};
    glm::mat4 simulationTransform{1.0f};

    std::uint32_t environment_map_texture;
    std::uint32_t environment_map_shader_program;

    std::vector<CSGTree> csg_tree_root_nodes{};
    CSGTree *selected_tree = nullptr;
    CSGTree *selected_tree_parent = nullptr;
    std::vector<CSGTreeReparentCommand> csg_reparent_commands{};
    bool delete_selected_tree = false;
    CSGTree copied_tree;
    bool copy_selected_tree = false;

    // csg program
    std::vector<CSGInstruction> csg_instructions;
    std::vector<CSGInstructionBox> csg_instructions_box;
    std::vector<CSGInstructionSphere> csg_instructions_sphere;
    std::vector<CSGInstructionExtrudePost> csg_instructions_extrude_post;
    std::vector<CSGRigidTransform> csg_transforms;
    std::vector<CSGMaterialComponent> csg_material;

    float last_mouse_x = 0;
    float last_mouse_y = 0;

    float mouse_scroll = 0;

    struct RenderSettings
    {
        glm::vec4 clearColor = glm::unpackUnorm4x8(0xFF9B7C70);
        bool wireframe = false;
        bool gammaCorrect = false;
    } renderSettings{};

    int displayWidth = 0;
    int displayHeight = 0;

    void Initialize();
    void Shutdown();
    void OnImGuiRender();
    void OnImGuiCSGTreeNode(CSGTree *tree, CSGTree *parent);
    void CompileCSGTreeToProgram(CSGTree &tree, CSGTree *parent);
    void Render();
    void Run();
};