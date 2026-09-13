pipeline: gpu.pipelines.Compiler.PipelineIndex,

pub fn init(
    pipeline_compiler: gpu.pipelines.Compiler,
) !AsymRenderer {
    const self: AsymRenderer = .{
        .pipeline = try pipeline_compiler.compileRasterVertexPipeline(
            pipeline_comptime,
            .{
                .color_targets = &.{.{
                    .format = .bgra8_srgb32,
                    .write_mask = 0xff,
                }},
                .depth_format = .depth_stencil_u24_u8,
                .stencil_format = .depth_stencil_u24_u8,
                .vertex_entry_point = pipeline_comptime.vertex_entry_point,
                .fragment_entry_point = pipeline_comptime.fragment_entry_point,
            },
        ),
    };

    return self;
}

pub fn render(
    self: AsymRenderer,
    command_buffer: *gpu.CommandBuffer,
    gpu_transient_arena: gpu.mem.Allocator,
    geo_context: *const asym.geo.Context,
    scene: *const asym.geo.Scene,
    views: []const asym.geo.Scene.View,
) !void {
    if (true) return;
    _ = geo_context; // autofix
    _ = scene; // autofix
    for (views) |*view| {
        gpu.setStateScissor(command_buffer, .{
            @intFromFloat(view.scissor[0]),
            @intFromFloat(view.scissor[1]),
            @intFromFloat(view.scissor[2]),
            @intFromFloat(view.scissor[3]),
        });

        var iter = view.iterate();

        while (iter.next()) |tuple| {
            const state, const group = tuple;
            _ = state; // autofix

            var draw_count: usize = 0;
            var param_count: usize = 0;

            for (
                group.draws_by_type.values,
                group.parameters_by_type.values,
            ) |
                draws,
                params,
            | {
                if (draws.len == 0) {
                    continue;
                }

                draw_count += draws.len;
                param_count += params.len;
            }

            const gpu_draws = try gpu_transient_arena.alloc(
                asym.geo.DrawCommand,
                draw_count,
                .gpu_cpu_writable,
            );
            const gpu_draws_cpu = gpu.mem.toAccessibleSlice(gpu_draws, .cpu);

            const gpu_params = try gpu_transient_arena.alloc(
                f32,
                param_count,
                .gpu_cpu_writable,
            );
            const gpu_params_cpu = gpu.mem.toAccessibleSlice(gpu_params, .cpu);

            const gpu_transforms = try gpu_transient_arena.alloc(
                asym.geo.AffineTransform3D,
                draw_count,
                .gpu_cpu_writable,
            );
            const gpu_transforms_cpu = gpu.mem.toAccessibleSlice(gpu_transforms, .cpu);

            const gpu_materials = try gpu_transient_arena.alloc(
                asym.geo.Material,
                draw_count,
                .gpu_cpu_writable,
            );
            const gpu_materials_cpu = gpu.mem.toAccessibleSlice(gpu_materials, .cpu);

            draw_count = 0;
            param_count = 0;

            for (
                group.draws_by_type.values,
                group.parameters_by_type.values,
                group.transforms_by_type.values,
                group.materials_by_type.values,
            ) |
                draws,
                params,
                transforms,
                materials,
            | {
                if (draws.len == 0) {
                    continue;
                }

                std.debug.print("draw_count = {}\n", .{draws.len});
                std.debug.print("transform_count = {}\n", .{transforms.len});

                @memcpy(gpu_draws_cpu[draw_count .. draw_count + draws.len], draws);
                @memcpy(gpu_transforms_cpu[draw_count .. draw_count + draws.len], transforms);
                @memcpy(gpu_materials_cpu[draw_count .. draw_count + draws.len], materials);
                @memcpy(gpu_params_cpu[param_count .. param_count + params.len], params);
                draw_count += draws.len;
                param_count += params.len;
            }

            gpu.setStateBlend(command_buffer, .{});
            gpu.setStateDepthStencil(command_buffer, .{});

            if (true) continue;

            gpu.launchRasterDraw(
                command_buffer,
                self.pipeline,
                &.{
                    undefined,
                    gpu_draws.ptr,
                    gpu_params.ptr,
                    gpu_transforms.ptr,
                    gpu_materials.ptr,
                },
                @as([*]gpu.RasterDrawCommand, @ptrCast(gpu_draws[0..].ptr))[0..draw_count],
                .{
                    .command_stride = @sizeOf(asym.geo.DrawCommand),
                },
            );
        }
    }
}

pub fn vertexMain(
    view_projection: [*]addrspace(kernel.address_space) math.Matrix(f32, 4, 4),
    draws: [*]addrspace(kernel.address_space) const asym.geo.DrawCommand,
    parameters: [*]addrspace(kernel.address_space) const f32,
    transforms: [*]addrspace(kernel.address_space) const asym.geo.AffineTransform3D,
    materials: [*]addrspace(kernel.address_space) const asym.geo.AffineTransform3D,
    draw_parameters: kernel.RasterDrawCommandParameters,
) struct { @Vector(4, f32), PipelinePacket } {
    _ = view_projection; // autofix
    _ = materials; // autofix
    _ = transforms; // autofix
    _ = parameters; // autofix
    _ = draws; // autofix
    _ = draw_parameters; // autofix
    return .{ @splat(0), undefined };
}

pub fn fragmentMain(
    input: PipelinePacket,
) @Vector(4, f32) {
    _ = input; // autofix

    return @splat(0);
}

const PipelinePacket = extern struct {
    pad: u32 = 0,
};

pub const pipeline_comptime = gpu.kernel.exportRasterVertexPipeline(
    @This(),
    "vertexMain",
    "fragmentMain",
    .{},
);

comptime {
    _ = pipeline_comptime;
}

const asym = @import("asym.zig");
const kernel = gpu.kernel;
const gpu = @import("gpu.zig");
const common = @import("lib").shaders.common;
const math = @import("math.zig");
const std = @import("std");
const AsymRenderer = @This();
