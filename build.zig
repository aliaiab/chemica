pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zglfw = b.dependency("zglfw", .{
        .target = target,
        .optimize = optimize,
        .import_vulkan = true,
    });

    const cimgui_dep = b.dependency("cimgui_zig", .{
        .target = target,
        .optimize = optimize,
        .platforms = &[_]cimgui.Platform{.GLFW},
        .docking = true,
    });

    const glm_dep = b.dependency("glm", .{});

    const zigimg = b.dependency("zigimg", .{});
    const zmath = b.dependency("zmath", .{});

    const mist_dep = b.dependency("msdf_zig", .{
        .target = target,
        .optimize = optimize,
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

    const zglfw_mod = zglfw.module("root");

    main_module.addImport("zmath", zmath.module("root"));
    main_module.addImport("zglfw", zglfw_mod);
    main_module.addImport("zigimg", zigimg.module("zigimg"));
    main_module.addImport("msdf-zig", mist_dep.module("msdf-zig"));

    main_module.link_libc = true;

    if (target.result.os.tag == .macos) {
        main_module.addImport("objc", b.dependency("zig_objc", .{
            .target = target,
            .optimize = optimize,
        }).module("objc"));
        main_module.linkFramework("Metal", .{});
        main_module.linkFramework("Foundation", .{});
    } else {
        main_module.addCSourceFiles(.{
            .files = &.{
                "gpu/c.cpp",
            },
            .root = b.path("src/"),
        });
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

        zglfw_mod.addImport("vulkan", vulkan_zig);
    }

    const disable_nfd = b.option(bool, "disable_nfd", "Disables native file dialogs") orelse false;
    const use_llvm = b.option(bool, "use_llvm", "Enables llvm") orelse false;

    const exe_options = b.addOptions();
    exe_options.addOption(bool, "enable_nfd", !disable_nfd);

    main_module.addImport("options", exe_options.createModule());

    if (!disable_nfd) {
        const nfd = b.dependency("nfd", .{ .target = target, .optimize = optimize });
        const nfd_mod = nfd.module("nfd");
        main_module.addImport("nfd", nfd_mod);
    }

    main_module.link_libc = true;

    const cimgui_lib = cimgui_dep.artifact("cimgui");
    addIncludePathsToTranslateC(cimgui_translate_c, cimgui_lib);
    const c_module = cimgui_translate_c.createModule();
    c_module.linkLibrary(cimgui_lib);

    main_module.addImport("cimgui", c_module);

    //main_module.linkLibrary(zglfw.artifact("glfw"));

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

    const exe_kernel_object_path = compileModuleKernels(b, optimize, exe, main_module, "src/main.zig");

    exe_options.addOptionPath("exe_kernel_object", exe_kernel_object_path);

    exe.is_linking_libcpp = true;

    b.installArtifact(exe);
}

///Compile the source as a zig kernel object and import import from root_module
///Returns a path to the generated kernel object
pub fn compileModuleKernels(
    b: *std.Build,
    mode: std.builtin.OptimizeMode,
    exe_step: *std.Build.Step.Compile,
    root_module: *std.Build.Module,
    source: []const u8,
) std.Build.LazyPath {
    const source_basename = std.fs.path.stem(source);

    const output_path = std.mem.concat(b.allocator, u8, &.{
        source_basename,
        "_pre_opt",
        ".spv",
    }) catch @panic("");
    const actual_output_path = std.mem.concat(b.allocator, u8, &.{
        source_basename,
        ".spv",
    }) catch @panic("");

    const compile_zig_shader = b.addObject(.{
        .name = std.fs.path.stem(output_path),
        .root_module = b.createModule(.{
            .root_source_file = b.path(source),
            .optimize = mode,
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .spirv64,
                .cpu_model = .{ .explicit = &std.Target.spirv.cpu.vulkan_v1_2 },
                .cpu_features_add = std.Target.spirv.featureSet(&[_]std.Target.spirv.Feature{
                    .v1_4,
                    .image_query,
                    .draw_parameters,
                    .sampled_image_array_non_uniform_indexing,
                    .storage_image_array_non_uniform_indexing,
                    .runtime_descriptor_array,
                    .variable_pointers_storage_buffer,
                    .variable_pointers,
                    .untyped_pointers_khr,
                    .SPV_KHR_untyped_pointers,
                    .SPV_EXT_physical_storage_buffer,
                    .SPV_EXT_descriptor_indexing,
                    .float64,
                }),
                .os_tag = .vulkan,
            }),
        }),
        .use_llvm = false,
        .use_lld = false,
    });

    for (root_module.import_table.keys(), root_module.import_table.values()) |key, value| {
        _ = key; // autofix
        const has_c = if (value.link_libc) |link_libc| link_libc else false;

        if (!has_c) {
            //compile_zig_shader.root_module.addImport(key, value);
        }
    }

    var compile_shader_step: *std.Build.Step = undefined;
    compile_shader_step = &compile_zig_shader.step;
    const output_file_path = compile_zig_shader.getEmittedBin();

    const val = b.addSystemCommand(&.{"spirv-val"});
    val.addFileArg(output_file_path);

    const opt = b.addSystemCommand(&.{
        "spirv-opt",
        "--target-env=vulkan1.3",
        "--skip-validation",
        "--inline-entry-points-exhaustive",
    });

    opt.addArtifactArg(compile_zig_shader);
    opt.addArg("-o");
    const output_lazy_path = opt.addOutputFileArg(actual_output_path);

    if (mode != .debug) {
        exe_step.root_module.addImport(actual_output_path, b.createModule(.{
            .root_source_file = output_lazy_path,
        }));
    }

    const copy_file = b.addInstallBinFile(output_lazy_path, actual_output_path);

    b.getInstallStep().dependOn(&copy_file.step);

    //exe_step.step.dependOn(&val.step);
    //
    return .{ .cwd_relative = std.fs.path.join(b.allocator, &.{ "zig-out/bin/", actual_output_path }) catch @panic("oom") };
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
