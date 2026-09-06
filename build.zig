pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const use_vulkan = b.option(bool, "use_vulkan", "Use the vulkan backend") orelse false;

    const zglfw = b.dependency("zglfw", .{
        .target = target,
        .optimize = optimize,
        .import_vulkan = true,
    });

    var cimgui_renderers: [1]cimgui.Renderer = undefined;

    if (target.result.os.tag == .macos) {
        cimgui_renderers[0] = .Metal;
    } else {
        if (use_vulkan) {
            //cimgui_renderers[0] = .Vulkan;
        }

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
        .extensions = &.{
            .EXT_mesh_shader,
        },
    });

    const freetype_dep = b.dependency("freetype", .{
        .target = target,
        .optimize = optimize,
    });

    const mist_dep = b.dependency("msdf_zig", .{
        .target = target,
        .optimize = optimize,
    });

    _ = freetype_dep; // autofix

    const cimgui_translate_c = b.addTranslateC(.{
        .root_source_file = b.path("src/cimgui.h"),
        .target = target,
        .optimize = optimize,
    });
    _ = cimgui_translate_c; // autofix

    const main_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
    });

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
    });

    root_module.addImport("zmath", zmath.module("root"));

    const zglfw_mod = zglfw.module("root");

    main_module.addImport("gl", gl_bindings);
    main_module.addImport("zglfw", zglfw_mod);
    main_module.addImport("zigimg", zigimg.module("zigimg"));
    main_module.addImport("lib", root_module);
    main_module.addImport("msdf-zig", mist_dep.module("msdf-zig"));
    main_module.linkSystemLibrary("vulkan", .{ .weak = true });

    // Get the (lazy) path to vk.xml:
    const registry = b.dependency("vulkan_headers", .{}).path("registry/vk.xml");
    // Get generator executable reference
    const vk_gen = b.dependency("vulkan", .{}).artifact("vulkan-zig-generator");
    // Set up a run step to generate the bindings
    const vk_generate_cmd = b.addRunArtifact(vk_gen);
    // Pass the registry to the generator
    vk_generate_cmd.addFileArg(registry);
    // Create a module from the generator's output...
    const vulkan_zig = b.addModule("vulkan-zig", .{
        .root_source_file = vk_generate_cmd.addOutputFileArg("vk.zig"),
    });
    // ... and pass it as a module to your executable's build command
    main_module.addImport("vulkan", vulkan_zig);
    main_module.link_libc = true;

    zglfw_mod.addImport("vulkan", vulkan_zig);

    if (target.result.os.tag == .macos) {
        main_module.addImport("objc", b.dependency("zig_objc", .{
            .target = target,
            .optimize = optimize,
        }).module("objc"));
    }

    const disable_nfd = b.option(bool, "disable_nfd", "Disables native file dialogs") orelse false;
    const use_llvm = b.option(bool, "use_llvm", "Enables llvm") orelse false;

    const exe_options = b.addOptions();
    exe_options.addOption(bool, "enable_nfd", !disable_nfd);
    exe_options.addOption(bool, "use_vulkan", use_vulkan);

    main_module.addImport("options", exe_options.createModule());

    if (!disable_nfd) {
        const nfd = b.dependency("nfd", .{ .target = target, .optimize = optimize });
        const nfd_mod = nfd.module("nfd");
        main_module.addImport("nfd", nfd_mod);
    }

    main_module.link_libc = true;

    const cimgui_lib = cimgui_dep.artifact("cimgui");
    const c_module = cimgui.createModule(b, cimgui_dep, cimgui_lib, b.path("src/cimgui.h"));
    c_module.linkLibrary(cimgui_lib);

    if (target.result.os.tag == .macos) {
        const metal_dep = b.dependency("metal_bindings", .{
            .target = target,
            .optimize = optimize,
        });

        main_module.addImport("metal", metal_dep.module("metal_bindings"));
    }

    main_module.addImport("cimgui", c_module);

    //main_module.linkLibrary(zglfw.artifact("glfw"));

    main_module.linkLibrary(cimgui_dep.artifact("cimgui"));

    main_module.addCSourceFiles(.{
        .files = &.{
            "ImGuizmo.cpp",
            "guizmo.cpp",
            "gpu/c.cpp",
            "stb_image.c",
            "imgui_style.cpp",
        },
        .root = b.path("src/"),
    });
    main_module.addIncludePath(glm_dep.path(""));

    main_module.strip = optimize != .debug;

    const exe = b.addExecutable(.{
        .name = "chemica",
        .root_module = main_module,
        .use_llvm = optimize != .debug or use_llvm,
    });

    exe.step.dependOn(&cimgui_lib.step);

    const test_mod = b.addTest(.{ .root_module = main_module });

    const test_step = b.step("test", "Test the program");

    test_step.dependOn(&test_mod.step);

    const exe_check = b.addExecutable(.{
        .name = "chemica",
        .root_module = main_module,
        .use_llvm = false,
    });

    const check_step = b.step("check", "Check if the executable compiles");

    check_step.dependOn(&exe_check.step);

    const glslang_zig = b.dependency("glslang_zig", .{
        .optimize = optimize,
        .target = target,
    });

    const glsl_compiler = b.addExecutable(.{
        .name = "glsl_compiler",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/build/glsl_compiler.zig"),
            .target = b.graph.host,
            .optimize = .debug,
        }),
    });

    glsl_compiler.root_module.addIncludePath(b.path(""));
    glsl_compiler.root_module.addImport("glslang", glslang_zig.module("glslang-zig"));
    glsl_compiler.root_module.addImport("glslang_c", glslang_zig.module("c_interface"));

    const shader_start_module = b.createModule(.{
        .root_source_file = b.path("src/shaders/start.zig"),
    });

    shader_start_module.addImport("lib", root_module);

    const renderer_shader_module = compileZigShader(b, shader_start_module, root_module, target, optimize, exe, .vertex, "src/shaders/renderer.zig");
    _ = compileZigShader(b, shader_start_module, root_module, target, optimize, exe, .fragment, "src/shaders/renderer.zig");
    _ = compileZigShader(b, shader_start_module, root_module, target, optimize, exe, .compute, "src/shaders/thermal_compute.zig");
    _ = compileZigShader(b, shader_start_module, root_module, target, optimize, exe, .compute, "src/shaders/fill_region.zig");
    _ = compileZigShader(b, shader_start_module, root_module, target, optimize, exe, .compute, "src/shaders/grain_simulation.zig");
    _ = compileZigShader(b, shader_start_module, root_module, target, optimize, exe, .compute, "src/shaders/generate_chunk_draws.zig");
    _ = compileZigShader(b, shader_start_module, root_module, target, optimize, exe, .vertex, "src/shaders/env_map_renderer.zig");
    _ = compileZigShader(b, shader_start_module, root_module, target, optimize, exe, .fragment, "src/shaders/env_map_renderer.zig");
    _ = compileZigShader(b, shader_start_module, root_module, target, optimize, exe, .vertex, "src/shaders/gizmo_renderer.zig");
    _ = compileZigShader(b, shader_start_module, root_module, target, optimize, exe, .fragment, "src/shaders/gizmo_renderer.zig");
    _ = compileZigShader(b, shader_start_module, root_module, target, optimize, exe, .vertex, "src/shaders/asym_renderer.zig");
    _ = compileZigShader(b, shader_start_module, root_module, target, optimize, exe, .fragment, "src/shaders/asym_renderer.zig");
    _ = compileZigShader(b, shader_start_module, root_module, target, optimize, exe, .fragment, "src/shaders/sdf_renderer.zig");
    _ = compileZigShader(b, shader_start_module, root_module, target, optimize, exe, .compute, "src/shaders/sdf_texture.zig");
    _ = compileZigShader(b, shader_start_module, root_module, target, optimize, exe, .fragment, "src/shaders/depth_prepass.zig");

    exe.root_module.addImport("renderer_shader", renderer_shader_module);

    exe.is_linking_libcpp = true;

    b.installArtifact(exe);
}

fn compileZigShader(
    b: *std.Build,
    start_module: *std.Build.Module,
    shader_lib_module: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    mode: std.builtin.OptimizeMode,
    exe_step: *std.Build.Step.Compile,
    shader_type: enum {
        vertex,
        fragment,
        compute,
    },
    source: []const u8,
) *std.Build.Module {
    const source_basename = std.fs.path.stem(source);

    const output_path = std.mem.concat(b.allocator, u8, &.{
        source_basename,
        "_",
        @tagName(shader_type),
        ".spv",
    }) catch @panic("");
    const options = b.addOptions();

    options.addOption(@TypeOf(shader_type), "shader_module_type", shader_type);

    const compile_zig_shader = b.addObject(.{
        .name = std.fs.path.stem(output_path),
        .root_module = b.createModule(.{
            .root_source_file = b.path(source),
            .optimize = mode,
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .spirv64,
                .cpu_model = .{ .explicit = &std.Target.spirv.cpu.generic },
                .cpu_features_add = std.Target.spirv.featureSet(&[_]std.Target.spirv.Feature{
                    .v1_4,
                    .image_query,
                }),
                .os_tag = .vulkan,
                .ofmt = .spirv,
            }),
            .imports = &.{
                .{ .name = "lib", .module = shader_lib_module },
                .{ .name = "shader_start", .module = start_module },
                .{ .name = "shader_options", .module = options.createModule() },
            },
        }),
        .use_llvm = false,
        .use_lld = false,
    });
    var compile_shader_step: *std.Build.Step = undefined;
    compile_shader_step = &compile_zig_shader.step;
    const output_file_path = compile_zig_shader.getEmittedBin();

    const val = b.addSystemCommand(&.{"spirv-val"});
    val.addFileArg(output_file_path);

    exe_step.root_module.addImport(output_path, b.createModule(.{
        .root_source_file = output_file_path,
    }));
    //exe_step.step.dependOn(&val.step);

    return b.createModule(.{
        .root_source_file = b.path(source),
        .optimize = mode,
        .target = target,
        .imports = &.{
            .{ .name = "lib", .module = shader_lib_module },
            .{ .name = "shader_start", .module = start_module },
            .{ .name = "shader_options", .module = options.createModule() },
        },
    });
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
