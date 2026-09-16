///Represents a heterogenous pointer
pub fn Pointer(comptime T: type) type {
    return extern struct {
        address: u64,

        pub const ChildType = T;

        pub fn toPointer(self: @This()) *addrspace(address_space) T {
            return @ptrFromInt(self.address);
        }

        pub fn toPointerMulti(self: @This()) [*]addrspace(address_space) T {
            return @ptrFromInt(self.address);
        }

        pub fn toConstPointer(self: @This()) *addrspace(address_space) const T {
            return @ptrFromInt(self.address);
        }

        pub fn toConstPointerMulti(self: @This()) [*]addrspace(address_space) const T {
            return @ptrFromInt(self.address);
        }
    };
}

///Represents a heterogenous slice
pub fn Slice(comptime T: type) type {
    return extern struct {
        address: u64,
        length: u64,

        pub fn toPointer(self: @This()) []addrspace(address_space) T {
            return Pointer(T).toPointerMulti(.{ .address = self.address })[0..self.length];
        }

        pub fn toConstPointer(self: @This()) []addrspace(address_space) const T {
            return Pointer(T).toPointerMulti(.{ .address = self.address })[0..self.length];
        }

        pub const ChildType = T;
    };
}

///Command parameters from launchCompute
pub const ComputeCommandParameters = struct {
    global_invocation_id: [3]u32,
    local_invocation_id: [3]u32,
    workgroup_size: [3]u32,
    workgroup_id: [3]u32,
};

///Command parameters from launchDraw and launchDrawIndexed
pub const RasterDrawCommandParameters = struct {
    vertex_index: u32,
    draw_index: u32,
    instance_index: u32,
};

pub const FragmentDepthAssumption = enum {
    any,
    greater,
    less_than,
};

///Reprsents fragment depth for input and output
pub fn FragmentDepth(comptime assumption: FragmentDepthAssumption) type {
    return enum(u32) {
        _,

        pub const depth_assumption = assumption;

        pub fn fromFloat(comptime T: type, value: T) @This() {
            return @bitCast(value);
        }
    };
}

///Represents an opaque, implementation specific acceleration structure for ray traversal
pub const AccelerationStructure = opaque {
    pub fn rayQuery() void {}

    pub fn rayTraverse(
        self: *addrspace(address_space) const AccelerationStructure,
    ) void {
        _ = self; // autofix

    }
};

pub const RayQuery = opaque {};

///Represents a heap of sampler descriptors
pub const SamplerHeap = struct {
    backend_data: backend.SamplerHeap,

    ///Returns the dimensions of an image descriptor
    pub fn imageDimensions(
        self: SamplerHeap,
        index: Index,
    ) @Vector(3, u32) {
        return self.backend_data.imageDimensions(index);
    }

    pub fn imageSample(
        self: SamplerHeap,
        index: Index,
        comptime T: type,
        uv: @Vector(2, f32),
    ) T {
        return self.backend_data.imageSample(index, uv);
    }

    pub fn imageFetch(
        self: SamplerHeap,
        index: Index,
        location: @Vector(3, i32),
    ) @Vector(4, f32) {
        return self.backend_data.imageFetch(index, location);
    }

    pub fn imageLoad(
        self: SamplerHeap,
        index: Index,
        location: @Vector(3, i32),
    ) void {
        return self.backend_data.imageLoad(index, location);
    }

    pub fn imageStore(
        self: SamplerHeap,
        index: Index,
        location: @Vector(3, i32),
        texel: @Vector(4, f32),
    ) void {
        return self.backend_data.imageStore(index, location, texel);
    }

    pub const Index = enum(u32) {
        null = std.math.maxInt(u32),
        _,

        ///Returns a sampler index from a pointer contained within a heap
        pub fn fromHeapPtr(heap: anytype, ptr: anytype) Index {
            return @fromBackingInt(@intCast((@intFromPtr(ptr) - @intFromPtr(heap)) / @sizeOf(u256)));
        }
    };
};

pub const Subgroup = struct {
    id: u32,
    size: u32,

    pub fn barrier(_: Subgroup) void {}

    pub fn memoryBarrier(_: Subgroup) void {}

    pub fn memoryBarrierShared(_: Subgroup) void {}

    pub fn memoryBarrierImage(_: Subgroup) void {}

    pub fn elect(_: Subgroup) bool {
        return true;
    }

    pub fn all(_: Subgroup, value: bool) bool {
        _ = value; // autofix
        return true;
    }

    pub fn any(_: Subgroup, value: bool) bool {
        _ = value; // autofix
        return true;
    }

    pub fn allEqual(_: Subgroup, value: bool) bool {
        _ = value; // autofix
        return true;
    }

    pub fn broadcast(_: Subgroup, comptime T: type, value: T, comptime id: u32) T {
        _ = id; // autofix
        return value;
    }

    pub fn ballot(_: Subgroup, value: bool) Ballot {
        _ = value; // autofix
        return undefined;
    }

    pub fn add(_: Subgroup, comptime T: type, value: T) T {
        return value;
    }

    pub fn mul(_: Subgroup, comptime T: type, value: T) T {
        return value;
    }

    pub fn min(_: Subgroup, comptime T: type, value: T) T {
        return value;
    }

    pub fn max(_: Subgroup, comptime T: type, value: T) T {
        return value;
    }

    pub fn shuffle(_: Subgroup, comptime T: type, value: T, index: u32) T {
        _ = index; // autofix
        return value;
    }

    pub const Ballot = packed struct(u128) {
        value: u128,

        ///Returns true if the ballot bit for the invocation is set
        pub fn isSet(self: Ballot, index: u32) bool {
            _ = self; // autofix
            _ = index; // autofix
            return false;
        }
    };
};

pub const SubgroupQuad = struct {
    pub fn broadcast(_: SubgroupQuad) void {}
    pub fn swapHorizontal(_: SubgroupQuad) void {}
    pub fn swapVertical(_: SubgroupQuad) void {}
    pub fn swapDiagonal(_: SubgroupQuad) void {}
    pub fn computeDerivativeCoarse(_: SubgroupQuad) void {}
    pub fn computeDerivative(_: SubgroupQuad) void {}
};

///References all public exported pipeline decls
pub fn referenceAllPipelines(
    module: type,
) void {
    switch (@typeInfo(module)) {
        .@"struct" => {
            for (@typeInfo(module).@"struct".decl_names) |decl| {
                if (@TypeOf(@field(module, decl)) == ExportedRasterPipeline) {
                    _ = @field(module, decl);
                    @compileError(decl);
                } else {
                    switch (@typeInfo(@TypeOf(@field(module, decl)))) {
                        .type => {
                            referenceAllPipelines(@field(module, decl));
                        },
                        else => {},
                    }
                }
            }
        },
        else => {},
    }
}

pub const RasterVertexPipelineOptions = struct {
    compile_constants_type: ?type = null,
};

pub const ExportedRasterPipeline = struct {
    vertex_entry_point: [:0]const u8,
    fragment_entry_point: [:0]const u8,
    ///Name of the zig module which can be @embedFile'd
    module_name: []const u8 = "",
};

pub const ExportedComputePipeline = struct {
    compute_entry_point: [:0]const u8,
    ///Name of the zig module which can be @embedFile'd
    module_name: []const u8 = "",
};

pub fn exportRasterVertexPipeline(
    module: type,
    comptime vertex_fn_name: [:0]const u8,
    comptime fragment_fn_name: [:0]const u8,
    comptime options: RasterVertexPipelineOptions,
) ExportedRasterPipeline {
    const vertex_module_name = @typeName(@import("root")) ++ "." ++ @typeName(module) ++ "." ++ vertex_fn_name;
    const fragment_module_name = @typeName(@import("root")) ++ "." ++ @typeName(module) ++ "." ++ fragment_fn_name;

    const result: ExportedRasterPipeline = .{
        .vertex_entry_point = vertex_module_name,
        .fragment_entry_point = fragment_module_name,
    };

    _ = backend.exportRasterVertexPipeline(
        module,
        vertex_fn_name,
        fragment_fn_name,
        options,
    );

    return result;
}

pub const WorkgroupSize = struct {
    x: u32,
    y: u32,
    z: u32,
};

pub fn exportComputePipeline(
    module: type,
    comptime compute_fn_name: []const u8,
    comptime kernel_workgroup_size: WorkgroupSize,
) ExportedComputePipeline {
    const compute_entry_point = @typeName(@import("root")) ++ "." ++ @typeName(module) ++ "." ++ compute_fn_name;

    const result: ExportedComputePipeline = .{
        .compute_entry_point = compute_entry_point,
    };

    _ = backend.exportComputePipeline(
        module,
        compute_fn_name,
        kernel_workgroup_size,
    );

    return result;
}

//TODO: remove when the language gets scope and semantics builtin to @atomicAdd
pub inline fn atomicAdd(
    comptime T: type,
    ptr: *addrspace(address_space) T,
    operand: T,
    scope: Scope,
    semantics: MemorySemantics,
) T {
    return backend.atomicAdd(
        T,
        ptr,
        operand,
        scope,
        semantics,
    );
}

pub const Scope = enum(u32) {
    cross_device = 0,
    device = 1,
    workgroup = 2,
    subgroup = 3,
    invocation = 4,
    queue_family = 5,
    kernel_call = 6,
};

pub const MemorySemantics = packed struct(u32) {
    _reserved_bit_0: bool = false,
    acquire: bool = false,
    release: bool = false,
    acquire_release: bool = false,
    sequentially_consistent: bool = false,
    _reserved_bit_5: bool = false,
    uniform_memory: bool = false,
    subgroup_memory: bool = false,
    workgroup_memory: bool = false,
    cross_workgroup_memory: bool = false,
    atomic_counter_memory: bool = false,
    image_memory: bool = false,
    output_memory: bool = false,
    make_available: bool = false,
    make_visible: bool = false,
    @"volatile": bool = false,
    _reserved: u16 = 0,

    pub const none: MemorySemantics = .{};
};

///Address space to use for heterogenous compute
pub const address_space: std.builtin.AddressSpace = backend.address_space;

const backend = @import("kernel_spirv.zig");
const std = @import("std");
