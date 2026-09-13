pub const Result = struct {
    sdf_grad: SdfGrad,
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

const std = @import("std");
