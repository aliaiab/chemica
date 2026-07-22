pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zglfw = b.dependency("zglfw", .{
        .target = target,
        .optimize = optimize,
    });

    const cimgui_dep = b.dependency("cimgui_zig", .{
        .target = target,
        .optimize = optimize,
        .platforms = &[_]cimgui.Platform{.GLFW},
        .renderers = &[_]cimgui.Renderer{.OpenGL3},
        // .docking = true, // Default value: false
    });

    const main_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("Source/main.zig"),
    });

    main_module.linkLibrary(zglfw.artifact("glfw"));

    main_module.linkLibrary(cimgui_dep.artifact("cimgui"));

    main_module.addCSourceFiles(.{
        .files = &.{
            "Main.cpp",
            "ImGuizmo.cpp",
            "Program.cpp",
            "Simulation.cpp",
        },
        .root = b.path("Source/"),
    });
    main_module.addCSourceFiles(.{
        .files = &.{
            "glad/src/glad.c",
            "json-parser/json.c",
        },
        .root = b.path("External/"),
    });
    main_module.addIncludePath(b.path("External/glad/include"));
    main_module.addIncludePath(b.path("External/glfw"));
    main_module.addIncludePath(b.path("External/glm"));
    main_module.addIncludePath(b.path("External/imgui"));
    main_module.addIncludePath(b.path("External/json-parser"));
    main_module.addIncludePath(b.path("External/stb_image"));

    const compile_thermal_compute = b.addSystemCommand(
        &.{
            "glslangValidator",
            "-G",
            "-S",
            "comp",
            "--vn",
            "thermalComputeBinary",
            "Source/Shaders/ThermalCompute.glsl",
            "-o",
            "Source/Shaders/Include/ThermalCompute.h",
        },
    );
    const compile_renderer_fragment = b.addSystemCommand(
        &.{
            "glslangValidator",
            "-G",
            "-S",
            "frag",
            "--vn",
            "rendererFragmentBinary",
        },
    );
    compile_renderer_fragment.addFileArg(b.path("Source/Shaders/RendererFragment.glsl"));
    compile_renderer_fragment.addFileInput(b.path("Source/Shaders/RendererFragment.glsl"));
    compile_renderer_fragment.addArgs(&.{
        "-o",
        "Source/Shaders/Include/RendererFragment.h",
    });

    main_module.strip = optimize != .Debug;

    const exe = b.addExecutable(.{
        .name = "chemica",
        .root_module = main_module,
    });

    exe.step.dependOn(&compile_thermal_compute.step);
    exe.step.dependOn(&compile_renderer_fragment.step);

    exe.is_linking_libcpp = true;

    b.installArtifact(exe);
}

const cimgui = @import("cimgui_zig");
const std = @import("std");
