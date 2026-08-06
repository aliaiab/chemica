//!A replacement for google's shaderc. A frontend to khronos glslang for use in zig build.
//!As such, this frontend does not need to provide a human readable command line interface.

const glslang_c = @import("glslang_c");

extern fn glslang_default_resource() callconv(.c) *const glslang_c.glslang_resource_t;

const IncludeContext = struct {
    root_source_directory: []const u8,
    io: std.Io,
    environ_map: *std.process.Environ.Map,
    included_files: std.ArrayList([]const u8) = .empty,
};

fn glslIncludeLocalFunc(
    context: ?*anyopaque,
    header_name: [*c]const u8,
    includer_name: [*c]const u8,
    include_depth: usize,
) callconv(.c) [*c]glslang_c.glsl_include_result_t {
    _ = include_depth; // autofix
    const include_context: *IncludeContext = @ptrCast(@alignCast(context.?));

    std.debug.assert(header_name != null);

    const result = std.heap.c_allocator.create(glslang_c.glsl_include_result_t) catch @panic("oom");

    const includer_name_span = std.mem.span(@as([*:0]const u8, @ptrCast(includer_name)));
    const header_name_span = std.mem.span(@as([*:0]const u8, @ptrCast(header_name)));

    const includer_dir_relative = std.fs.path.dirname(includer_name_span) orelse "";

    const file_path = std.fs.path.join(std.heap.c_allocator, &.{
        include_context.root_source_directory,
        includer_dir_relative,
        header_name_span,
    }) catch @panic("oom");

    const relative_to_root = std.fs.path.relative(
        std.heap.c_allocator,
        std.Io.Dir.cwd().realPathFileAlloc(include_context.io, ".", std.heap.c_allocator) catch unreachable,
        include_context.environ_map,
        include_context.root_source_directory,
        file_path,
    ) catch @panic("");

    var path_component_iterator = std.fs.path.componentIterator(relative_to_root);

    while (path_component_iterator.next()) |path_component| {
        if (std.mem.eql(u8, path_component.path, "..")) {
            //TODO: make sure includes don't go outside the package path
        }
    }

    include_context.included_files.append(std.heap.c_allocator, file_path) catch unreachable;

    const file_contents = std.Io.Dir.cwd().readFileAlloc(include_context.io, file_path, std.heap.c_allocator, .unlimited) catch {
        return null;
    };

    result.header_name = header_name;
    result.header_length = file_contents.len;
    result.header_data = file_contents.ptr;

    return result;
}

fn glslIncludeResultFree(context: ?*anyopaque, glsl_include_result: [*c]glslang_c.glsl_include_result_t) callconv(.c) c_int {
    _ = context;

    std.heap.c_allocator.destroy(@as(*glslang_c.glsl_include_result_t, @ptrCast(glsl_include_result)));

    return 0;
}

pub fn main(init: std.process.Init) !void {
    run(init) catch |e| {
        switch (e) {
            error.CompileFailed => {},
            else => {
                return e;
            },
        }

        return;
    };
}

pub fn run(init: std.process.Init) !void {
    var process_args_iterator = init.minimal.args.iterate();

    _ = process_args_iterator.next().?;

    const arg_optimize = process_args_iterator.next().?;

    const shader_optimize = std.meta.stringToEnum(std.builtin.OptimizeMode, arg_optimize).?;

    const arg_stage = process_args_iterator.next().?;

    const Stage = enum {
        vertex,
        fragment,
        compute,
    };

    const stage = std.meta.stringToEnum(Stage, arg_stage).?;

    const arg_input_path = process_args_iterator.next().?;

    const source_file_data = try std.Io.Dir.cwd().readFileAllocOptions(
        init.io,
        arg_input_path,
        std.heap.page_allocator,
        .unlimited,
        .@"1",
        0,
    );

    const arg_output_path = process_args_iterator.next().?;

    if (glslang_c.glslang_initialize_process() == 0) {
        return error.FailedToInitializeProcess;
    }

    defer glslang_c.glslang_finalize_process();

    const shader_stage: c_uint = switch (stage) {
        .vertex => glslang_c.GLSLANG_STAGE_VERTEX,
        .fragment => glslang_c.GLSLANG_STAGE_FRAGMENT,
        .compute => glslang_c.GLSLANG_STAGE_COMPUTE,
    };

    const struct_glslang_input_s = extern struct {
        language: glslang_c.glslang_source_t,
        stage: glslang_c.glslang_stage_t,
        client: glslang_c.glslang_client_t,
        client_version: glslang_c.glslang_target_client_version_t,
        target_language: glslang_c.glslang_target_language_t,
        target_language_version: glslang_c.glslang_target_language_version_t,
        code: [*c]const u8,
        default_version: c_int,
        default_profile: glslang_c.glslang_profile_t,
        force_default_version_and_profile: c_int,
        forward_compatible: c_int,
        messages: glslang_c.glslang_messages_t,
        resource: [*c]const glslang_c.glslang_resource_t,
        callbacks: glslang_c.glsl_include_callbacks_t,
        context: ?*anyopaque,
    };

    var include_context: IncludeContext = .{
        .root_source_directory = std.fs.path.dirname(arg_input_path).?,
        .io = init.io,
        .environ_map = init.environ_map,
    };

    var input: struct_glslang_input_s = .{
        .language = glslang_c.GLSLANG_SOURCE_GLSL,
        .stage = shader_stage,
        .client = glslang_c.GLSLANG_CLIENT_OPENGL,
        .client_version = glslang_c.GLSLANG_TARGET_OPENGL_450,
        .target_language = glslang_c.GLSLANG_TARGET_SPV,
        .target_language_version = glslang_c.GLSLANG_TARGET_SPV_1_0,
        .code = source_file_data.ptr,
        .default_version = 450,
        .default_profile = glslang_c.GLSLANG_CORE_PROFILE,
        .force_default_version_and_profile = @intFromBool(true),
        .forward_compatible = @intFromBool(false),
        .messages = glslang_c.GLSLANG_MSG_DEFAULT_BIT | glslang_c.GLSLANG_MSG_DEBUG_INFO_BIT | glslang_c.GLSLANG_MSG_ENHANCED | glslang_c.GLSLANG_MSG_CASCADING_ERRORS_BIT,
        .resource = glslang_default_resource(),
        .callbacks = .{
            .include_local = &glslIncludeLocalFunc,
            .include_system = &glslIncludeLocalFunc,
            .free_include_result = &glslIncludeResultFree,
        },
        .context = &include_context,
    };

    const shader = glslang_c.glslang_shader_create(@ptrCast(&input)) orelse return error.FailedToCreateShader;
    defer glslang_c.glslang_shader_delete(shader);

    //glslang_c.glslang_shader_set_options(shader, glslang_c.GLSLANG_SHADER_AUTO_MAP_LOCATIONS);

    errdefer {
        const info_log = std.mem.span(@as([*:0]const u8, @ptrCast(glslang_c.glslang_shader_get_info_log(shader))));

        var info_log_lines = std.mem.tokenizeSequence(u8, info_log, &.{'\n'});

        while (info_log_lines.next()) |info_log_line| {
            const error_token: []const u8 = "ERROR: ";

            if (std.mem.startsWith(u8, info_log_line, error_token)) {
                const error_message = info_log_line[error_token.len..];

                if (std.mem.startsWith(u8, error_message, "0:")) {
                    log.err("{s}:{s}", .{ arg_input_path, error_message[2..] });
                } else {
                    log.err("{s}", .{error_message});
                }
            }
        }

        const debug_log: ?[*:0]const u8 = @ptrCast(glslang_c.glslang_shader_get_info_debug_log(shader));

        if (debug_log != null and std.mem.span(debug_log.?).len != 0) {
            log.debug("{s}", .{debug_log.?});
        }
    }

    if (glslang_c.glslang_shader_preprocess(shader, @ptrCast(&input)) == 0) {
        return error.CompileFailed;
    }

    if (glslang_c.glslang_shader_parse(shader, @ptrCast(&input)) == 0) {
        return error.CompileFailed;
    }

    const program = glslang_c.glslang_program_create() orelse return error.FailedToCreateProgram;
    defer glslang_c.glslang_program_delete(program);

    glslang_c.glslang_program_add_shader(program, shader);

    if (glslang_c.glslang_program_link(program, glslang_c.GLSLANG_MSG_SPV_RULES_BIT | glslang_c.GLSLANG_MSG_VULKAN_RULES_BIT) == 0) {
        return error.LinkFailed;
    }

    if (glslang_c.glslang_program_map_io(program) == 0) {
        return error.InputOutputMappingFailed;
    }

    const file_path = try std.heap.page_allocator.dupeSentinel(u8, arg_input_path, 0);

    glslang_c.glslang_program_add_source_text(program, shader_stage, source_file_data.ptr, source_file_data.len);
    glslang_c.glslang_program_set_source_file(program, shader_stage, file_path);

    var spirv_options: glslang_c.glslang_spv_options_t = .{
        .generate_debug_info = shader_optimize == .debug and false,
        .strip_debug_info = shader_optimize != .debug and false,
        .disable_optimizer = shader_optimize == .debug,
        .optimize_size = shader_optimize == .small,
        .disassemble = false,
        .validate = true,
        .emit_nonsemantic_shader_debug_info = shader_optimize == .debug and false,
        .emit_nonsemantic_shader_debug_source = shader_optimize == .debug and false,
    };

    glslang_c.glslang_program_SPIRV_generate_with_options(program, shader_stage, &spirv_options);

    const spirv_messages = glslang_c.glslang_program_SPIRV_get_messages(program);

    if (spirv_messages != null) {
        log.err("{s}", .{spirv_messages});

        return error.SpirvGenerationFailed;
    }

    const binary_size = glslang_c.glslang_program_SPIRV_get_size(program);
    const spirv_ptr = glslang_c.glslang_program_SPIRV_get_ptr(program);

    const spirv_data = spirv_ptr[0..binary_size];

    std.Io.Dir.cwd().createDir(init.io, std.fs.path.dirname(arg_output_path).?, .default_dir) catch {};

    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = arg_output_path, .data = std.mem.sliceAsBytes(spirv_data) });

    const maybe_dep_file_path = process_args_iterator.next();

    if (maybe_dep_file_path) |dep_file_path| {
        std.debug.print("dep_file: {s}\n", .{dep_file_path});

        var dep_file_contents: std.ArrayList(u8) = .empty;

        try dep_file_contents.appendSlice(init.arena.allocator(), file_path);
        try dep_file_contents.appendSlice(init.arena.allocator(), " : ");

        for (include_context.included_files.items) |file| {
            try dep_file_contents.appendSlice(init.arena.allocator(), file);
            try dep_file_contents.appendSlice(init.arena.allocator(), " ");
        }

        try std.Io.Dir.cwd().writeFile(init.io, .{ .data = dep_file_contents.items, .sub_path = dep_file_path });
    }
}

const std = @import("std");
const log = std.log.scoped(.glsl_compiler);
