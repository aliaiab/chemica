pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zglfw = b.dependency("zglfw", .{
        .target = target,
        .optimize = optimize,
    });

    var cimgui_renderers: [1]cimgui.Renderer = undefined;

    if (target.result.os.tag == .macos) {
        cimgui_renderers[0] = .Metal;
    } else {
        cimgui_renderers[0] = .OpenGL3;
    }

    const cimgui_dep = b.dependency("cimgui_zig", .{
        .target = target,
        .optimize = optimize,
        .platforms = &[_]cimgui.Platform{.GLFW},
        .renderers = &cimgui_renderers,
        .docking = true,
    });

    const glm_dep = b.dependency("glm", .{});

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
        .root_source_file = b.path("src/cimgui.h"),
        .target = target,
        .optimize = optimize,
    });

    const main_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
    });
    main_module.addImport("gl", gl_bindings);
    main_module.addImport("zglfw", zglfw.module("root"));
    main_module.addImport("zigimg", zigimg.module("zigimg"));
    main_module.addImport("zmath", zmath.module("root"));

    if (target.result.os.tag == .macos) {
        main_module.addImport("objc", b.dependency("zig_objc", .{
            .target = target,
            .optimize = optimize,
        }).module("objc"));
    }

    if (false) {
        const nfd = b.dependency("nfd", .{ .target = target, .optimize = optimize });
        const nfd_mod = nfd.module("nfd");
        main_module.addImport("nfd", nfd_mod);
    }

    main_module.link_libc = true;

    const cimgui_lib = cimgui_dep.artifact("cimgui");
    addIncludePathsToTranslateC(cimgui_translate_c, cimgui_lib);
    const c_module = cimgui_translate_c.createModule();
    c_module.linkLibrary(cimgui_lib);

    if (target.result.os.tag == .macos) {
        const metal_dep = b.dependency("metal_bindings", .{
            .target = target,
            .optimize = optimize,
        });

        main_module.addImport("metal", metal_dep.module("metal_bindings"));
    }

    main_module.addImport("cimgui", c_module);

    main_module.linkLibrary(zglfw.artifact("glfw"));

    main_module.linkLibrary(cimgui_dep.artifact("cimgui"));

    main_module.addCSourceFiles(.{
        .files = &.{
            "ImGuizmo.cpp",
            "guizmo.cpp",
            "stb_image.c",
            "imgui_style.cpp",
        },
        .root = b.path("src/"),
    });
    main_module.addIncludePath(glm_dep.path(""));

    main_module.strip = optimize != .Debug;

    const exe = b.addExecutable(.{
        .name = "chemica",
        .root_module = main_module,
        .use_llvm = optimize != .Debug,
    });

    const glslang_zig = b.dependency("glslang_zig", .{
        .optimize = optimize,
        .target = target,
    });

    const glsl_compiler = b.addExecutable(.{
        .name = "glsl_compiler",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/build/glsl_compiler.zig"),
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });

    glsl_compiler.root_module.addIncludePath(b.path(""));
    glsl_compiler.root_module.addImport("glslang", glslang_zig.module("glslang-zig"));
    glsl_compiler.root_module.addImport("glslang_c", glslang_zig.module("c_interface"));

    const compile_zig_shader = b.addObject(.{
        .name = "renderer_vertex",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/shaders/renderer_vertex.zig"),
            .optimize = optimize,
            .target = b.resolveTargetQuery(.{
                .os_tag = std.Target.Os.Tag.vulkan,
                .cpu_model = .{ .explicit = &std.Target.spirv.cpu.generic },
                .cpu_features_add = std.Target.spirv.featureSet(&.{.v1_4}),
                .cpu_arch = .spirv64,
            }),
        }),
        .use_llvm = false,
        .use_lld = false,
    });
    if (false) {
        const source_stem = std.fs.path.stem("src/shaders/renderer_vertex.glsl");
        const source_basename = std.fs.path.basename(source_stem);

        const get_path_step = b.addSystemCommand(&.{
            "echo",
        });

        get_path_step.addFileArg(compile_zig_shader.getEmittedBin());
        const generated_file = get_path_step.captureStdOut(.{});

        const install_path = b.addInstallFile(generated_file, source_basename);

        exe.step.dependOn(&install_path.step);
    }

    compile_zig_shader.root_module.addImport("zmath", zmath.module("root"));

    exe.step.dependOn(&compile_zig_shader.step);

    _ = compileShader(b, glsl_compiler, target, optimize, exe, .compute, "src/shaders/thermal_compute.glsl");
    _ = compileShader(b, glsl_compiler, target, optimize, exe, .vertex, "src/shaders/renderer_vertex.glsl");
    _ = compileShader(b, glsl_compiler, target, optimize, exe, .fragment, "src/shaders/renderer_fragment.glsl");
    _ = compileShader(b, glsl_compiler, target, optimize, exe, .compute, "src/shaders/fill_region.glsl");
    _ = compileShader(b, glsl_compiler, target, optimize, exe, .compute, "src/shaders/grain_simulation.glsl");
    _ = compileShader(b, glsl_compiler, target, optimize, exe, .fragment, "src/shaders/env_map_fragment.glsl");
    _ = compileShader(b, glsl_compiler, target, optimize, exe, .vertex, "src/shaders/env_map_vertex.glsl");
    _ = compileShader(b, glsl_compiler, target, optimize, exe, .compute, "src/shaders/generate_chunk_draws.glsl");
    _ = compileShader(b, glsl_compiler, target, optimize, exe, .vertex, "src/shaders/gizmo_shader_vertex.glsl");
    _ = compileShader(b, glsl_compiler, target, optimize, exe, .fragment, "src/shaders/gizmo_shader_fragment.glsl");
    _ = compileShader(b, glsl_compiler, target, optimize, exe, .fragment, "src/shaders/depth_prepass_fragment.glsl");

    exe.is_linking_libcpp = true;

    b.installArtifact(exe);
}

fn compileShader(
    b: *std.Build,
    glsl_compiler: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    mode: std.builtin.OptimizeMode,
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
        source_basename,
        ".spv",
    }) catch @panic("");

    const type_string: []const u8 = switch (shader_type) {
        .vertex => "vert",
        .fragment => "frag",
        .compute => "comp",
    };

    const output_file = b.addWriteFile(output_path, &.{});
    const output_file_path = output_file.add(output_path, &.{});

    const compile_shader = b.addRunArtifact(glsl_compiler);

    compile_shader.addArg(@tagName(mode));
    compile_shader.addArg(@tagName(shader_type));
    compile_shader.addArg(source);
    compile_shader.addFileArg(output_file_path);

    //_ = compile_shader.addDepFileOutputArg("deps.d");

    if (false) {
        compile_shader = b.addSystemCommand(
            &.{
                "glslangValidator",
                "-G",
                "-g",
                "-S",
                type_string,
                source,
                "-o",
            },
        );

        compile_shader.addFileArg(output_file_path);
    }

    const get_path_step = b.addSystemCommand(&.{
        "echo",
    });

    get_path_step.addFileArg(output_file_path);
    const generated_file = get_path_step.captureStdOut(.{});

    const install_path = b.addInstallFile(generated_file, source_basename);

    compile_shader.step.addWatchInput(b.path(source)) catch @panic("oom");

    if (mode != .Debug) {
        exe_step.root_module.addImport(output_path, b.createModule(.{
            .root_source_file = output_file_path,
        }));
    }

    exe_step.step.dependOn(&install_path.step);

    if (target.result.os.tag == .macos) {
        const msl_output_path = std.mem.concat(b.allocator, u8, &.{
            source_basename,
            ".msl",
        }) catch @panic("");

        const msl_output_path_install = b.pathJoin(&.{ "zig-out/bin/", msl_output_path });

        const convert_to_msl = b.addSystemCommand(&.{
            "spirv-cross",
            output_path,
            "--msl",
            "--msl-version",
            "20200",
            "--output",
            msl_output_path_install,
        });

        convert_to_msl.step.addWatchInput(b.path(output_path)) catch @panic("");
        exe_step.step.dependOn(&convert_to_msl.step);
    }
    b.getInstallStep().dependOn(&compile_shader.step);
    b.getInstallStep().dependOn(&install_path.step);
    b.default_step.dependOn(&install_path.step);

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
