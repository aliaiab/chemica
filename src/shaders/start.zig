const root = @import("root");

pub const Pointer = spirv_ext.GpuPointer;
pub const Slice = spirv_ext.GpuSlice;

pub const ComputeCommandParameters = struct {
    global_invocation_id: [3]u32,
};

pub const RasterDrawCommandParameters = struct {
    vertex_index: u32,
    draw_index: u32,
    instance_index: u32,
};

pub const SamplerHeap = spirv_ext.SamplerHeap;

pub fn exportPipeline(
    comptime module_type: anytype,
) void {
    if (@import("builtin").os.tag == .vulkan) {
        switch (module_type) {
            .vertex => {
                if (@hasDecl(root, "vertexMain")) {
                    @export(&vertexMain, .{ .name = "main" });
                }
            },
            .fragment => {
                if (@hasDecl(root, "fragmentMain")) {
                    @export(&fragmentMain, .{ .name = "main" });
                }
            },
            else => @compileError(""),
        }
    }
}

pub fn exportComputePipeline(
    spirv_kernel_options: struct {
        x: comptime_int,
        y: comptime_int,
        z: comptime_int,
    },
) void {
    if (@import("builtin").os.tag == .vulkan) {
        const S = struct {
            pub fn computeMain() callconv(.{ .spirv_kernel = .{
                .x = spirv_kernel_options.x,
                .y = spirv_kernel_options.y,
                .z = spirv_kernel_options.z,
            } }) void {
                var args_tuple: std.meta.ArgsTuple(@TypeOf(root.computeMain)) = undefined;

                inline for (&args_tuple, 0..) |*arg, i| {
                    switch (@typeInfo(@TypeOf(arg.*))) {
                        .pointer => {
                            arg.* = @ptrFromInt(push_data.data_pointers[i]);
                        },
                        .@"struct" => {
                            switch (@TypeOf(arg.*)) {
                                ComputeCommandParameters => {
                                    arg.* = .{
                                        .global_invocation_id = spirv.global_invocation_id,
                                    };
                                },
                                SamplerHeap => {
                                    arg.* = .{
                                        .samplers_2d = @extern(@TypeOf(arg.*.samplers_2d), .{
                                            .name = "samplers",
                                        }),
                                    };
                                },
                                else => @compileError("Type not supported!"),
                            }
                        },
                        else => @compileError(""),
                    }
                }

                _ = @call(.always_inline, root.computeMain, args_tuple);
            }
        };

        if (@hasDecl(root, "computeMain")) {
            @export(&S.computeMain, .{ .name = "main" });
        }
    }
}

const push_data = @extern(*addrspace(.push_constant) const PushData, .{ .name = "push_data" });

const PushData = extern struct {
    data_pointers: [8]u64,
};

fn vertexMain() callconv(.spirv_vertex) void {
    const out = @extern(
        *addrspace(.output) @typeInfo(@typeInfo(@TypeOf(root.vertexMain)).@"fn".return_type.?).@"struct".field_types[1],
        .{
            .name = "out",
            .decoration = .{
                .location = 0,
            },
        },
    );

    var args_tuple: std.meta.ArgsTuple(@TypeOf(root.vertexMain)) = undefined;

    comptime var root_index: u32 = 0;

    inline for (&args_tuple) |*arg| {
        switch (@typeInfo(@TypeOf(arg.*))) {
            .pointer => {
                arg.* = @ptrFromInt(push_data.data_pointers[root_index]);
                root_index += 1;
            },
            .@"struct" => {
                switch (@TypeOf(arg.*)) {
                    RasterDrawCommandParameters => {
                        arg.* = .{
                            .vertex_index = spirv.vertex_index,
                            .draw_index = spirv_ext.draw_index.*,
                            .instance_index = spirv.instance_index,
                        };
                    },
                    SamplerHeap => {
                        arg.* = .{};
                    },
                    else => @compileError("Not supported!"),
                }
            },
            else => @compileError(""),
        }
    }

    spirv.position_out.*, out.* = @call(.always_inline, root.vertexMain, args_tuple);
}

fn fragmentMain() callconv(.{ .spirv_fragment = .{} }) void {
    const out_colour = @extern(*addrspace(.output) @Vector(4, f32), .{
        .name = "out_colour",
        .decoration = .{
            .location = 0,
        },
    });

    const in = @extern(
        *addrspace(.output) @typeInfo(@typeInfo(@TypeOf(root.vertexMain)).@"fn".return_type.?).@"struct".field_types[1],
        .{
            .name = "in",
            .decoration = .{
                .location = 0,
            },
        },
    );

    var args_tuple: std.meta.ArgsTuple(@TypeOf(root.fragmentMain)) = undefined;
    comptime var root_index: u32 = 0;

    inline for (&args_tuple) |*arg| {
        switch (@typeInfo(@TypeOf(arg.*))) {
            .pointer => {
                arg.* = @ptrFromInt(push_data.data_pointers[root_index]);
                root_index += 1;
            },
            .@"struct" => {
                switch (@TypeOf(arg.*)) {
                    RasterDrawCommandParameters => {
                        arg.* = .{
                            .vertex_index = spirv.vertex_index,
                            .draw_index = spirv_ext.draw_index.*,
                            .instance_index = spirv.instance_index,
                        };
                    },
                    SamplerHeap => {
                        arg.* = .{};
                    },
                    else => {
                        arg.* = in.*;
                    },
                }
            },
            else => @compileError(""),
        }
    }

    out_colour.* = @call(.always_inline, root.fragmentMain, args_tuple);
}

///Address space to use for heterogenous compute
pub const address_space: std.builtin.AddressSpace = switch (@import("builtin").cpu.arch) {
    .spirv32, .spirv64 => .physical_storage_buffer,
    else => std.builtin.AddressSpace.generic,
};

const spirv_ext = @import("lib").shaders.spirv_ext;
const spirv = std.spirv;
const std = @import("std");
