pub const Result = struct {
    sdf_grad: SdfGrad,
    material: u32,
};

pub const ElementHandle = enum(u32) {
    null = std.math.maxInt(u32),
    _,
};

pub const Element = packed struct {
    descriptor: Descriptor,
    params_start: u16,
    children_start: u16,
    children_count: u16,

    pub const Descriptor = packed struct(u16) {
        type: Type,
        modifiers: Modifiers,
    };

    pub const Type = enum(u8) {
        @"union",
        intersection,
        difference,
        box,
        cylinder,
        sphere,
        extrude,
        revolve,
        n_gon,
    };

    pub const Modifiers = packed struct(u8) {
        rounding: bool,
        extrusion: bool,
        repetition: bool,
        revolution: bool,
        elongation: bool,
        material: bool,
        pad: u2 = 0,
    };

    pub inline fn paramVec3(
        element: Element,
        comptime address_space: std.builtin.AddressSpace,
        params: anytype,
    ) @Vector(3, f32) {
        _ = address_space; // autofix
        return .{
            params[element.params_start],
            params[element.params_start + 1],
            params[element.params_start + 2],
        };
    }
};

///Represents (f, grad f)
pub const SdfGrad = extern struct {
    gradient: @Vector(3, f32) = @splat(0),
    distance: f32 = 0,

    ///Returns the interior (inverted)
    pub fn interior(f: SdfGrad) SdfGrad {
        return .{
            .distance = -f.distance,
            .gradient = f.gradient,
        };
    }

    ///Returns the sdf and gradient of a box
    pub fn box(
        p: @Vector(3, f32),
        b: @Vector(3, f32),
    ) SdfGrad {
        const w = @abs(p) - b;
        const g = @max(w[0], @max(w[1], w[2]));
        const q = @max(w, @as(@Vector(3, f32), @splat(0)));
        const l = @sqrt(@reduce(.Add, q * q));

        const q_on_l = q / @as(@Vector(3, f32), @splat(l));

        const f: @Vector(4, f32) = if (g > 0) .{
            l,
            q_on_l[0],
            q_on_l[1],
            q_on_l[2],
        } else .{
            g,
            if (w[0] == g) 1 else 0,
            if (w[1] == g) 1 else 0,
            if (w[2] == g) 1 else 0,
        };

        return .{
            .distance = f[0],
            .gradient = .{ f[1], f[2], f[3] },
        };
    }

    pub fn sphere(p: @Vector(3, f32), r: f32) SdfGrad {
        const l = @sqrt(@reduce(.Add, p * p));

        return .{
            .distance = l - r,
            .gradient = p / @as(@Vector(3, f32), @splat(l)),
        };
    }

    //Returns the set theoretic union of the two sdfs
    pub fn unionSet(lhs: SdfGrad, rhs: SdfGrad) SdfGrad {
        var res: SdfGrad = undefined;

        res.distance = @min(lhs.distance, rhs.distance);
        const t: f32 = if (lhs.distance < rhs.distance) 1 else 0;
        const t_vec: @Vector(3, f32) = @splat(t);
        const t_comp: @Vector(3, f32) = @splat(1 - t);

        res.gradient = lhs.gradient * t_vec + rhs.gradient * t_comp;

        return res;
    }

    //Returns the set theoretic intersection of the two sdfs
    pub fn intersectionSet(lhs: SdfGrad, rhs: SdfGrad) SdfGrad {
        var res: SdfGrad = undefined;

        res.distance = @max(lhs.distance, rhs.distance);
        const t: f32 = if (lhs.distance < rhs.distance) 1 else 0;
        const t_vec: @Vector(3, f32) = @splat(t);
        const t_comp: @Vector(3, f32) = @splat(1 - t);

        res.gradient = lhs.gradient * t_comp + rhs.gradient * t_vec;

        return res;
    }

    ///Returns the set theoretic difference of the two sdfs
    pub fn differenceSet(lhs: SdfGrad, rhs: SdfGrad) SdfGrad {
        return intersectionSet(lhs, rhs.interior());
    }
};

pub inline fn evaluateElement(
    comptime address_space: std.builtin.AddressSpace,
    element: Element,
    transform: shaders.AffineTransform3D,
    params: anytype,
    sample_position: @Vector(3, f32),
) SdfGrad {
    _ = transform; // autofix
    //const transformed_position = transform.transformInverseVector(sample_position);
    const transformed_position = sample_position;

    var sdf_grad: SdfGrad = .{};

    const desc = element.descriptor;

    switch (desc.type) {
        .box => {
            sdf_grad = .box(transformed_position, element.paramVec3(
                address_space,
                params,
            ));
        },
        .cylinder => {},
        .sphere => {
            sdf_grad = .sphere(
                transformed_position,
                params[element.params_start],
            );
        },
        .n_gon => {
            return sdf_grad;
        },
        .@"union",
        .difference,
        .intersection,
        .extrude,
        .revolve,
        => {
            return sdf_grad;
        },
    }

    //sdf_grad.distance *= transform.uniform_scale;

    return sdf_grad;
}

///Evaluates the SDF scene specified in the data slices
pub inline fn evaluate(
    comptime address_space: std.builtin.AddressSpace,
    elements: anytype,
    transforms: anytype,
    bounds: anytype,
    params: anytype,
    ///The root element to evaluate
    root_element_handle: ElementHandle,
    evaluation_bounds_min: @Vector(3, f32),
    evaluation_bounds_max: @Vector(3, f32),
    sample_position: @Vector(3, f32),
) Result {
    _ = evaluation_bounds_min; // autofix
    _ = evaluation_bounds_max; // autofix
    _ = bounds; // autofix
    //

    const stack_size = 8;
    var element_stack: [stack_size]ElementHandle = @splat(.null);
    const element_child_index_stack: [stack_size]u32 = @splat(0);
    var sdf_stack: [stack_size]f32 = @splat(0);
    var gradient_stack: [stack_size]@Vector(3, f32) = @splat(@splat(0));
    var stack_pointer: u32 = 1;
    element_stack[0] = root_element_handle;

    var test_sdf: SdfGrad = .box(sample_position, .{ 10, 10, 10 });

    if (false) {
        test_sdf = .unionSet(test_sdf, .sphere(sample_position - @Vector(3, f32){ 10, 10, 0 }, 10));
        test_sdf = .differenceSet(test_sdf, .sphere(sample_position - @Vector(3, f32){ 10, 5, 0 }, 10));
        return .{ .sdf_grad = test_sdf, .material = 0 };
    }

    //sdf_stack[0] = test_sdf.distance;
    //gradient_stack[0] = test_sdf.gradient;

    while (stack_pointer != 0) {
        stack_pointer -%= 1;

        const element_handle = element_stack[stack_pointer];
        const element = elements[@intFromEnum(element_handle)];

        const element_transform = transforms[@intFromEnum(element_handle)];
        _ = element_transform; // autofix

        var lhs_sdf_grad: SdfGrad = .{ .distance = sdf_stack[stack_pointer], .gradient = gradient_stack[stack_pointer] };
        var rhs_sdf_grad: SdfGrad = .{ .distance = 0, .gradient = @splat(0) };

        if (true) {
            for (element_child_index_stack[stack_pointer]..element.children_count) |child_index| {
                const child_element_index: u32 = @intCast(element.children_start + @as(u32, @intCast(child_index)));
                const child_element = elements[child_element_index];
                const child_transform = transforms[child_element_index];

                if (true) {
                    rhs_sdf_grad = evaluateElement(
                        address_space,
                        child_element,
                        child_transform,
                        params,
                        sample_position,
                    );
                }

                if (child_index == 0) {
                    lhs_sdf_grad = rhs_sdf_grad;
                    continue;
                }

                switch (element.descriptor.type) {
                    .@"union" => {
                        lhs_sdf_grad = .unionSet(lhs_sdf_grad, rhs_sdf_grad);
                    },
                    .intersection => {
                        lhs_sdf_grad = .intersectionSet(lhs_sdf_grad, rhs_sdf_grad);
                    },
                    .difference => {
                        lhs_sdf_grad = .differenceSet(lhs_sdf_grad, rhs_sdf_grad);
                    },
                    else => blk: {
                        break :blk;
                    },
                }
            }
        }

        sdf_stack[stack_pointer] = lhs_sdf_grad.distance;
        gradient_stack[stack_pointer] = lhs_sdf_grad.gradient;
    }

    return .{
        .sdf_grad = .{ .distance = sdf_stack[stack_pointer], .gradient = gradient_stack[stack_pointer] },
        .material = 0,
    };
}

pub const elements_buffer = @extern(*addrspace(.storage_buffer) extern struct {
    data: @SpirvType(
        .{ .runtime_array = Element },
    ),
}, .{
    .name = "elements",
    .decoration = .{
        .descriptor = .{
            .binding = 60,
            .set = 0,
        },
    },
});

pub const elemnents_transform_buffer = @extern(*addrspace(.storage_buffer) extern struct {
    data: @SpirvType(
        .{ .runtime_array = shaders.AffineTransform3D },
    ),
}, .{
    .name = "elements_transform",
    .decoration = .{
        .descriptor = .{
            .binding = 61,
            .set = 0,
        },
    },
});

pub const elements_params_buffer = @extern(*addrspace(.storage_buffer) extern struct {
    data: @SpirvType(
        .{ .runtime_array = f32 },
    ),
}, .{
    .name = "elements_params",
    .decoration = .{
        .descriptor = .{
            .binding = 62,
            .set = 0,
        },
    },
});

pub const elmements_bounds_buffer = @extern(*addrspace(.storage_buffer) extern struct {
    data: @SpirvType(
        .{
            .runtime_array = @Vector(4, f32),
        },
    ),
}, .{
    .name = "elements_bounds_buffer",
    .decoration = .{
        .descriptor = .{
            .binding = 63,
            .set = 0,
        },
    },
});

test {
    _ = evaluate(
        .generic,
        &.{},
        &.{},
        &.{},
        &.{},
        .null,
        @splat(0),
        @splat(0),
        @splat(0),
    );
}

test {
    _ = std.testing.refAllDecls(@This());
}

const std = @import("std");
const shaders = @import("lib").shaders;
