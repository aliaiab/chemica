pub fn exportRasterVertexPipeline(
    module: type,
    comptime vertex_fn_name: []const u8,
    comptime fragment_fn_name: []const u8,
    comptime options: kernel.RasterVertexPipelineOptions,
) kernel.ExportedRasterPipeline {
    const vertex_module_name = @typeName(@import("root")) ++ "." ++ @typeName(module) ++ "." ++ vertex_fn_name;
    const fragment_module_name = @typeName(@import("root")) ++ "." ++ @typeName(module) ++ "." ++ fragment_fn_name;

    const result: kernel.ExportedRasterPipeline = .{
        .vertex_entry_point = vertex_module_name,
        .fragment_entry_point = fragment_module_name,
    };

    _ = options; // autofix
    if (!can_export_spirv) {
        //Return the spirv module
        return result;
    }

    const vertex_fn = @field(module, vertex_fn_name);
    const fragment_fn = @field(module, fragment_fn_name);

    const Static = struct {
        pub fn vertexMain() callconv(.spirv_vertex) void {
            const out = @extern(
                *addrspace(.output) @typeInfo(@typeInfo(@TypeOf(vertex_fn)).@"fn".return_type.?).@"struct".field_types[1],
                .{
                    .name = "out",
                    .decoration = .{
                        .location = 0,
                    },
                },
            );

            var args_tuple: std.meta.ArgsTuple(@TypeOf(vertex_fn)) = undefined;

            comptime var root_index: u32 = 0;

            inline for (&args_tuple) |*arg| {
                switch (@typeInfo(@TypeOf(arg.*))) {
                    .pointer => {
                        arg.* = @ptrFromInt(push_data.data_pointers[root_index]);
                        root_index += 1;
                    },
                    .@"enum" => {
                        arg.* = @fromBackingInt(@truncate(push_data.data_pointers[root_index]));
                        root_index += 1;
                    },
                    .@"struct" => {
                        switch (@TypeOf(arg.*)) {
                            kernel.RasterDrawCommandParameters => {
                                arg.* = .{
                                    .vertex_index = vertex_index,
                                    .draw_index = draw_index.*,
                                    .instance_index = instance_index,
                                };
                            },
                            kernel.SamplerHeap => {
                                arg.* = .{
                                    .sampler_count = samplers_2d.data.len,
                                    .backend_data = .{},
                                };
                            },
                            else => @compileError("Not supported!"),
                        }
                    },
                    else => @compileError(""),
                }
            }

            position_out.*, out.* = @call(.always_inline, vertex_fn, args_tuple);
        }

        pub fn fragmentMain() callconv(.{ .spirv_fragment = .{
            .depth_assumption = .unchanged,
        } }) void {
            //TODO: support multiple render targets
            const out_colour = @extern(*addrspace(.output) @Vector(4, f32), .{
                .name = "out_colour",
                .decoration = .{
                    .location = 0,
                },
            });

            const in = @extern(
                *addrspace(.input) @typeInfo(@typeInfo(@TypeOf(vertex_fn)).@"fn".return_type.?).@"struct".field_types[1],
                .{
                    .name = "in",
                    .decoration = .{
                        .location = 0,
                    },
                },
            );

            var args_tuple: std.meta.ArgsTuple(@TypeOf(fragment_fn)) = undefined;
            comptime var root_index: u32 = 0;

            inline for (&args_tuple) |*arg| {
                switch (@typeInfo(@TypeOf(arg.*))) {
                    .pointer => {
                        arg.* = @ptrFromInt(push_data.data_pointers[root_index]);
                        root_index += 1;
                    },
                    .@"enum" => {
                        arg.* = @fromBackingInt(@truncate(push_data.data_pointers[root_index]));
                        root_index += 1;
                    },
                    .@"struct" => {
                        switch (@TypeOf(arg.*)) {
                            kernel.RasterDrawCommandParameters => {
                                arg.* = .{
                                    .vertex_index = vertex_index,
                                    .draw_index = draw_index.*,
                                    .instance_index = instance_index,
                                };
                            },
                            kernel.SamplerHeap => {
                                arg.* = .{
                                    .backend_data = .{},
                                };
                            },
                            else => {
                                arg.* = in.*;
                            },
                        }
                    },
                    else => @compileError(""),
                }
            }

            blk: switch (@typeInfo(@typeInfo(@TypeOf(fragment_fn)).@"fn".return_type.?)) {
                .optional => {
                    out_colour.* = @call(.always_inline, fragment_fn, args_tuple) orelse {
                        opDiscard();

                        break :blk;
                    };
                },
                .@"struct" => {
                    out_colour.* = @call(.always_inline, fragment_fn, args_tuple);
                },
                .vector, .array => {
                    out_colour.* = @call(.always_inline, fragment_fn, args_tuple);
                },
                else => @compileError("Fragment kernel return type not supported!"),
            }
        }
    };

    @export(&Static.vertexMain, .{ .name = vertex_module_name });
    @export(&Static.fragmentMain, .{ .name = fragment_module_name });

    return result;
}

pub fn exportComputePipeline(
    module: type,
    comptime compute_fn_name: []const u8,
    comptime kernel_workgroup_size: kernel.WorkgroupSize,
) kernel.ExportedComputePipeline {
    const compute_entry_point = @typeName(@import("root")) ++ "." ++ @typeName(module) ++ "." ++ compute_fn_name;

    const result: kernel.ExportedComputePipeline = .{
        .compute_entry_point = compute_entry_point,
    };

    if (!can_export_spirv) {
        //Return the spirv module
        return result;
    }

    const compute_fn = @field(module, compute_fn_name);
    const Static = struct {
        pub fn computeMain() callconv(.{ .spirv_kernel = .{
            .x = kernel_workgroup_size.x,
            .y = kernel_workgroup_size.y,
            .z = kernel_workgroup_size.z,
        } }) void {
            var args_tuple: std.meta.ArgsTuple(@TypeOf(compute_fn)) = undefined;

            inline for (&args_tuple, 0..) |*arg, i| {
                switch (@typeInfo(@TypeOf(arg.*))) {
                    .pointer => {
                        arg.* = @ptrFromInt(push_data.data_pointers[i]);
                    },
                    .@"struct" => {
                        switch (@TypeOf(arg.*)) {
                            kernel.ComputeCommandParameters => {
                                arg.* = .{
                                    .global_invocation_id = global_invocation_id,
                                    .local_invocation_id = local_invocation_id,
                                    .workgroup_size = @splat(0),
                                    .workgroup_id = workgroup_id,
                                };
                            },
                            kernel.SamplerHeap => {
                                arg.* = .{
                                    .sampler_count = samplers_2d.data.len,
                                    .backend_data = .{},
                                };
                            },
                            else => @compileError("Type not supported!"),
                        }
                    },
                    else => @compileError(""),
                }
            }

            _ = @call(.always_inline, compute_fn, args_tuple);
        }
    };

    @export(&Static.computeMain, .{ .name = compute_entry_point });

    return result;
}

const push_data = @extern(*addrspace(.push_constant) const PushData, .{
    .name = "push_data",
});

const PushData = extern struct {
    data_pointers: [8]u64,
};

const samplers_2d = @extern(*addrspace(.constant) extern struct {
    data: @SpirvType(.{ .runtime_array = SamplerHeap.USampler2D }),
}, .{
    .name = "samplers",
    .decoration = .{
        .descriptor = .{
            .set = 0,
            .binding = 0,
        },
    },
});

pub const SamplerHeap = struct {
    padding: u32 = 0,

    pub fn imageDimensions(
        self: SamplerHeap,
        index: kernel.SamplerHeap.Index,
    ) @Vector(3, u32) {
        _ = self; // autofix
        _ = index; // autofix
        return @splat(0);
    }

    pub fn imageSample(
        self: SamplerHeap,
        index: kernel.SamplerHeap.Index,
        uv: @Vector(2, f32),
    ) @Vector(4, f32) {
        _ = self; // autofix

        return imageSampleImplicitLod(&samplers_2d.data[@backingInt(index)], uv);
    }

    pub fn imageFetch(
        self: SamplerHeap,
        index: kernel.SamplerHeap.Index,
        location: @Vector(3, i32),
    ) @Vector(4, f32) {
        _ = location; // autofix
        _ = self; // autofix
        _ = index; // autofix
        return @splat(0);
    }

    pub fn imageStore(
        self: SamplerHeap,
        index: kernel.SamplerHeap.Index,
        location: @Vector(3, i32),
        texel: @Vector(4, f32),
    ) void {
        _ = texel; // autofix
        _ = location; // autofix
        _ = self; // autofix
        _ = index; // autofix
    }

    pub const USampler2D = @SpirvType(.{ .sampled_image = UImage2DSampled });

    pub const UImage2DSampled = @SpirvType(.{ .image = .{
        .usage = .{ .sampled = f32 },
        .format = .unknown,
        .dim = .@"2d",
        .depth = .not_depth,
        .arrayed = false,
        .multisampled = false,
        .access = .unknown,
    } });

    pub const UImage2D = @SpirvType(.{ .image = .{
        .usage = .{ .storage = f32 },
        .format = .rgba8_unorm,
        .dim = .@"2d",
        .depth = .not_depth,
        .arrayed = false,
        .multisampled = false,
        .access = .unknown,
    } });
};

/// The type of `sampled_image` must be a pointer to a SPIR-V sampled image.
pub inline fn imageSampleImplicitLod(
    sampled_image: anytype,
    coordinate: ImageCoordinate(std.meta.Child(@TypeOf(sampled_image)), f32),
) @Vector(4, ImageSampledType(std.meta.Child(@TypeOf(sampled_image)))) {
    const SampledImage = switch (@typeInfo(@TypeOf(sampled_image))) {
        .pointer => |pointer| pointer.child,
        else => @compileError("Expected a pointer to SPIR-V sampled image type, found '" ++ @typeName(@TypeOf(sampled_image)) ++ "'"),
    };
    const Result = @Vector(4, ImageSampledType(SampledImage));

    const image_info = switch (@typeInfo(SampledImage)) {
        .spirv => |spv| switch (spv) {
            .sampled_image => |sampled_image_info| @typeInfo(sampled_image_info).spirv.image,
            else => @compileError("Expected SPIR-V sampled image type, found '" ++ @typeName(SampledImage) ++ "'"),
        },
        else => @compileError("Expected SPIR-V sampled image type, found '" ++ @typeName(SampledImage) ++ "'"),
    };

    if (image_info.multisampled)
        @compileError("Can not implicitly sample a sampled image that was multisampled");

    // TOOD: If buffer dim is added, throw a compile error if the dimension is a buffer.

    return asm volatile (
        \\%loaded_sampler = OpLoad %SampledImage %sampled_image
        \\%ret            = OpImageSampleImplicitLod %Result %loaded_sampler %coordinate
        : [ret] "" (-> Result),
        : [SampledImage] "t" (SampledImage),
          [sampled_image] "" (sampled_image),
          [Result] "t" (Result),
          [coordinate] "" (coordinate),
    );
}

/// Write a texel to an image without a sampler.
/// The type of `image` must be a pointer to a SPIR-V image.
pub inline fn imageFetch(
    image: anytype,
    T: type,
    coordinate: ImageCoordinate(std.meta.Child(@TypeOf(image)), T),
) @Vector(4, ImageSampledType(std.meta.Child(@TypeOf(image)))) {
    const ReturnType = @Vector(4, ImageSampledType(std.meta.Child(@TypeOf(image))));
    switch (T) {
        u32, i32 => {},
        else => @compileError("Expected one of u32, i32 and f32 types. Found '" ++ @typeName(T) ++ "'"),
    }

    const Image = switch (@typeInfo(@TypeOf(image))) {
        .pointer => |pointer| pointer.child,
        else => @compileError("Expected a pointer to SPIR-V image type, found '" ++ @typeName(@TypeOf(image)) ++ "'"),
    };

    return asm volatile (
        \\%loaded_image = OpLoad %Image %image
        \\%texel = OpImageRead %Result %loaded_image %coordinate
        : [texel] "" (-> ReturnType),
        : [Image] "t" (Image),
          [Result] "t" (ReturnType),
          [image] "" (image),
          [coordinate] "" (coordinate),
    );
}

/// Query the dimensions of `image`, with no level of detail.
pub inline fn imageQuerySize(
    image: anytype,
) ImageCoordinate(std.meta.Child(@TypeOf(image)), u32) {
    const Image = switch (@typeInfo(@TypeOf(image))) {
        .pointer => |pointer| pointer.child,
        else => @compileError("Expected a pointer to SPIR-V image type, found '" ++ @typeName(@TypeOf(image)) ++ "'"),
    };

    const image_info = switch (@typeInfo(Image)) {
        .spirv => |spv| switch (spv) {
            .image => |info| info,
            else => @compileError("Expected SPIR-V image type, found '" ++ @typeName(Image) ++ "'"),
        },
        else => @compileError("Expected SPIR-V image type, found '" ++ @typeName(Image) ++ "'"),
    };

    // TODO: Remove this check if dimension is not 1d, 2d, 3d, or cube (in case buffer is added).
    if (!image_info.multisampled and image_info.usage != .unknown and image_info.usage != .storage)
        @compileError("SPIR-V image must be either be multisampled or have an unknown or storage usage");

    const Result = ImageCoordinate(std.meta.Child(@TypeOf(image)), u32);

    return asm volatile (
        \\%loaded_image = OpLoad %Image %image
        \\%ret          = OpImageQuerySize %Result %loaded_image
        : [ret] "" (-> Result),
        : [Image] "t" (Image),
          [image] "" (image),
          [Result] "t" (Result),
    );
}

/// Write a texel to an image without a sampler.
/// The type of `image` must be a pointer to a SPIR-V image.
pub inline fn imageWrite(
    image: anytype,
    T: type,
    coordinate: ImageCoordinate(std.meta.Child(@TypeOf(image)), T),
    texel: @Vector(4, ImageSampledType(std.meta.Child(@TypeOf(image)))),
) void {
    switch (T) {
        u32, i32 => {},
        f32 => if (@import("builtin").target.os.tag != .opencl) {
            @compileError("Floating point image coordinates only supported by OpenCL");
        },
        else => @compileError("Expected one of u32, i32 and f32 types. Found '" ++ @typeName(T) ++ "'"),
    }

    const Image = switch (@typeInfo(@TypeOf(image))) {
        .pointer => |pointer| pointer.child,
        else => @compileError("Expected a pointer to SPIR-V image type, found '" ++ @typeName(@TypeOf(image)) ++ "'"),
    };

    const image_info = switch (@typeInfo(Image)) {
        .spirv => |spv| switch (spv) {
            .image => |info| info,
            else => @compileError("Expected SPIR-V image type, found '" ++ @typeName(Image) ++ "'"),
        },
        else => @compileError("Expected SPIR-V image type, found '" ++ @typeName(Image) ++ "'"),
    };

    switch (image_info.usage) {
        .unknown, .storage => {},
        else => @compileError("SPIR-V image must have unknown or storage usage"),
    }

    // TODO: If SubpassData dim is added, throw a compiler error if the image is arrayed and has the SubpassData dim.

    return asm volatile (
        \\%loaded_image = OpLoad %Image %image
        \\                OpImageWrite %loaded_image %coordinate %texel
        :
        : [Image] "t" (Image),
          [image] "" (image),
          [coordinate] "" (coordinate),
          [texel] "" (texel),
    );
}

/// The type of the components that result from sampling or reading from the given SPIR-V image or sampled image type.
fn ImageSampledType(Image: type) type {
    const image_info = switch (@typeInfo(Image)) {
        .spirv => |spv| switch (spv) {
            .sampled_image => |sampled_image| @typeInfo(sampled_image).spirv.image,
            .image => |image| image,
            else => @compileError("Expected SPIR-V image or sampled image type, found '" ++ @typeName(Image) ++ "'"),
        },
        else => @compileError("Expected SPIR-V image or sampled image type, found '" ++ @typeName(Image) ++ "'"),
    };
    return switch (image_info.usage) {
        inline else => |usage| usage,
    };
}

/// Get the type that specifies a coordinate for a SPIR-V image or sampled image.
fn ImageCoordinate(Image: type, Element: type) type {
    const image_info = switch (@typeInfo(Image)) {
        .spirv => |spv| switch (spv) {
            .sampled_image => |sampled_image| @typeInfo(sampled_image).spirv.image,
            .image => |image| image,
            else => @compileError("Expected SPIR-V image or sampled image type, found '" ++ @typeName(Image) ++ "'"),
        },
        else => @compileError("Expected SPIR-V image or sampled image type, found '" ++ @typeName(Image) ++ "'"),
    };
    const dim = switch (image_info.dim) {
        .@"1d" => 1 + @as(u8, @intFromBool(image_info.arrayed)),
        .@"2d" => 2 + @as(u8, @intFromBool(image_info.arrayed)),
        .@"3d", .cube => 3 + @as(u8, @intFromBool(image_info.arrayed)),
    };
    if (dim == 1) return Element else return @Vector(dim, Element);
}

pub inline fn atomicAdd(
    comptime T: type,
    ptr: *addrspace(address_space) T,
    operand: T,
    scope: kernel.Scope,
    semantics: kernel.MemorySemantics,
) T {
    return asm volatile (
        \\%res = OpAtomicIAdd %Type %pointer %scope %sem %operand
        : [res] "" (-> T),
        : [Type] "t" (T),
          [pointer] "" (ptr),
          [scope] "" (@as(u32, @backingInt(scope))),
          [sem] "" (@as(u32, @bitCast(semantics))),
          [operand] "" (operand),
    );
}

pub inline fn atomicMin(
    comptime T: type,
    ptr: *addrspace(address_space) T,
    operand: T,
    scope: kernel.Scope,
    semantics: kernel.MemorySemantics,
) T {
    return asm volatile (
        \\%res = OpAtomicSMin %Type %pointer %scope %sem %operand
        : [res] "" (-> T),
        : [Type] "t" (T),
          [pointer] "" (ptr),
          [scope] "" (@as(u32, @backingInt(scope))),
          [sem] "" (@as(u32, @bitCast(semantics))),
          [operand] "" (operand),
    );
}

pub inline fn atomicMax(
    comptime T: type,
    ptr: *addrspace(address_space) T,
    operand: T,
    scope: kernel.Scope,
    semantics: kernel.MemorySemantics,
) T {
    return asm volatile (
        \\%res = OpAtomicSMax %Type %pointer %scope %sem %operand
        : [res] "" (-> T),
        : [Type] "t" (T),
          [pointer] "" (ptr),
          [scope] "" (@as(u32, @backingInt(scope))),
          [sem] "" (@as(u32, @bitCast(semantics))),
          [operand] "" (operand),
    );
}

inline fn opDiscard() void {
    _ = asm volatile (
        \\OpKill
    );
}

const position_out = @extern(*addrspace(.output) @Vector(4, f32), .{ .name = "position" });

extern const vertex_index: u32 addrspace(.input);
extern const instance_index: u32 addrspace(.input);
const draw_index = @extern(*addrspace(.input) u32, .{
    .name = "draw_index",
});

extern const workgroup_size: @Vector(3, u32) addrspace(.input);
extern const workgroup_id: @Vector(3, u32) addrspace(.input);
extern const local_invocation_id: @Vector(3, u32) addrspace(.input);
extern const global_invocation_id: @Vector(3, u32) addrspace(.input);

///Address space to use for heterogenous compute
pub const address_space: std.builtin.AddressSpace = switch (@import("builtin").cpu.arch) {
    .spirv32, .spirv64 => switch (@import("builtin").os.tag) {
        .vulkan => .physical_storage_buffer,
        .opencl => .global,
        else => @compileError("Os not supported for spirv compilation!"),
    },
    else => .generic,
};

const can_export_spirv = @import("builtin").os.tag == .vulkan or @import("builtin").os.tag == .opencl;

const std = @import("std");
const kernel = @import("kernel.zig");
