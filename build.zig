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

    const zigimg = b.dependency("zigimg", .{});
    const zmath = b.dependency("zmath", .{});

    // Choose the OpenGL API, version, profile and extensions you want to generate bindings for.
    const gl_bindings = @import("zigglgen").generateModule(b, .{
        .api = .gl,
        .version = .@"4.6",
        .profile = .core,
        .extensions = &.{},
    });

    const cimgui_translate_c = b.addTranslateC(.{
        .root_source_file = b.path("Source/cimgui.h"),
        .target = target,
        .optimize = optimize,
    });

    const main_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("Source/main.zig"),
    });
    main_module.addImport("gl", gl_bindings);
    main_module.addImport("zglfw", zglfw.module("root"));
    main_module.addImport("zigimg", zigimg.module("zigimg"));
    main_module.addImport("zmath", zmath.module("root"));

    const cimgui_lib = cimgui_dep.artifact("cimgui");
    addIncludePathsToTranslateC(cimgui_translate_c, cimgui_lib);
    const c_module = cimgui_translate_c.createModule();
    c_module.linkLibrary(cimgui_lib);

    main_module.addImport("cimgui", c_module);

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

    main_module.strip = optimize != .Debug;

    const exe = b.addExecutable(.{
        .name = "chemica",
        .root_module = main_module,
        .use_llvm = false,
    });

    _ = compileShader(b, exe, .compute, "Source/Shaders/ThermalCompute.glsl");
    _ = compileShader(b, exe, .vertex, "Source/Shaders/RendererVertex.glsl");
    _ = compileShader(b, exe, .fragment, "Source/Shaders/RendererFragment.glsl");
    _ = compileShader(b, exe, .compute, "Source/Shaders/FillRegion.glsl");
    _ = compileShader(b, exe, .compute, "Source/Shaders/GrainSimulation.glsl");
    _ = compileShader(b, exe, .fragment, "Source/Shaders/EnvMapFragment.glsl");
    _ = compileShader(b, exe, .vertex, "Source/Shaders/EnvMapVertex.glsl");

    exe.is_linking_libcpp = true;

    b.installArtifact(exe);
}

fn compileShader(
    b: *std.Build,
    exe_step: *std.Build.Step.Compile,
    shader_type: enum {
        vertex,
        fragment,
        compute,
    },
    source: []const u8,
) *std.Build.Step.Run {
    const source_basename = std.fs.path.stem(source);

    const output_path = std.mem.concat(b.allocator, u8, &.{
        "Source/Shaders/Include/",
        source_basename,
        ".spv",
    }) catch @panic("");

    const type_string: []const u8 = switch (shader_type) {
        .vertex => "vert",
        .fragment => "frag",
        .compute => "comp",
    };

    const compile_shader = b.addSystemCommand(
        &.{
            "glslangValidator",
            "-G",
            "-S",
            type_string,
            source,
            "-o",
            output_path,
        },
    );

    exe_step.step.dependOn(&compile_shader.step);

    return compile_shader;
}

fn addIncludePathsToTranslateC(translate_c: *std.Build.Step.TranslateC, lib: *std.Build.Step.Compile) void {
    for (lib.root_module.include_dirs.items) |*included| {
        switch (included.*) {
            .path => translate_c.addIncludePath(included.path),
            .config_header_step => translate_c.addConfigHeader(included.config_header_step),
            .path_system => translate_c.addSystemIncludePath(included.path_system),
            .other_step => addIncludePathsToTranslateC(translate_c, included.other_step),
            else => unreachable,
        }
    }
}

const cimgui = @import("cimgui_zig");
const std = @import("std");
