#include <cstdio>
#include <imgui.h>
#include <backends/imgui_impl_opengl3.h>
#include <backends/imgui_impl_glfw.h>
#define GLM_ENABLE_EXPERIMENTAL
#include <glm/gtx/transform.hpp>
#include <glm/gtc/type_ptr.hpp>
#include <glm/gtx/matrix_decompose.hpp>
#include <glm/ext/quaternion_transform.hpp>
#include <glad/glad.h>
#include <unistd.h>
#define STB_IMAGE_IMPLEMENTATION
#include <stb_image.h>
#include "shader.h"
#include "Shaders/Include/EnvMapVertex.h"
#include "Shaders/Include/EnvMapFragment.h"

#include "ImGuizmo.h"
#include "Program.h"

#define ARRAY_LENGTH(x) sizeof(x) / sizeof(*x)

static void GLDebugMessageCallback(
    const GLenum source,
    const GLenum type,
    const GLuint id,
    const GLenum severity,
    const GLsizei length,
    const GLchar *const message,
    const void *const user_param)
{
    std::fprintf(stderr, "[OpenGL]: %s\n", message);
};

static void scrollCallback(GLFWwindow *window, double xscroll, double yscroll)
{
    const auto self = (Program *)glfwGetWindowUserPointer(window);

    self->mouse_scroll = -yscroll * 0.1;
}

void imGuiEnableDepthTestingCallback(const ImDrawList *parent_list, const ImDrawCmd *cmd)
{
    glEnable(GL_DEPTH_TEST);
    glDepthMask(true);
    glDepthFunc(GL_GEQUAL);

    std::printf("Enable Depth Testing");
}

void imguiDisableDepthTestingCallback(const ImDrawList *parent_list, const ImDrawCmd *cmd)
{
    glDepthFunc(GL_LESS);
    glDisable(GL_DEPTH_TEST);

    std::printf("Disable Depth Testing");
}

void Program::Initialize()
{
    glfwInit();

    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 6);
    glfwWindowHint(GLFW_OPENGL_DEBUG_CONTEXT, true);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

    window = glfwCreateWindow(640, 480, "Chemica", nullptr, nullptr);

    assert(window != nullptr);

    glfwSetWindowUserPointer(window, this);

    glfwMaximizeWindow(window);
    glfwMakeContextCurrent(window);
    glfwSwapInterval(0);

    gladLoadGL();

    glEnable(GL_BLEND);
    glEnable(GL_DEPTH_TEST);
    glEnable(GL_DEBUG_OUTPUT);

    glEnable(GL_CULL_FACE);
    glCullFace(GL_BACK);
    glFrontFace(GL_CCW);

    glDepthMask(true);
    glDepthFunc(GL_LESS);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    glDebugMessageControl(GL_DONT_CARE, GL_DONT_CARE, GL_DEBUG_SEVERITY_NOTIFICATION, 0, nullptr, GL_FALSE);
    glDebugMessageCallback(GLDebugMessageCallback, nullptr);

    simulation.width = 128;
    simulation.height = 128;
    simulation.depth = 128;

    const char *materialNames[]{
        "Sand",
        "Stone",
        "Water",
        "Copper",
        "Glass"};

    memset(materials, 0, sizeof(materials));
    memset(voxel_materials_visual, 0, sizeof(voxel_materials_visual));

    for (int i = 0; i < ARRAY_LENGTH(materials); i++)
    {
        materials[i] = {};
        materials[i].melting_point = 100000;
        voxel_materials_visual[i] = {};
    }

    voxel_materials_visual[0].albedo = 0;
    materials[0].heat_conductivity = 0;

    voxel_materials_visual[1].albedo = glm::packUnorm4x8({0.89f, 0.79f, 0.55f, 1.0f});
    materials[1].heat_conductivity = 0.5;

    voxel_materials_visual[2].albedo = glm::packUnorm4x8({0.29f, 0.29f, 0.29f, 1.0f});
    materials[2].heat_conductivity = 1;
    materials[2].melting_point = 1000;

    voxel_materials_visual[3].albedo = glm::packUnorm4x8({0.17f, 0.56f, 0.82f, 0.19f});
    materials[3].heat_conductivity = 0.9;

    // materials[4].color = glm::packUnorm4x8({ 0.72f, 0.45f, 0.2f, 1.0f });
    voxel_materials_visual[4].albedo = 0xff1d2971;
    materials[4].heat_conductivity = 3;
    materials[4].melting_point = 3000;

    voxel_materials_visual[5].albedo = glm::packUnorm4x8({0.9f, 0.5f, 0.5f, 0.5f});
    materials[5].heat_conductivity = 0.3;

    simulation.voxelMaterials = materials;
    simulation.voxelMaterialsVisual = voxel_materials_visual;
    simulation.voxelMaterialCount = ARRAY_LENGTH(materials);

    simulation.Create();

    camera.target = glm::vec3{simulation.width, simulation.height, simulation.depth} * 0.5f;

    camera.view = glm::lookAt(camera.eye, camera.target, glm::vec3{0.0f, 1.0f, 0.0f});

    if (config.devMode)
    {
        ImGui::CreateContext();

        ImGui_ImplGlfw_InitForOpenGL(window, true);
        ImGui_ImplOpenGL3_Init("#version 450");

        ImGuizmo::SetImGuiContext(ImGui::GetCurrentContext());
        ImGuizmo::Enable(true);
        ImGuizmo::SetOrthographic(camera.is_orthographic);
    }

    simulationTransform = glm::scale(simulationTransform, {1, 1, 1});
    simulationTransform = glm::translate(simulationTransform, {0, 0, 0});

    double cursor_pos_x, cursor_pos_y;
    glfwGetCursorPos(window, &cursor_pos_x, &cursor_pos_y);

    last_mouse_x = cursor_pos_x;
    last_mouse_y = cursor_pos_y;

    glfwSetScrollCallback(window, &scrollCallback);

    CSGInstruction instructions[7] = {
        {.csg_op = CSGInstructionOp::UNARY_OP_REVOLVE, .stream_index = 0},
        {.csg_op = CSGInstructionOp::UNARY_OP_EXTRUDE_PRE, .stream_index = 0},
        {.csg_op = CSGInstructionOp::SPHERE, .stream_index = 0},

        {.csg_op = CSGInstructionOp::UNARY_OP_EXTRUDE_POST, .stream_index = 0},
        {.csg_op = CSGInstructionOp::BOX, .stream_index = 0},
        {.csg_op = CSGInstructionOp::BINARY_OP_INTERSECTION, .stream_index = 0},

        // {.csg_op = CSGInstructionOp::BOX, .stream_index = 0},
        // {.csg_op = CSGInstructionOp::BINARY_OP_DIFFERENCE, .stream_index = 0},
        // {.csg_op = CSGInstructionOp::BOX, .stream_index = 1},
        // {.csg_op = CSGInstructionOp::BINARY_OP_UNION, .stream_index/ = 0},
        // {.csg_op = CSGInstructionOp::SPHERE, .stream_index = 0},
        // {.csg_op = CSGInstructionOp::BINARY_OP_UNION, .stream_index = 0},
    };

    CSGInstructionBox boxes[2] = {
        {.bounds = {10, 5, 20}, .rigid_transform = 0},
        {.bounds = {5, 5, 5}, .rigid_transform = 1},
    };

    CSGInstructionSphere spheres[2] = {
        {
            .radius = 0.5,
            .rigid_transform = 0,
        },
        {
            .radius = 3,
            .rigid_transform = 1,
        }};

    CSGRigidTransform transforms[2] = {
        {.position = {0, 0, 0}, .uniform_scale = 10, .rotation = {0, 0, 0, 1}},
        {.position = {0, 0, 0}, .uniform_scale = 2, .rotation = {0, 0, 0, 1}},
    };

    CSGInstructionExtrudePost extrude[1] = {
        {.h = 5}};

    CSGMaterialComponent material_components[3] = {
        {3, 0.8},
        {1, 0.1},
        {2, 0.1}};

    csg_instructions.resize(ARRAY_LENGTH(instructions));
    csg_transforms.resize(ARRAY_LENGTH(transforms));
    csg_material.resize(ARRAY_LENGTH(material_components));
    csg_instructions_box.resize(ARRAY_LENGTH(instructions));
    csg_instructions_sphere.resize(ARRAY_LENGTH(instructions));
    csg_instructions_extrude_post.resize(ARRAY_LENGTH(extrude));

    memcpy(&csg_transforms[0], transforms, sizeof(transforms));
    memcpy(&csg_instructions[0], instructions, sizeof(instructions));
    memcpy(&csg_instructions_box[0], boxes, sizeof(boxes));
    memcpy(&csg_instructions_sphere[0], spheres, sizeof(spheres));
    memcpy(&csg_material[0], material_components, sizeof(material_components));
    memcpy(&csg_instructions_extrude_post[0], extrude, sizeof(extrude));

    simulation.csg_invocations = new CSGInvocation[1];
    simulation.csg_invocation_count = 1;
    simulation.csg_invocations[0].transform = CSGRigidTransform::identity();
    simulation.csg_invocations[0].transform.position = glm::vec3(simulation.width, simulation.height, simulation.depth) * 0.5f;

    simulation.UpdateCSGProgram(
        csg_transforms,
        csg_instructions,
        csg_instructions_box,
        csg_instructions_sphere,
        this->csg_instructions_extrude_post,
        csg_material,
        false);

    simulation.window = window;

    std::int32_t env_map_width;
    std::int32_t env_map_height;
    std::int32_t env_map_channels;
    std::uint8_t *data = stbi_load("../Assets/futuristic_env.jpg", &env_map_width, &env_map_height, &env_map_channels, 0);

    assert(data);
    assert(env_map_width);

    glCreateTextures(GL_TEXTURE_2D, 1, &this->environment_map_texture);
    glTextureStorage2D(this->environment_map_texture, 1, GL_RGB8, env_map_width, env_map_height);
    glTextureSubImage2D(this->environment_map_texture, 0, 0, 0, env_map_width, env_map_height, GL_RGB, GL_UNSIGNED_BYTE, data);

    ShaderSource rendererShaders[2]{
        {GL_VERTEX_SHADER, envMapVertexBinary, sizeof(envMapVertexBinary)},
        {GL_FRAGMENT_SHADER, envMapFragmentBinary, sizeof(envMapFragmentBinary)}};

    this->environment_map_shader_program = LoadProgram(rendererShaders, 2);

    assert(this->environment_map_shader_program);

    this->simulation.point_lights.push_back(PointLight{
        .position = glm::vec3(128, 128, 64),
        .radiance = 100.0f,
        .colour = glm::packUnorm4x8({0.5f, 0.3f, 0.3f, 1.0f}),
    });
}

void Program::Shutdown()
{
    simulation.Destroy();

    if (config.devMode)
    {
        ImGui_ImplOpenGL3_Shutdown();
        ImGui_ImplGlfw_Shutdown();

        ImGui::DestroyContext();
    }

    glfwDestroyWindow(window);
    glfwTerminate();
}

void Program::OnImGuiRender()
{
    ImGui::ShowMetricsWindow();

    if (ImGui::Begin("Settings"))
    {
        float fov_degrees = glm::degrees(camera.fov);

        ImGui::DragFloat("Fov", &fov_degrees);

        camera.fov = glm::radians(fov_degrees);

        ImGui::Checkbox("Orthographic", &camera.is_orthographic);

        ImGui::Checkbox("Wireframe", &renderSettings.wireframe);
        ImGui::Checkbox("Gamma Correction", &renderSettings.gammaCorrect);

        ImGui::End();
    }

    ImGui::ShowDemoWindow();

    {
        ImGuizmo::BeginFrame();

        ImGuiIO &io = ImGui::GetIO();
        ImGuizmo::SetRect(0, 0, io.DisplaySize.x, io.DisplaySize.y);

        CSGRigidTransform *transform_ptr = &simulation.csg_invocations[0].transform;
        bool can_nonuniformly_scale = false;

        if (this->selected_tree != nullptr)
        {
            transform_ptr = &this->selected_tree->transform;

            if (this->selected_tree->sdf_type == CSGTreeType::box)
            {
                can_nonuniformly_scale = true;
            }
        }

        if (this->selected_tree != nullptr)
        {

            CSGRigidTransform &transform = *transform_ptr;

            glm::mat4 matrix = glm::identity<glm::mat4>();

            ImGuizmo::Enable(!enableSimulation);

            matrix = glm::scale(glm::vec3(transform.uniform_scale));
            matrix = glm::mat4_cast(glm::normalize(glm::quat(-transform.rotation.w, transform.rotation.x, transform.rotation.y, transform.rotation.z))) * matrix;

            glm::vec3 temp_translation = transform.position;

            if (this->selected_tree != nullptr)
            {
                temp_translation = transform.position + glm::vec3(this->simulation.width / 2.0f, this->simulation.height / 2.0f, this->simulation.depth / 2.0f);
            }
            matrix = glm::translate(temp_translation) * matrix;

            float snap[3] = {1, 1, 1};

            ImGuizmo::OPERATION operation = ImGuizmo::OPERATION::TRANSLATE | ImGuizmo::OPERATION::ROTATE | ImGuizmo::OPERATION::SCALE_XU;

            glm::vec3 local_bounds[2] = {
                {-100, -100, -100}, {100, 100, 100}};

            if (can_nonuniformly_scale)
            {
                operation = operation | ImGuizmo::OPERATION::BOUNDS;
                // local_bounds = &this->selected_tree->data.box.bounds.x;
                local_bounds[0] = -this->selected_tree->data.box.bounds / 2.0f;
                local_bounds[1] = this->selected_tree->data.box.bounds / 2.0f;
            }

            if (ImGuizmo::Manipulate(
                    (float *)&camera.view,
                    (float *)&camera.projection,
                    operation,
                    ImGuizmo::MODE::LOCAL,
                    (float *)&matrix),
                nullptr,
                snap,
                &local_bounds[0].x,
                snap)
            {
            }

            auto quat = glm::normalize(glm::quat_cast(matrix));
            auto translation = glm::vec3{std::floor(matrix[3][0]), std::floor(matrix[3][1]), std::floor(matrix[3][2])};
            auto scale = glm::vec3(matrix[1][1]);
            auto skew = glm::vec3(0);
            auto persp = glm::vec4(0);

            glm::decompose(matrix, scale, quat, translation, skew, persp);

            transform.position = glm::floor(translation);
            if (this->selected_tree != nullptr)
            {
                transform.position = glm::floor(translation) - glm::vec3(this->simulation.width / 2.0f, this->simulation.height / 2.0f, this->simulation.depth / 2.0f);
            }
            transform.rotation = {quat.x, quat.y, quat.z, -quat.w};
            transform.uniform_scale = scale[0];

            if (can_nonuniformly_scale)
            {
            }
        }

        {
            glm::mat4 identity = glm::identity<glm::mat4>();
            identity = glm::translate(glm::vec3{(float)this->simulation.width / 2.0f, (float)this->simulation.height / 2.0f, (float)this->simulation.depth / 2.0f});
            ImGui::GetWindowDrawList()->AddCallback(imGuiEnableDepthTestingCallback, nullptr);

            // ImGuizmo::DrawGrid((float *)&camera.view, (float *)&camera.projection, (float *)&identity, 64.0f);

            ImGui::GetWindowDrawList()->AddCallback(imguiDisableDepthTestingCallback, nullptr);

            ImGuizmo::ViewManipulate((float *)&camera.view, 100, ImVec2(io.DisplaySize.x - 128, 128), ImVec2(128, 128), 0x10101010);
        }
    }

    if (ImGui::Begin("CSG Editor"))
    {
        if (this->selected_tree != nullptr)
        {
            ImGui::Text("Transform");
            ImGui::Separator();

            ImGui::DragFloat3("Translation", &this->selected_tree->transform.position.x);
            ImGui::DragFloat("Scale", &this->selected_tree->transform.uniform_scale);
            ImGui::DragFloat4("Rotation", &this->selected_tree->transform.rotation.x);

            ImGui::Separator();

            const char *child_op_names[] = {
                "IDENTITY",
                "BOX",
                "SPHERE",
                "PLANE",
                "TRIANGLE",
                "CYLYNDER",
                "CONE",
                "TORUS",

                "BINARY_OP_UNION",
                "BINARY_OP_INTERSECTION",
                "BINARY_OP_DIFFERENCE",
                "BINARY_OP_XOR",
                "BINARY_OP_SMOOTH_UNION",
                "BINARY_OP_SMOOTH_INTERSECTION",
                "BINARY_OP_SMOOTH_DIFFERENCE",
                "UNARY_OP_REVOLVE",
                "UNARY_OP_ELONGATE",
                "UNARY_OP_EXTRUDE_PRE",
                "UNARY_OP_EXTRUDE_POST",
                "POP_DISTANCE",
                "POP_POSITION",
            };

            ImGui::Combo("Child Algebraic Operation", (int *)&this->selected_tree->child_op, child_op_names, ARRAY_LENGTH(child_op_names));

            ImGui::Combo("Unary Operation", (int *)&this->selected_tree->unary_op, child_op_names, ARRAY_LENGTH(child_op_names));

            switch (this->selected_tree->unary_op)
            {
            case CSGInstructionOp::UNARY_OP_EXTRUDE_PRE:
            {
                ImGui::DragFloat("Height", &this->selected_tree->unary_op_data.extrude.h);
                break;
            }
            }

            ImGui::Separator();
            const char *materialNames[]{
                "Sand",
                "Stone",
                "Water",
                "Copper",
                "Glass"};
            int material = this->selected_tree->material - 1;
            ImGui::Combo("Material", &material, materialNames, ARRAY_LENGTH(materialNames));
            this->selected_tree->material = (std::uint16_t)material + 1;

            switch (this->selected_tree->sdf_type)
            {
            case CSGTreeType::box:
                ImGui::Text("Box");
                ImGui::Separator();
                ImGui::DragFloat3("Bounds", &this->selected_tree->data.box.bounds.x);
                break;
            case CSGTreeType::sphere:
                ImGui::Text("Sphere");
                ImGui::Separator();
                ImGui::DragFloat("Radius", &this->selected_tree->data.sphere.radius);
                break;
            }
        }

        if (ImGui::Button("Add Node"))
        {
            ImGui::OpenPopup("node_type_popup");
        }

        if (this->selected_tree != nullptr && ImGui::IsKeyDown(GLFW_KEY_DELETE))
        {
            if (this->selected_tree_parent == nullptr)
            {
                this->csg_tree_root_nodes.erase(static_cast<std::vector<CSGTree>::iterator>(this->selected_tree));
            }
            else
            {
                this->selected_tree_parent->children.erase(static_cast<std::vector<CSGTree>::iterator>(this->selected_tree));
            }

            this->selected_tree = nullptr;
            this->selected_tree_parent = nullptr;
        }

        if (this->selected_tree != nullptr && ImGui::IsKeyDown(GLFW_KEY_LEFT_CONTROL) && ImGui::IsKeyPressed(GLFW_KEY_C))
        {
            std::printf("Copied node %p\n", this->selected_tree);

            this->copied_tree.intiializeCopy(*this->selected_tree);
            this->copy_selected_tree = true;
        }

        if (this->copy_selected_tree && ImGui::IsKeyDown(GLFW_KEY_LEFT_CONTROL) && ImGui::IsKeyPressed(GLFW_KEY_V))
        {
            this->csg_tree_root_nodes.push_back(this->copied_tree);

            this->selected_tree = &this->csg_tree_root_nodes.back();
        }

        if (ImGui::BeginPopup("node_type_popup"))
        {
            if (ImGui::Selectable("Box"))
            {
                CSGTree &current_node = this->csg_tree_root_nodes.emplace_back();
                current_node = {};
                current_node.sdf_type = CSGTreeType::box;
                current_node.data.box.bounds = glm::vec3(10);
                current_node.transform = CSGRigidTransform::identity();
                current_node.material = 1;
                memcpy(current_node.name, "Box", 3 + 1);

                this->selected_tree = &current_node;
                this->selected_tree_parent = nullptr;
            }

            if (ImGui::Selectable("Sphere"))
            {
                CSGTree &current_node = this->csg_tree_root_nodes.emplace_back();
                current_node = {};
                current_node.sdf_type = CSGTreeType::sphere;
                current_node.data = {
                    .sphere = {.radius = 10},
                };
                current_node.material = 1;
                current_node.transform = CSGRigidTransform::identity();
                memcpy(current_node.name, "Sphere", 6 + 1);

                this->selected_tree = &current_node;
                this->selected_tree_parent = nullptr;
            }

            ImGui::EndPopup();
        }

        for (CSGTree &node : this->csg_tree_root_nodes)
        {
            this->OnImGuiCSGTreeNode(&node, nullptr);
        }

        ImGui::Separator();

        if (ImGui::Button("Add Light"))
        {
            auto &light = this->simulation.point_lights.emplace_back();
            light.radiance = 10.0f;
            light.colour = 0xffffffff;
            light.position = glm::vec3(0);
        }

        std::uint32_t i = 0;

        for (auto &light : this->simulation.point_lights)
        {
            ImGui::Separator();
            ImGui::PushID(i);

            ImGui::DragFloat3("Position", &light.position.x);
            ImGui::DragFloat("Radiance", &light.radiance);

            glm::vec3 colour = glm::vec3(glm::unpackUnorm4x8(light.colour));

            ImGui::ColorEdit3("Colour", &colour.x);

            light.colour = glm::packUnorm4x8(glm::vec4(colour, 1));
            ImGui::PopID();

            i += 1;
        }

        ImGui::End();
    }

    for (auto command : this->csg_reparent_commands)
    {
        command.destination->children.push_back(*command.source);
        if (command.source_parent != nullptr)
        {
            command.source_parent->children.erase(static_cast<std::vector<CSGTree>::iterator>(command.source));
        }
        else
        {
            this->csg_tree_root_nodes.erase(static_cast<std::vector<CSGTree>::iterator>(command.source));
        }
    }

    this->csg_reparent_commands.clear();

    this->csg_instructions.clear();
    this->csg_transforms.clear();
    this->csg_instructions_box.clear();
    this->csg_instructions_sphere.clear();
    this->csg_instructions_extrude_post.clear();

    {
        std::size_t i = 0;

        for (auto node : this->csg_tree_root_nodes)
        {
            this->CompileCSGTreeToProgram(node, nullptr);

            if (i != 0)
            {
                this->csg_instructions.push_back({.csg_op = CSGInstructionOp::BINARY_OP_UNION});
            }

            i += 1;
        }
    }

    std::printf("Compiled CSG Program: \n");
    for (const auto instruction : this->csg_instructions)
    {
        std::printf("Inst: op: %u, stream_idx: %u\n", (std::uint32_t)instruction.csg_op, instruction.stream_index);
    }

    if (ImGui::Begin("Voxels"))
    {
        static int pos[3]{};
        static int size[3]{1, 1, 1};

        static int radius = 1;
        static int diameter = 2;
        static int radiusSqr = 1;

        const char *materialNames[]{
            "Sand",
            "Stone",
            "Water",
            "Copper",
            "Glass"};

        static std::int32_t selected = 1;
        static std::int32_t placementTemperature = CelsiusToKelvin(20);

        ImGui::DragInt("Placement Temperature", &placementTemperature);

        if (ImGui::CollapsingHeader("Particles"))
        {
            ImGui::Indent();

            for (std::uint8_t i = 0; i < ARRAY_LENGTH(materialNames); i++)
            {
                const auto color = voxel_materials_visual[i + 1].albedo;

                ImGui::PushID("Color");

                ImGui::ColorButton(materialNames[i], ImColor(color));

                ImGui::PopID();

                ImGui::SameLine();

                if (ImGui::Selectable(materialNames[i], selected == i + 1))
                {
                    selected = i + 1;
                }
            }

            ImGui::Unindent();

            ImGui::DragFloat("Melting Point", &materials[selected].melting_point);
            ImGui::DragFloat("Boiling Point", &materials[selected].boiling_point);
            ImGui::DragFloat("Reflectivity", &voxel_materials_visual[selected].reflectivity);

            std::uint32_t *roughness_metalness_packed = &voxel_materials_visual[selected].roughness_metalness;
            glm::vec4 roughness_metalness = glm::unpackUnorm4x8(*roughness_metalness_packed);
            glm::vec4 roughness = roughness_metalness;
            roughness.g = roughness_metalness.x;
            roughness.b = roughness_metalness.x;
            glm::vec4 metalness = roughness_metalness;
            metalness.r = metalness.g;
            metalness.g = metalness.g;
            metalness.b = metalness.g;

            ImGui::ColorEdit3("Roughness", &roughness.x);
            ImGui::ColorEdit3("Metalness", &metalness.x);
            roughness_metalness.r = roughness.x;
            roughness_metalness.g = metalness.x;

            *roughness_metalness_packed = glm::packUnorm4x8(roughness_metalness);

            glm::vec4 color = glm::unpackUnorm4x8(voxel_materials_visual[selected].albedo);
            ImGui::DragFloat("Transmissability", &color.a);
            voxel_materials_visual[selected].albedo = glm::packUnorm4x8(color);

            ImGui::Separator();
        }

        for (int i = 0; i < csg_material.size(); i++)
        {
            const auto material_comp = &csg_material[i];

            ImGui::PushID(i);

            ImGui::DragFloat("Material", &material_comp->density, 0.05, 0, 1);

            ImGui::PopID();
        }

        ImGui::Checkbox("Enable Simulation", &enableSimulation);

        ImGui::End();
    }
}

void Program::CompileCSGTreeToProgram(CSGTree &node, CSGTree *parent)
{
    if (node.unary_op != CSGInstructionOp::IDENTITY)
    {
        this->csg_instructions.push_back({.csg_op = node.unary_op});
    }

    const auto transform_index = this->csg_transforms.size();

    CSGRigidTransform parent_transform = CSGRigidTransform::identity();

    if (parent != nullptr)
    {
        parent_transform = parent->transform;
    }

    const auto resolved_transform = transformCompose(parent_transform, node.transform);

    this->csg_transforms.push_back(resolved_transform);

    std::uint32_t identity_transform_index = 0xffffffff;

    if (node.unary_op == CSGInstructionOp::UNARY_OP_EXTRUDE_PRE)
    {
        identity_transform_index = this->csg_transforms.size();
        this->csg_transforms.push_back(CSGRigidTransform::identity());

        this->csg_instructions.push_back({.csg_op = CSGInstructionOp::TRANSFORM, .stream_index = (std::uint32_t)transform_index});
        this->csg_instructions.push_back({.csg_op = node.unary_op});
    }

    CSGInstruction &instruction = this->csg_instructions.emplace_back();

    switch (node.sdf_type)
    {
    case CSGTreeType::box:
    {
        const auto stream_index = this->csg_instructions_box.size();
        CSGInstructionBox &box_data = this->csg_instructions_box.emplace_back();

        box_data.bounds = node.data.box.bounds;
        box_data.rigid_transform = transform_index;
        box_data.material = node.material;

        if (identity_transform_index != 0xffffffff)
        {
            box_data.rigid_transform = identity_transform_index;
        }

        instruction.csg_op = CSGInstructionOp::BOX;
        instruction.stream_index = stream_index;

        break;
    }
    case CSGTreeType::sphere:
    {
        const auto stream_index = this->csg_instructions_sphere.size();
        CSGInstructionSphere &sphere_data = this->csg_instructions_sphere.emplace_back();

        sphere_data.radius = node.data.sphere.radius;
        sphere_data.rigid_transform = transform_index;
        sphere_data.material = node.material;

        if (identity_transform_index != 0xffffffff)
        {
            sphere_data.rigid_transform = identity_transform_index;
        }

        instruction.csg_op = CSGInstructionOp::SPHERE;
        instruction.stream_index = stream_index;

        break;
    }
    }

    if (node.unary_op == CSGInstructionOp::UNARY_OP_EXTRUDE_PRE)
    {
        const auto stream_idx = this->csg_instructions_extrude_post.size();

        auto &extrude_data = this->csg_instructions_extrude_post.emplace_back();

        extrude_data.h = node.unary_op_data.extrude.h;

        this->csg_instructions.push_back({.csg_op = CSGInstructionOp::TRANSFORM_POST, .stream_index = (std::uint32_t)transform_index});

        this->csg_instructions.push_back({.csg_op = CSGInstructionOp::UNARY_OP_EXTRUDE_POST, .stream_index = (std::uint32_t)stream_idx});
    }

    std::size_t i = 0;

    for (CSGTree &child : node.children)
    {
        CompileCSGTreeToProgram(child, &node);

        if (i != 0)
        {
            this->csg_instructions.push_back({.csg_op = node.child_op});
        }

        i += 1;
    }

    if (node.children.size() != 0)
    {
        this->csg_instructions.push_back({.csg_op = CSGInstructionOp::BINARY_OP_UNION});
    }
}

void Program::OnImGuiCSGTreeNode(CSGTree *tree, CSGTree *parent)
{
    ImGuiTreeNodeFlags base_flags = ImGuiTreeNodeFlags_OpenOnArrow | ImGuiTreeNodeFlags_OpenOnDoubleClick | ImGuiTreeNodeFlags_SpanAvailWidth;

    if (tree == this->selected_tree)
    {
        base_flags |= ImGuiTreeNodeFlags_Selected;
    }

    ImGui::PushID(tree);

    if (ImGui::TreeNodeEx(tree->name, base_flags))
    {
        if (ImGui::IsItemClicked())
        {
            this->selected_tree = tree;
        }

        if (ImGui::BeginDragDropSource())
        {
            CSGTreeReparentCommand command;

            command.source = tree;
            command.source_parent = parent;

            ImGui::SetDragDropPayload("node", &command, sizeof(CSGTreeReparentCommand));
            ImGui::EndDragDropSource();
        }

        if (ImGui::BeginDragDropTarget())
        {
            const auto payload = ImGui::AcceptDragDropPayload("node");

            if (payload != nullptr)
            {
                auto payload_tree_command = *(CSGTreeReparentCommand *)payload->Data;

                payload_tree_command.destination = tree;

                this->csg_reparent_commands.push_back(payload_tree_command);
            }

            ImGui::EndDragDropTarget();
        }

        for (CSGTree &child : tree->children)
        {
            this->OnImGuiCSGTreeNode(&child, tree);
        }

        ImGui::TreePop();
    }

    ImGui::PopID();
}

void Program::Render()
{
    simulation.UpdateCSGProgram(
        csg_transforms,
        csg_instructions,
        csg_instructions_box,
        csg_instructions_sphere,
        csg_instructions_extrude_post,
        csg_material,
        true);

    // camera controls
    {
        double cursor_pos_x, cursor_pos_y;
        glfwGetCursorPos(window, &cursor_pos_x, &cursor_pos_y);

        const auto cursor_delta_x = cursor_pos_x - last_mouse_x;
        const auto cursor_delta_y = cursor_pos_y - last_mouse_y;

        const auto norm_delta_x = ((float)cursor_delta_x / (float)displayWidth);
        const auto norm_delta_y = ((float)cursor_delta_y / (float)displayHeight);

        const auto angle_x = norm_delta_x * 2 * glm::pi<float>();
        const auto angle_y = norm_delta_y * 2 * glm::pi<float>();

        const auto rotation_x = glm::mat3(glm::rotate(-angle_x, glm::vec3{0, 1, 0}));
        const auto rotation_y = glm::mat3(glm::rotate(angle_y, glm::vec3{0, 0, 1}));

        const auto rotation = rotation_x * rotation_y;

        const auto new_eye = rotation * (camera.eye - camera.target) + camera.target;

        if (glfwGetMouseButton(window, GLFW_MOUSE_BUTTON_1) && !ImGui::IsAnyItemActive() && !ImGuizmo::IsUsing())
        {
            camera.eye = new_eye;
        }

        camera.eye += glm::clamp<float>(this->mouse_scroll, -1, 1) * (camera.eye - camera.target);

        this->mouse_scroll = 0;

        if (glfwGetMouseButton(window, GLFW_MOUSE_BUTTON_2) && !ImGui::IsAnyItemActive() && !ImGuizmo::IsUsingViewManipulate())
        {
            const auto lateral_vector = glm::cross((camera.target - camera.eye), glm::vec3{0, 1, 0});

            camera.eye += lateral_vector * norm_delta_x;
            camera.target += lateral_vector * norm_delta_x;

            camera.eye += glm::vec3{0, 5, 0} * norm_delta_y;
            camera.target += glm::vec3{0, 5, 0} * norm_delta_y;
        }

        last_mouse_x = cursor_pos_x;
        last_mouse_y = cursor_pos_y;
    }

    camera.projection = glm::perspective(camera.fov, (float)displayWidth / (float)displayHeight, camera.near, camera.far);

    if (camera.is_orthographic)
    {
        camera.projection = glm::ortho(-(float)this->displayWidth / 2.0f, (float)this->displayWidth / 2.0f, (float)this->displayHeight / 2.0f, -(float)this->displayHeight / 2.0f, 0.1f, 100.0f);
        // camera.projection = glm::ortho(0.0f, (float)this->displayWidth, (float)this->displayHeight, 0.0f, 0.0f, 1000.0f);
    }
    camera.view = glm::lookAt(camera.eye, camera.target, glm::vec3{0.0f, 1.0f, 0.0f});

    simulation.model = simulationTransform;
    simulation.view = camera.view;
    simulation.projection = camera.projection;

    if (renderSettings.wireframe)
    {
        glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
    }
    else
    {
        glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
    }

    if (renderSettings.gammaCorrect)
    {
        glEnable(GL_FRAMEBUFFER_SRGB);
    }

    simulation.Update(enableSimulation);

    glUseProgram(this->environment_map_shader_program);
    glBindBufferBase(GL_UNIFORM_BUFFER, 0, this->simulation.uniformBuffer);
    glBindTexture(GL_TEXTURE_2D, this->environment_map_texture);
    glBindTextureUnit(2, this->environment_map_texture);

    glBindVertexArray(simulation.vertexArray);
    glDisable(GL_CULL_FACE);

    glDrawArrays(GL_TRIANGLES, 0, 36);

    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LESS);
    glDepthMask(GL_TRUE);

    glBindTextureUnit(22, this->environment_map_texture);

    simulation.Render();

    if (config.devMode)
    {
        ImGui_ImplOpenGL3_NewFrame();
        ImGui_ImplGlfw_NewFrame();

        ImGui::NewFrame();

        OnImGuiRender();

        ImGui::Render();

        glDisable(GL_FRAMEBUFFER_SRGB);

        ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
    }
}

void Program::Run()
{
    while (!glfwWindowShouldClose(window))
    {
        const auto time_begin = glfwGetTime();

        glfwPollEvents();
        glfwGetFramebufferSize(window, &displayWidth, &displayHeight);

        glClearNamedFramebufferfv(0, GL_COLOR, 0, &renderSettings.clearColor.x);
        glClearNamedFramebufferfi(0, GL_DEPTH_STENCIL, 0, 1.0f, 1);
        glViewport(0, 0, displayWidth, displayHeight);

        Render();

        glfwSwapBuffers(window);
    }
}
