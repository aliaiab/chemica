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

void Program::Initialize()
{
    glfwInit();

    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 6);
    glfwWindowHint(GLFW_OPENGL_DEBUG_CONTEXT, true);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

    window = glfwCreateWindow(640, 480, "Chemica", nullptr, nullptr);

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

    for (int i = 0; i < ARRAY_LENGTH(materials); i++)
    {
        materials[i] = {};
        materials[i].melting_point = 100000;
    }

    materials[0].color = 0;
    materials[0].heat_conductivity = 0;

    materials[1].color = glm::packUnorm4x8({0.89f, 0.79f, 0.55f, 1.0f});
    materials[1].heat_conductivity = 0.5;

    materials[2].color = glm::packUnorm4x8({0.29f, 0.29f, 0.29f, 1.0f});
    materials[2].heat_conductivity = 1;
    materials[2].melting_point = 1000;

    materials[3].color = glm::packUnorm4x8({0.17f, 0.56f, 0.82f, 0.19f});
    materials[3].heat_conductivity = 0.9;

    // materials[4].color = glm::packUnorm4x8({ 0.72f, 0.45f, 0.2f, 1.0f });
    materials[4].color = 0xff1d2971;
    materials[4].heat_conductivity = 3;
    materials[4].melting_point = 3000;

    materials[5].color = glm::packUnorm4x8({0.9f, 0.5f, 0.5f, 0.5f});
    materials[5].heat_conductivity = 0.3;

    simulation.voxelMaterials = materials;
    simulation.voxelMaterialCount = ARRAY_LENGTH(materials);

    simulation.Create();

    camera.target = glm::vec3{simulation.width, simulation.height, simulation.depth} * 0.5f;

    if (config.devMode)
    {
        ImGui::CreateContext();

        ImGui_ImplGlfw_InitForOpenGL(window, true);
        ImGui_ImplOpenGL3_Init("#version 450");

        ImGuizmo::SetImGuiContext(ImGui::GetCurrentContext());
        ImGuizmo::Enable(true);
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
        {.csg_op = CSGInstructionOp::POP_POSITION, .stream_index = 0},
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

    CSGMaterialComponent material_components[3] = {
        {3, 0.8},
        {1, 0.1},
        {2, 0.1}};

    csg_instructions_count = ARRAY_LENGTH(instructions);
    csg_transforms_count = ARRAY_LENGTH(transforms);
    csg_material_comp_count = ARRAY_LENGTH(material_components);
    csg_transforms = new CSGRigidTransform[csg_transforms_count];
    csg_instructions = new CSGInstruction[csg_instructions_count];
    csg_instructions_box = new CSGInstructionBox[csg_instructions_count];
    csg_instructions_sphere = new CSGInstructionSphere[csg_instructions_count];
    csg_material = new CSGMaterialComponent[csg_material_comp_count];

    memset(csg_instructions_box, 0, csg_instructions_count * sizeof(CSGInstructionBox));
    memset(csg_instructions_sphere, 0, csg_instructions_count * sizeof(CSGInstructionSphere));
    memset(csg_material, 0, csg_material_comp_count * sizeof(CSGMaterialComponent));

    memcpy(csg_transforms, transforms, sizeof(transforms));
    memcpy(csg_instructions, instructions, sizeof(instructions));
    memcpy(csg_instructions_box, boxes, sizeof(boxes));
    memcpy(csg_instructions_sphere, spheres, sizeof(spheres));
    memcpy(csg_material, material_components, sizeof(material_components));

    simulation.csg_invocations = new CSGInvocation[1];
    simulation.csg_invocation_count = 1;
    simulation.csg_invocations[0].transform = CSGRigidTransform::identity();
    simulation.csg_invocations[0].transform.position = glm::vec3(simulation.width, simulation.height, simulation.depth) * 0.5f;

    simulation.UpdateCSGProgram(
        csg_transforms,
        csg_transforms_count,
        csg_instructions,
        csg_instructions_count,
        csg_instructions_box,
        1,
        csg_instructions_sphere,
        1,
        csg_material,
        csg_material_comp_count,
        false);

    simulation.window = window;
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
        ImGui::DragFloat3("Camera Position", glm::value_ptr(camera.eye));
        ImGui::DragFloat3("Camera Target", glm::value_ptr(camera.target));

        float fov_degrees = glm::degrees(camera.fov);

        ImGui::DragFloat("Fov", &fov_degrees);

        camera.fov = glm::radians(fov_degrees);
        ImGui::DragFloat("Zoom", &camera.zoom, 0.01f);
        ImGui::DragFloat("Near Plane", &camera.near, 0.1f);
        ImGui::DragFloat("Far Plane", &camera.far, 1.0f);

        ImGui::ColorEdit4("Clear Color", &renderSettings.clearColor.x);
        ImGui::Checkbox("Wireframe", &renderSettings.wireframe);
        ImGui::Checkbox("Gamma Correction", &renderSettings.gammaCorrect);

        ImGui::End();
    }

    {
        ImGuizmo::BeginFrame();

        ImGuiIO &io = ImGui::GetIO();
        ImGuizmo::SetRect(0, 0, io.DisplaySize.x, io.DisplaySize.y);

        CSGRigidTransform transform = simulation.csg_invocations[0].transform;

        glm::mat4 matrix = glm::identity<glm::mat4>();

        ImGuizmo::Enable(!enableSimulation);

        matrix = glm::scale(glm::vec3(transform.uniform_scale));
        matrix = glm::mat4_cast(glm::normalize(glm::quat(-transform.rotation.w, transform.rotation.x, transform.rotation.y, transform.rotation.z))) * matrix;
        matrix = glm::translate(transform.position) * matrix;

        float snap[3] = {1, 1, 1};

        if (ImGuizmo::Manipulate(
                (float *)&camera.view,
                (float *)&camera.projection,
                ImGuizmo::OPERATION::TRANSLATE | ImGuizmo::OPERATION::ROTATE | ImGuizmo::OPERATION::SCALE_XU,
                ImGuizmo::MODE::LOCAL,
                (float *)&matrix),
            nullptr,
            snap)
        {
        }

        auto quat = glm::normalize(glm::quat_cast(matrix));
        auto translation = glm::vec3{std::floor(matrix[3][0]), std::floor(matrix[3][1]), std::floor(matrix[3][2])};
        auto scale = glm::vec3(matrix[1][1]);
        auto skew = glm::vec3(0);
        auto persp = glm::vec4(0);

        glm::decompose(matrix, scale, quat, translation, skew, persp);

        simulation.csg_invocations[0].transform.position = glm::floor(translation);
        simulation.csg_invocations[0].transform.rotation = {quat.x, quat.y, quat.z, -quat.w};
        simulation.csg_invocations[0].transform.uniform_scale = scale[0];
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
                const auto color = materials[i + 1].color;

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
        }

        for (int i = 0; i < csg_material_comp_count; i++)
        {
            const auto material_comp = &csg_material[i];

            ImGui::PushID(i);

            ImGui::DragFloat("Material", &material_comp->density, 0.05, 0, 1);

            ImGui::PopID();
        }

        static auto continous = false;

        ImGui::Checkbox("Continous", &continous);

        static auto replace = true;

        ImGui::Checkbox("Replace", &replace);

        if (ImGui::Button("Reset"))
        {
            // TODO: implement reset on the gpu
        }

        ImGui::Checkbox("Enable Simulation", &enableSimulation);

        ImGui::End();
    }
}

void Program::Render()
{
    simulation.UpdateCSGProgram(
        csg_transforms,
        csg_transforms_count,
        csg_instructions,
        csg_instructions_count,
        csg_instructions_box,
        1,
        csg_instructions_sphere,
        1,
        csg_material,
        csg_material_comp_count,
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

        if (glfwGetMouseButton(window, GLFW_MOUSE_BUTTON_2) && !ImGui::IsAnyItemActive())
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

    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LESS);
    glDepthMask(GL_TRUE);

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