pub fn mulQuat(a: @Vector(4, f32), b: @Vector(4, f32)) @Vector(4, f32) {
    const lhs_rot: Rotor3(f32) = .cast(@as([4]f32, a));
    const rhs_rot: Rotor3(f32) = .cast(@as([4]f32, b));

    const res_rot: Rotor3(f32) = .mul(lhs_rot, rhs_rot);

    return res_rot.toComponents().toArray();
}

///Compute the nth root of x
pub fn rootn(comptime T: type, x: T, n: T) T {
    return expn(T, reciprocal(T, n), x);
}

///Compute the exp to the base n of x
pub fn expn(comptime T: type, x: T, base: T) T {
    return @exp(x * @log(base));
}

///Compute the reciprocal of x
pub fn reciprocal(comptime T: type, x: T) T {
    return switch (@typeInfo(T)) {
        .vector => @as(T, @splat(1)) / x,
        .float, .int => {
            return 1 / x;
        },
        else => @compileError("Type T not supported"),
    };
}

pub fn ScalarConstantType(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .vector => std.meta.Child(T),
        .int, .float => T,
        else => @compileError("T is not a valid scalar type"),
    };
}

pub fn scalarConstant(comptime T: type, constant: ScalarConstantType(T)) T {
    return switch (@typeInfo(T)) {
        .vector => @splat(constant),
        .int, .float => constant,
        else => comptime unreachable,
    };
}

///Represents the type of mathematical value
pub const ValueType = enum {
    none,
    decl_literal,
    scalar,
    vector,
    bivector,
    multor,
    rotor,
    matrix,
    tensor,
    angle,
    affine_transform,
    affine_transform_nonuniform,

    pub fn RuntimeScalar(comptime T: type) type {
        return switch (@typeInfo(T)) {
            .int, .float => T,
            .comptime_int, .comptime_float => return f64,
            else => f64,
        };
    }

    pub fn of(comptime T: type) ValueType {
        return switch (@typeInfo(T)) {
            .float, .int, .comptime_int, .comptime_float => .scalar,
            .pointer => .of(std.meta.Child(T)),
            .enum_literal => .decl_literal,
            .array => .vector,
            else => T.value_type,
        };
    }

    pub fn ofValue(value: anytype) ValueType {
        switch (@TypeOf(value)) {
            @EnumLiteral() => {
                switch (value) {
                    .i, .j, .k => .rotor,
                    .e0, .e1, .e2, .e3 => .vector,
                    .e12, .e21, .e31, .e13 => .bivector,
                    else => comptime unreachable,
                }
            },
            else => |T| return .of(T),
        }
    }

    pub fn dim(comptime T: type) usize {
        return switch (@typeInfo(T)) {
            .int, .float => 1,
            .pointer => dim(std.meta.Child(T)),
            else => T.value_dim,
        };
    }

    pub fn FieldType(comptime T: type) type {
        return switch (@typeInfo(T)) {
            .int, .float => T,
            .pointer => FieldType(std.meta.Child(T)),
            else => T.FieldType,
        };
    }

    pub fn info(comptime T: type) Info {
        return .{
            .dimension = dim(T),
            .type = of(T),
            .field_type = FieldType(T),
        };
    }

    pub fn cast(comptime ToType: type, value: anytype) ToType {
        return .cast(value);
    }

    pub const Info = struct {
        dimension: usize,
        type: ValueType,
        field_type: type,
    };
};

///Represents a linear algebra vector of dimension N in the orthonormal basis
pub fn Vec(dim: comptime_int, comptime T: type) type {
    return VecBasis(
        dim,
        T,
        .identity,
    );
}

///Represents a linear algebra vector of dimension N with a basis
pub fn VecBasis(
    dim: comptime_int,
    comptime T: type,
    comptime basis_matrix: Matrix(T, dim, dim),
) type {
    return extern struct {
        x: ComponentScalar(T, 0, dim) = 0,
        y: ComponentScalar(T, 1, dim) = 0,
        z: ComponentScalar(T, 2, dim) = 0,
        w: ComponentScalar(T, 3, dim) = 0,
        trailing: TrailingComponentScalars(T, 4, dim) = .{},

        pub fn fromComponents(components: VectorComponents(T, dim)) Self {
            return .{
                .x = components.x,
                .y = components.y,
                .z = components.z,
                .w = components.w,
                .trailing = components.trailing,
            };
        }

        pub fn toComponents(self: Self) VectorComponents(T, dim) {
            return .{
                .x = self.x,
                .y = self.y,
                .z = self.z,
                .w = self.w,
                .trailing = self.trailing,
            };
        }

        pub fn cast(value: anytype) Self {
            const value_value_type: ValueType = .of(@TypeOf(value));

            if (@typeInfo(@TypeOf(value)) == .pointer) {
                return .cast(value.*);
            }

            switch (value_value_type) {
                .scalar => @compileError("Cannot cast from scalar to vector!"),
                .vector => {
                    return value;
                },
                .decl_literal => {
                    return switch (value) {
                        .e0 => if (dim > 0) .e0 else basisVectorUseError(.e0),
                        .e1 => if (dim > 1) .e1 else basisVectorUseError(.e1),
                        .e2 => if (dim > 2) .e2 else basisVectorUseError(.e2),
                        .e3 => if (dim > 3) .e3 else basisVectorUseError(.e3),
                        else => @compileError("Decl literal not supported!"),
                    };
                },
                .rotor => return switch (@typeInfo(@TypeOf(value))) {
                    .@"struct" => {
                        return .{
                            .x = value.x,
                            .y = value.y,
                            .z = value.z,
                        };
                    },
                    else => value,
                },
                else => return switch (@typeInfo(@TypeOf(value))) {
                    .pointer => value.*,
                    else => value,
                },
            }
        }

        pub fn componentAt(self: Self, index: usize) T {
            return self.toComponents().toArray()[index];
        }

        pub fn add(lhs: Self, rhs: Self) Self {
            return .fromComponents(lhs.toComponents().add(rhs.toComponents()));
        }

        pub fn sub(lhs: Self, rhs: Self) Self {
            return lhs.add(rhs.negate());
        }

        ///Scale lhs by rhs
        pub fn scale(lhs: Self, rhs: T) Self {
            return .fromComponents(lhs.toComponents().scale(rhs));
        }

        pub fn negate(vector: Self) Self {
            return vector.scale(-1);
        }

        ///Compute the vector square of lhs
        pub fn square(vector: Self) T {
            return vector.inner(vector);
        }

        ///Raises the vector to the kth power
        pub fn pow(vector: Self, n: T) T {
            _ = n; // autofix
            _ = vector; // autofix
            //TODO: implement pow
            unreachable;
        }

        ///Compute the euclidean 2-norm of vector
        pub fn norm(vector: Self) T {
            return @sqrt(vector.square());
        }

        ///Return the unit vector in the direction of the vector
        pub fn unit(vector: Self) Self {
            return vector.scale(reciprocal(T, vector.norm()));
        }

        ///Return the euclidean distance between lhs and rhs
        pub fn distance(lhs: Self, rhs: Self) T {
            return lhs.sub(rhs).norm();
        }

        ///Compute the euclidean k-norm of vector
        pub fn pnorm(vector: Self, p: usize) T {
            return rootn(vector.pow(p), p);
        }

        pub fn fromAny(any: anytype) Self {
            return switch (@typeInfo(@TypeOf(any))) {
                .enum_literal => switch (any) {
                    .e0 => if (dim > 0) .e0 else basisVectorUseError(.e0),
                    .e1 => if (dim > 1) .e1 else basisVectorUseError(.e1),
                    .e2 => if (dim > 2) .e2 else basisVectorUseError(.e2),
                    .e3 => if (dim > 3) .e3 else basisVectorUseError(.e3),
                    else => @compileError("Decl literal not supported!"),
                },
                .pointer => any.*,
                else => return any,
            };
        }

        ///Computes the inner product of lhs and rhs
        pub fn inner(lhs: anytype, rhs: anytype) T {
            const actual_lhs = fromAny(lhs);
            const actual_rhs = fromAny(rhs);
            return actual_lhs.toComponents().inner(actual_rhs.toComponents());
        }

        ///Computes the outer product of lhs and rhs
        pub fn outer(lhs: anytype, rhs: anytype) Bivec(T, dim) {
            _ = lhs; // autofix
            _ = rhs; // autofix
            switch (dim) {
                0 => return .{},
                1 => return .{},
                2 => return .{},
                3 => return .{},
                else => @compileError("Outer product for dim not yet defined"),
            }
        }

        ///Computes the cross product of lhs and rhs
        pub fn cross(lhs: anytype, rhs: anytype) Bivec(T, dim) {
            if (dim != 3 and dim != 7) {
                @compileError("The cross product is only defined for vectors of dimension 3 and 7!");
            }

            return outer(lhs, rhs).negate();
        }

        ///Computes the hadamard product of lhs and rhs
        pub fn hadamard(lhs: Self, rhs: Self) Self {
            return .fromComponents(lhs.toComponents().hadamard(rhs.toComponents()));
        }

        ///Computes the product of lhs and rhs
        ///Multiplying a vector and a vector uses the grassmann product
        ///Multiplying a vector a and a scalar scales the vector by the scalar
        ///Multiplying a vector by a matrix multiples the vector by the matrix
        pub fn mul(
            lhs: anytype,
            rhs: anytype,
        ) ProductType(@TypeOf(lhs), @TypeOf(rhs)) {
            const Prod = ProductType(@TypeOf(lhs), @TypeOf(rhs));

            const prod_value_type: ValueType = .of(Prod);

            switch (prod_value_type) {
                .vector => unreachable,
                .rotor => {
                    var result: Rotor(dim, T) = undefined;

                    result.a = lhs.inner(rhs);
                    if (dim == 2) {
                        result.x = lhs.outer(rhs).vector().x;
                    } else {
                        result.vectorPtr().* = lhs.outer(rhs).vector();
                    }

                    return result;
                },
                else => comptime unreachable,
            }
        }

        ///Divides lhs by rhs
        pub fn div(lhs: anytype, rhs: anytype) ProductType(@TypeOf(lhs), @TypeOf(rhs)) {
            return lhs.mul(rhs.inverse());
        }

        ///Returns the conjugate of the vector
        pub inline fn conjugate(vector: Self) Self {
            return vector;
        }

        ///Compute the multiplicative inverse of the vector
        pub fn inverse(vector: Self) Self {
            return vector.conjugate().mul(reciprocal(vector.square()));
        }

        pub const zero: Self = .{};

        ///The first basis vector
        pub const e0: Self = if (dim > 0) basis[0] else basisVectorUseError(.e0);
        ///The second basis vector
        pub const e1: Self = if (dim > 1) basis[1] else basisVectorUseError(.e1);
        ///The third basis vector
        pub const e2: Self = if (dim > 2) basis[2] else basisVectorUseError(.e2);
        //The fourth basis vector
        pub const e3: Self = if (dim > 3) basis[3] else basisVectorUseError(.e3);
        ///The fifth basis vector
        pub const e4: Self = if (dim > 4) basis[4] else basisVectorUseError(.e4);

        ///The standard orthonormal basis
        pub const basis: [dim]Self = basis_matrix.columns();
        pub const value_type: ValueType = .vector;
        pub const value_dim: comptime_int = dim;
        pub const FieldType = T;

        fn basisVectorUseError(comptime basis_name: @EnumLiteral()) noreturn {
            @compileError(
                @tagName(basis_name) ++ " is not defined in " ++ std.fmt.comptimePrint(
                    "{s}",
                    .{@typeName(Self)},
                ),
            );
        }

        const Self = @This();
    };
}

///Alias for Vec(2, T)
pub fn Vec2(comptime T: type) type {
    return Vec(2, T);
}

///Alias for Vec(3, T)
pub fn Vec3(comptime T: type) type {
    return Vec(3, T);
}

///Alias for Vec(4, T)
pub fn Vec4(comptime T: type) type {
    return Vec(4, T);
}

///Alias for Vec2(f32)
pub const Vec2f32 = Vec2(f32);
///Alias for Vec3(f32)
pub const Vec3f32 = Vec3(f32);
///Alias for Vec4(f32)
pub const Vec4f32 = Vec4(f32);

///Alias for Rotor(2, T)
pub fn Rotor2(comptime T: type) type {
    return Rotor(2, T);
}

///Alias for Rotor(3, T)
pub fn Rotor3(comptime T: type) type {
    return Rotor(3, T);
}

///Alias for Rotor2(f32)
pub const Rotor2f32 = Rotor2(f32);
///Alias for Rotor3(f32)
pub const Rotor3f32 = Rotor3(f32);

comptime {
    if (false) {
        var vec: Vec2f32 = .zero;

        vec = .e1;
        //vec = .add(.mul(.e1, 5), .e1);
        vec = vec.add(.{ .x = 1, .y = 2 });

        const vec3 = vec.toComponents().xyz();
        _ = vec3; // autofix

        const rot_angle: Angle(f32, .turns) = .{ .value = 0.5 };

        const rotation: Rotor2(f32) = .exp(rot_angle);

        const rot: Rotor2(f32) = vec.mul(.e1);

        const rotated = rot.mul(vec);
        const rotated_again = rotation.mul(rotated);
        _ = rotated_again; // autofix
        var z: Rotor2(f32) = .add(5, .i); //5 + i

        z = .mul(z, .i);

        @compileLog(z);
        z = .mul(z, .i);

        @compileLog(z);

        const q: Quaternion(f32) = .cast(z);
        _ = q; // autofix

        const bivec = Vec2f32.e0.outer(.e1);

        const bivec_area = @abs(bivec.norm());
        _ = bivec_area; // autofix
    }
}

///Represents a bivector
pub fn Bivec(comptime T: type, dim: comptime_int) type {
    return extern struct {
        x: ComponentScalar(T, 0, n) = 0,
        y: ComponentScalar(T, 1, n) = 0,
        z: ComponentScalar(T, 2, n) = 0,
        w: ComponentScalar(T, 3, n) = 0,
        trailing: TrailingComponentScalars(T, 4, n) = .{},

        pub fn fromComponents(components: VectorComponents(T, n)) Self {
            return .{
                .x = components.x,
                .y = components.y,
                .z = components.z,
                .w = components.w,
                .trailing = components.trailing,
            };
        }

        pub fn toComponents(self: Self) VectorComponents(T, n) {
            return .{
                .x = self.x,
                .y = self.y,
                .z = self.z,
                .w = self.w,
                .trailing = self.trailing,
            };
        }

        pub fn add(lhs: Self, rhs: Self) Self {
            return .fromComponents(lhs.toComponents().add(rhs.toComponents()));
        }

        pub fn sub(lhs: Self, rhs: Self) Self {
            return lhs.add(rhs.negate());
        }

        pub fn scale(lhs: Self, rhs: T) Self {
            return .fromComponents(lhs.toComponents().scale(rhs));
        }

        pub fn negate(bivector: Self) Self {
            return bivector.scale(-1);
        }

        ///Compute the inner product of lhs and rhs
        pub fn inner(lhs: Self, rhs: Self) T {
            return lhs.toComponents().inner(rhs.toComponents());
        }

        ///Compute the square of the bivector
        pub fn square(bivector: Self) T {
            return -bivector.inner(bivector);
        }

        ///Returns the unit bivector of bivector
        pub fn unit(bivector: Self) Self {
            return bivector.scale(reciprocal(T, bivector.norm()));
        }

        ///Compute the euclidean 2-norm of the bivector
        pub fn norm(bivector: Self) T {
            return @sqrt(@abs(bivector.square()));
        }

        ///Returns the bivector as a vector
        pub fn vector(bivector: Self) Vec(n, T) {
            return .fromComponents(bivector.toComponents());
        }

        pub const zero: Self = .{};

        pub const n: comptime_int = blk: {
            break :blk switch (dim) {
                0 => 0,
                1 => 1,
                2 => 1,
                3 => 3,
                else => unreachable,
            };
        };

        pub const e12: Self = Vec(T, dim).e1.outer(.e2);
        pub const e23: Self = Vec(T, dim).e2.outer(.e3);
        pub const e31: Self = Vec(T, dim).e3.outer(.e1);

        pub const value_type: ValueType = .bivector;
        pub const value_dim: comptime_int = dim;

        const Self = @This();
    };
}

///A complex number type
///Alias for a Rotor(T, 2)
pub fn Complex(comptime T: type) type {
    return Rotor(2, T);
}

///A quaternion type
///Alias for Rotor(T, 3)
pub fn Quaternion(comptime T: type) type {
    //TODO: add rotor handedness
    return Rotor(3, T);
}

///Storage for a named component (x, y, z, w, ect..)
pub fn ComponentScalar(comptime T: type, i: comptime_int, dim: comptime_int) type {
    if (i >= dim) {
        return u0;
    }

    return T;
}

pub fn TrailingComponentScalars(comptime T: type, comptime i: usize, comptime dim: usize) type {
    return ComponentScalars(T, (i -| 1) -| dim);
}

///Storage struct for components that go after the named components (x, y, z, w)
pub fn ComponentScalars(comptime T: type, comptime dim: usize) type {
    return extern struct {
        values: [dim]T = @splat(0),

        pub fn add(lhs: Self, rhs: Self) Self {
            var result: Self = undefined;
            for (&result.values, lhs.values, rhs.values) |*res, a, b| {
                res.* = a + b;
            }
            return result;
        }

        pub fn sub(lhs: Self, rhs: Self) Self {
            return lhs.add(rhs.negate());
        }

        pub fn scale(lhs: Self, rhs: T) Self {
            var result: Self = undefined;
            for (&result.values, lhs.values) |*res, a| {
                res.* = a * rhs;
            }
            return result;
        }

        pub fn negate(rhs: Self) Self {
            return rhs.scale(-1);
        }

        pub fn inner(lhs: Self, rhs: Self) T {
            var result: T = 0;

            for (lhs.values, rhs.values) |a, b| {
                result += a * b;
            }

            return result;
        }

        pub fn hadamard(lhs: Self, rhs: Self) Self {
            var result: Self = undefined;

            for (&result.values, lhs.values, rhs.values) |*res, a, b| {
                res.* = a * b;
            }

            return result;
        }

        const Self = @This();
    };
}

pub fn MatrixComponents(comptime T: type, m: comptime_int, n: comptime_int) type {
    _ = T; // autofix
    _ = m; // autofix
    _ = n; // autofix
    return extern struct {};
}

///A struct of named scalar components
pub fn VectorComponents(comptime T: type, dim: comptime_int) type {
    return extern struct {
        x: ComponentScalar(T, 0, dim) = 0,
        y: ComponentScalar(T, 1, dim) = 0,
        z: ComponentScalar(T, 2, dim) = 0,
        w: ComponentScalar(T, 3, dim) = 0,
        trailing: TrailingComponentScalars(T, 4, dim) = .{},

        pub fn toArray(self: Self) [dim]T {
            var array: [dim]T = undefined;

            if (dim > 0) array[0] = self.x;
            if (dim > 1) array[1] = self.y;
            if (dim > 2) array[2] = self.z;
            if (dim > 3) array[3] = self.w;

            if (dim > 4) {
                @memcpy(array[4..], &self.trailing.values);
            }

            return array;
        }

        pub fn fromArray(array: [dim]T) Self {
            var self: Self = .{};

            self.x = if (dim != 0) array[0] else 0;
            self.y = if (dim > 1) array[1] else 0;
            self.z = if (dim > 2) array[2] else 0;
            self.w = if (dim > 3) array[3] else 0;

            if (dim > 4) {
                @memcpy(&self.trailng.values, array[4..]);
            }

            return self;
        }

        pub fn xyzw(self: Self) Vec(4, T) {
            return .{ .x = self.x, .y = self.y, .z = self.z, .w = self.w };
        }

        pub fn yxwz(self: Self) Vec(4, T) {
            return .{ .x = self.y, .y = self.x, .z = self.w, .w = self.z };
        }

        pub fn wzyx(self: Self) Vec(4, T) {
            return .{ .x = self.w, .y = self.z, .z = self.y, .w = self.x };
        }

        pub fn xxy(self: Self) Vec(3, T) {
            return .{ .x = self.x, .y = self.x, .z = self.y };
        }

        pub fn yxx(self: Self) Vec(3, T) {
            return .{ .x = self.y, .y = self.x, .z = self.x };
        }

        pub fn xyz(self: Self) Vec(3, T) {
            return .{ .x = self.x, .y = self.y, .z = self.z };
        }

        pub fn xzy(self: Self) Vec(3, T) {
            return .{ .x = self.x, .y = self.z, .z = self.y };
        }

        pub fn zyx(self: Self) Vec(3, T) {
            return .{ .x = self.z, .y = self.y, .z = self.x };
        }

        pub fn yzx(self: Self) Vec(3, T) {
            return .{ .x = self.y, .y = self.z, .z = self.x };
        }

        pub fn xy(self: Self) Vec(2, T) {
            return .{ .x = self.x, .y = self.y };
        }

        pub fn xx(self: Self) Vec(2, T) {
            return .{ .x = self.x, .y = self.x };
        }

        pub fn yx(self: Self) Vec(2, T) {
            return .{ .x = self.y, .y = self.x };
        }

        pub fn yy(self: Self) Vec(2, T) {
            return .{ .x = self.y, .y = self.y };
        }

        ///Add lhs and rhs
        pub fn add(lhs: Self, rhs: Self) Self {
            var result: Self = undefined;

            if (@import("builtin").cpu.arch == .spirv32 or @import("builtin").cpu.arch == .spirv64) {
                const v0: @Vector(dim, T) = lhs.toArray();
                const v1: @Vector(dim, T) = lhs.toArray();

                const res = v0 + v1;

                return .fromArray(res);
            }

            result.x = lhs.x + rhs.x;
            result.y = lhs.y + rhs.y;
            result.z = lhs.z + rhs.z;
            result.w = lhs.w + rhs.w;

            result.trailing = .add(lhs.trailing, rhs.trailing);

            return result;
        }

        ///Subtract rhs from lhs
        pub fn sub(lhs: Self, rhs: Self) Self {
            return lhs.add(.negate(rhs));
        }

        ///Scale lhs by rhs
        pub fn scale(lhs: Self, rhs: T) Self {
            var result: Self = undefined;
            result.x = lhs.x * rhs;
            result.y = lhs.y * rhs;
            result.z = lhs.z * rhs;
            result.w = lhs.w * rhs;
            result.trailing = .scale(lhs.trailing, rhs);

            return result;
        }

        pub fn inner(lhs: Self, rhs: Self) T {
            var result: T = 0;

            if (@import("builtin").cpu.arch == .spirv32 or @import("builtin").cpu.arch == .spirv64) {
                const v0: @Vector(dim, T) = lhs.toArray();
                const v1: @Vector(dim, T) = lhs.toArray();

                const res = v0 * v1;

                return @reduce(.Add, res);
            }

            result += lhs.x * rhs.x;
            result += lhs.y * rhs.y;
            result += lhs.z * rhs.z;
            result += lhs.w * rhs.w;
            result += lhs.trailing.inner(rhs.trailing);

            return result;
        }

        pub fn square(lhs: Self) T {
            return lhs.inner(lhs);
        }

        ///Negate rhs
        pub fn negate(lhs: Self) Self {
            return lhs.scale(-1);
        }

        pub fn hadamard(lhs: Self, rhs: Self) Self {
            var result: Self = undefined;

            if (@import("builtin").cpu.arch == .spirv32 or @import("builtin").cpu.arch == .spirv64) {
                const v0: @Vector(dim, T) = lhs.toArray();
                const v1: @Vector(dim, T) = lhs.toArray();

                const res = v0 * v1;

                return .fromArray(res);
            }

            result.x = lhs.x * rhs.x;
            result.y = lhs.y * rhs.y;
            result.z = lhs.z * rhs.z;
            result.w = lhs.w * rhs.w;
            result.trailing = lhs.trailing.hadamard(rhs.trailing);

            return result;
        }

        pub const zero: Self = .{};

        const Self = @This();
    };
}

///Represents a clifford algebra rotor in dimension N
///Rotor(T, 2) == Complex number
///Rotor(T, 3) == Negative quaternion
pub fn Rotor(dim: comptime_int, comptime T: type) type {
    return extern struct {
        a: ComponentScalar(T, 0, n) = 0,
        x: ComponentScalar(T, 1, n) = 0,
        y: ComponentScalar(T, 2, n) = 0,
        z: ComponentScalar(T, 3, n) = 0,
        trailing: TrailingComponentScalars(T, 4, n) = .{},

        pub const value_type: ValueType = .rotor;

        pub fn fromComponents(components: VectorComponents(T, n)) Self {
            return .{
                .a = if (n >= 1) components.x else 0,
                .x = if (n >= 2) components.y else 0,
                .y = if (n >= 3) components.z else 0,
                .z = if (n >= 4) components.w else 0,
                .trailing = components.trailing,
            };
        }

        pub fn toComponents(self: Self) VectorComponents(T, n) {
            return .{
                .x = if (n >= 1) self.a else 0,
                .y = if (n >= 2) self.x else 0,
                .z = if (n >= 3) self.y else 0,
                .w = if (n >= 4) self.z else 0,
                .trailing = self.trailing,
            };
        }

        pub fn fromScalar(scalar: T) Self {
            return .{ .a = scalar };
        }

        pub fn fromVector(vec: Vec(dim, T)) Self {
            return switch (dim) {
                2 => .{ .a = vec.x, .x = vec.y },
                3 => .{ .a = 0, .x = vec.x, .y = vec.y, .z = vec.z },
                else => @compileError("Not yet supported!"),
            };
        }

        pub fn cast(value: anytype) Self {
            const value_value_type: ValueType = .of(@TypeOf(value));

            if (@typeInfo(@TypeOf(value)) == .pointer) {
                return .cast(value.*);
            }

            switch (value_value_type) {
                .scalar => return fromScalar(value),
                .vector => {
                    return fromVector(value);
                },
                .decl_literal => {
                    return switch (value) {
                        .i => .i,
                        .j => .j,
                        .k => .k,
                        else => comptime unreachable,
                    };
                },
                .rotor => return switch (@typeInfo(@TypeOf(value))) {
                    .@"struct" => {
                        if (@TypeOf(value) == Self) {
                            return value;
                        }

                        return .{
                            .a = value.a,
                            .x = value.x,
                            .y = value.y,
                            .z = value.z,
                        };
                    },
                    else => value,
                },
                else => return switch (@typeInfo(@TypeOf(value))) {
                    .pointer => value.*,
                    else => value,
                },
            }
        }

        pub fn castTo(comptime ToType: type, value: anytype) ToType {
            return .cast(value);
        }

        ///Returns the real part of the rotor (the scalar part)
        pub fn real(self: Self) T {
            return self.a;
        }

        ///Return the imaginary part (at the specified imaginary index)
        ///Equivalent to vector(self).asArray()[index.value]
        pub fn imaginary(
            self: Self,
            index: struct {
                value: usize = 0,
            },
        ) T {
            return switch (index.value) {
                0 => self.x,
                1 => self.y,
                2 => self.z,
                3 => self.trailing.values[index.value - 3],
            };
        }

        ///Returns the vector representation or part of the rotor
        pub fn vector(self: Self) Vec(dim, T) {
            if (dim == 2) {
                return .{ .x = self.a, .y = self.x };
            }

            if (dim <= 2) {
                @compileError("Rotors of dimension 2 or less don't have a vector part");
            }

            return .{ .x = self.x, .y = self.y, .z = self.z };
        }

        ///Returns the vector part of the rotor
        pub fn vectorPtr(self: *Self) *Vec(ValueType.dim(Bivec(T, dim)), T) {
            if (dim <= 2) {
                @compileError("Rotors of dimension 2 or less don't have a vector part");
            }

            return @ptrCast(&self.x);
        }

        //evaluates exp(angle)
        //Angle can be a scalar, Angle, vector or rotor
        pub fn exp(value: anytype) Self {
            return switch (dim) {
                1 => .{ .a = value },
                2 => trig.euler(T, value),
                3 => .mul(
                    @exp(value.a),
                    .add(
                        trig.cos(T, value.norm()),
                        value.vector().unit().mul(trig.sin(T, value.norm())),
                    ),
                ),
                else => @compileError("Dim not supported"),
            };
        }

        ///Evaluates exp(i*value)
        pub fn expi(rotor: Self, value: anytype) Self {
            _ = value; // autofix
            _ = rotor; // autofix
        }

        ///Scale the rotor by rhs
        pub fn scale(lhs: Self, rhs: T) Self {
            return .fromComponents(lhs.toComponents().scale(rhs));
        }

        ///Negate the rotor
        pub fn negate(lhs: Self) Self {
            return lhs.scale(-1);
        }

        pub fn add(lhs: anytype, rhs: anytype) SumType(T, @TypeOf(lhs), @TypeOf(rhs)) {
            const Sum = SumType(T, @TypeOf(lhs), @TypeOf(rhs));

            const lhs_value_type: ValueType = .of(@TypeOf(lhs));
            _ = lhs_value_type; // autofix
            const rhs_value_type: ValueType = .of(@TypeOf(rhs));
            _ = rhs_value_type; // autofix

            const sum_value_type: ValueType = .of(Sum);

            switch (sum_value_type) {
                .rotor => {
                    if (@TypeOf(lhs) == @TypeOf(rhs) and @TypeOf(lhs) == Self) {
                        return .fromComponents(lhs.toComponents().add(rhs.toComponents()));
                    }

                    const lhs_val = Self.cast(lhs);

                    return .add(lhs_val, Self.cast(rhs));
                },
                else => comptime unreachable,
            }
        }

        pub fn sub(lhs: Self, rhs: Self) Self {
            return lhs.add(rhs.negate());
        }

        ///Multiply lhs by rhs
        pub fn mul(lhs: anytype, rhs: anytype) ProductType(@TypeOf(lhs), @TypeOf(rhs)) {
            const Prod = ProductType(@TypeOf(lhs), @TypeOf(rhs));
            const prod_value_type: ValueType = .of(Prod);

            const lhs_val: Self = .cast(lhs);
            const rhs_val: Self = .cast(rhs);

            switch (prod_value_type) {
                .rotor => {
                    switch (dim) {
                        0 => return .{},
                        1 => return lhs_val.a * rhs_val.a,
                        2 => {
                            return .{
                                .a = lhs_val.a * rhs_val.a - lhs_val.x * rhs_val.x,
                                .x = lhs_val.a * rhs_val.x + lhs_val.x * lhs_val.x * rhs_val.a,
                            };
                        },
                        3 => {
                            var result: Self = undefined;

                            result.a = lhs_val.a * rhs_val.a + lhs_val.vector().inner(rhs_val.vector());
                            const lhs_v = lhs_val.vector();
                            const rhs_v = rhs_val.vector();

                            result.vectorPtr().* = rhs_v.scale(lhs_val.a).add(lhs_v.scale(rhs_val.a)).add(
                                .fromComponents(lhs_v.outer(rhs_v).toComponents()),
                            );

                            return result;
                        },
                        else => comptime unreachable,
                    }
                },
                .vector => {
                    return .cast(mul(lhs, Self.cast(rhs)));
                },
                else => @compileError(""),
            }
        }

        ///Return the conjugate of the rotor (r*)
        pub fn conjugate(rotor: Self) Self {
            var result: Self = rotor;

            result.vectorPtr().* = result.vector().negate();

            return result;
        }

        pub fn square(rotor: Self) T {
            return rotor.toComponents().square();
        }

        pub fn norm(rotor: Self) T {
            return @sqrt(rotor.square());
        }

        ///Compute the multiplicative inverse
        pub fn inverse(rotor: Self) Self {
            return rotor.conjugate().scale(reciprocal(rotor.square()));
        }

        ///Divide lhs by rhs
        pub fn div(lhs: Self, rhs: Self) Self {
            return .mul(lhs, rhs.inverse());
        }

        pub const zero: Self = .fromComponents(.zero);

        pub const identity: Self = .one;

        pub const n: comptime_int = blk: {
            break :blk switch (dim) {
                0 => 0,
                1 => 1,
                2 => 2,
                3 => 4,
                else => unreachable,
            };
        };

        pub const one: Self = .{ .a = 1 };
        pub const i: Self = .{ .x = 1 };
        pub const j: Self = .{ .y = 1 };
        pub const k: Self = .{ .z = 1 };

        const Self = @This();
    };
}

///Represents a multor (or multivector) in dimension N
pub fn Multor(comptime T: type, dim: comptime_int) type {
    return extern struct {
        scalar_comp: T,
        vector_comp: Vec(T, dim),
        bivector_comp: Bivec(T, dim),

        ///Return the scalar part of the multor
        pub fn scalar(self: Self) T {
            return self.scalar_comp;
        }

        ///Return the vector part of the multor
        pub fn vector(self: Self) Vec(T, dim) {
            return self.vector_comp;
        }

        ///Return the bivector part of the multor
        pub fn bivector(self: Self) Bivec(T, dim) {
            return self.bivector_comp;
        }

        ///Compute the sum of lhs and rhs
        pub fn add(lhs: Self, rhs: Self) Self {
            var res: Self = undefined;

            res.scalar_comp = lhs.scalar_comp + rhs.scalar_comp;
            res.vector_comp = .add(lhs.vector_comp, rhs.vector_comp);
            res.bivector_comp = .add(lhs.bi_vector_comp, rhs.bivector_comp);

            return res;
        }

        ///Subtract rhs from lhs
        pub fn sub(lhs: Self, rhs: Self) Self {
            return lhs.add(rhs.negate());
        }

        pub fn mul(lhs: Self, rhs: Self) Self {
            _ = lhs; // autofix
            _ = rhs; // autofix
        }

        ///Scale the multor by rhs
        pub fn scale(lhs: Self, rhs: T) Self {
            var result: Self = lhs;

            result.scalar_comp = lhs.scalar_comp * rhs;
            result.vector_comp = lhs.vector_comp.scale(rhs);
            result.bivector_comp = lhs.bivector_comp.scale(rhs);

            return result;
        }

        ///Negate lhs
        pub fn negate(lhs: Self) Self {
            return lhs.scale(-1);
        }

        pub const n: comptime_int = blk: {
            break :blk switch (dim) {
                2 => 1,
                3 => 3,
                else => @compileError("Multor dim not supported!"),
            };
        };

        const Self = @This();
    };
}

///Represents an mxn matrix over T
pub fn Matrix(comptime T: type, m: comptime_int, comptime n: comptime_int) type {
    return extern struct {
        coeffs: [m * n]T,

        pub const identity: Self = blk: {
            var coeffs: [m * n]T = @splat(0);

            for (0..n) |j| {
                coeffs[j] = 1;
            }

            break :blk .{ .coeffs = coeffs };
        };

        ///Add two matrices and return the result
        pub fn add(lhs: Self, rhs: Self) Self {
            var coeffs: [m * n]T = undefined;

            for (&coeffs, lhs.coeffs, rhs.coeffs) |*res, a, b| {
                res.* = a + b;
            }

            return .{ .coeffs = coeffs };
        }

        pub fn row(lhs: Self, i: usize) Vec(m, T) {
            return .fromComponents(.fromArray(lhs.coeffs[i * m .. i * m + m].*));
        }

        pub fn column(lhs: Self, j: usize) Vec(n, T) {
            var coeffs: [n]T = undefined;

            for (0..n) |i| {
                coeffs[i] = lhs.row(i).componentAt(j);
            }

            return .fromComponents(.fromArray(coeffs));
        }

        ///Returns the columns of the matrix
        pub fn columns(lhs: Self) [m]Vec(n, T) {
            var cols: [n]Vec(n, T) = undefined;

            for (0..m) |j| {
                cols[j] = lhs.column(j);
            }

            return cols;
        }

        ///Returns the rows of the matrix
        pub fn rows(lhs: Self) [m]Vec(n, T) {
            return @bitCast(lhs.coeffs);
        }

        ///Computes the transpose of the matrix
        pub fn transpose(matrix: Self) Self {
            return @bitCast(matrix.columns());
        }

        ///Multiply two matricies and return the result
        pub fn mul(lhs: Self, rhs: Self) Self {
            var coeffs: [m * n]T = undefined;

            inline for (0..n) |i| {
                inline for (0..m) |j| {
                    coeffs[i * j] = lhs.row(j).inner(rhs.column(i));
                }
            }

            return .{ .coeffs = coeffs };
        }

        pub fn mulVec(lhs: Self, rhs: Vec(T, n)) Vec(T, n) {
            var coeffs: [n]T = undefined;

            inline for (0..m) |j| {
                coeffs[j] = lhs.row(j).inner(rhs);
            }

            return .{ .coeffs = coeffs };
        }

        pub fn det(a: Self) T {
            _ = a; // autofix
        }

        pub fn inverse(a: Self) Self {
            _ = a; // autofix

        }

        pub const value_type: ValueType = .matrix;

        const Self = @This();
    };
}

///Represents an affine transform in dimension N with unfiform scaling
pub fn AffineTransform(comptime T: type, dim: comptime_int) type {
    return extern struct {
        translation: Vec(dim, T),
        scale: T,
        rotation: Rotor(dim, T),

        pub fn inverse(transform: Self) Self {
            return .{
                .translation = .neg(transform.translation),
                .scale = reciprocal(T, transform.scale),
                .rotation = transform.rotation.inverse(),
            };
        }

        ///Compute the composition of lhs and rhs
        pub fn mul(lhs: Self, rhs: Self) Self {
            const translation = lhs.translation + lhs.rotation.mulVec(rhs.translation);
            const scale = lhs.scale * rhs.scale;
            const rotation = .mul(lhs.rotation, rhs.rotation);

            return .{
                .translation = translation,
                .scale = scale,
                .rotation = rotation,
            };
        }

        pub const identity: Self = .{
            .position = .{},
            .scale = 1,
            .rotation = .identity,
        };

        pub const value_type: ValueType = .affine_transform;

        const Self = @This();
    };
}

///Represents an affine transrform in dimension N with non-uniform scaling
pub fn AffineTransformNonUniform(comptime T: type, dim: comptime_int) type {
    return extern struct {
        translation: Vec(dim, T),
        scale: Vec(dim, T),
        rotation: Rotor(dim, T),

        ///Compute the composition of lhs and rhs
        pub fn mul(lhs: Self, rhs: Self) Self {
            const translation = lhs.translation + lhs.rotation.mulVec(rhs.translation.hadamard(lhs.scale));
            const scale = lhs.scale.hadamard(rhs.scale);
            const rotation = .mul(lhs.rotation, rhs.rotation);

            return .{
                .translation = translation,
                .scale = scale,
                .rotation = rotation,
            };
        }

        pub const identity: Self = .{
            .position = .{},
            .scale = 1,
            .rotation = .identity,
        };

        const Self = @This();
    };
}

pub const AngleType = enum {
    ///Angle represented by the range [0, 1]
    turns,
    ///Angle represented by the range [0. 2π]
    radians,
    ///Angle represented by the range [0, 360]
    degrees,
};

pub fn turns(value: anytype) Angle(@TypeOf(value), .radians) {
    return .{ .value = value };
}

pub fn radians(value: anytype) Angle(@TypeOf(value), .radians) {
    return .{ .value = value };
}

pub fn degrees(value: anytype) Angle(@TypeOf(value), .degrees) {
    return .{ .value = value };
}

pub fn AnyAngle(comptime T: type) type {
    return struct {
        value: T,
        comptime tag: AngleType = .radians,

        pub const zero: Self = .{ .value = 0 };

        pub fn turns(value: anytype) Self {
            return .{ .value = value, .tag = .turns };
        }

        pub fn radians(value: anytype) Self {
            return .{ .value = value, .tag = .radians };
        }

        pub fn degrees(value: anytype) Self {
            return .{ .value = value, .tag = .degrees };
        }

        const Self = @This();
    };
}

///Represents the ratio of the unit arc length between two vectors and the arc of a unit circle
pub fn Angle(comptime T: type, comptime angle_tag: AngleType) type {
    return struct {
        value: T,

        pub fn add(lhs: Self, rhs: Self) Self {
            return .{ .value = lhs.value + rhs.value };
        }

        pub fn sub(lhs: Self, rhs: Self) Self {
            return .{ .value = lhs.value - rhs.value };
        }

        pub fn mul(lhs: Self, rhs: Self) Self {
            return .{ .value = lhs.value * rhs.value };
        }

        pub fn div(lhs: Self, rhs: Self) Self {
            return .{ .value = lhs.value / rhs.value };
        }

        pub fn scale(lhs: Self, scalar: T) Self {
            return .{ .value = lhs.value * scalar };
        }

        ///Maps from [0, inf) -> [0, one_turn]
        pub fn wrap(angle: Self) Self {
            var angle_turns = angle.inTurns();

            angle_turns = angle_turns - @floor(angle_turns);

            return .cast(tag, turns(angle_turns));
        }

        pub fn inRadians(self: Self) T {
            return switch (angle_tag) {
                .radians => self.value,
                .turns => self.value * std.math.tau,
                .degrees => self.inTurns() * std.math.tau,
            };
        }

        pub fn inTurns(self: Self) T {
            return switch (angle_tag) {
                .radians => self.value * reciprocal(T, scalarConstant(T, std.math.tau)),
                .turns => self.value,
                .degrees => self.value * reciprocal(T, scalarConstant(T, 360.0)),
            };
        }

        pub fn inDegrees(self: Self) T {
            return self.inTurns() * scalarConstant(T, 360.0);
        }

        pub fn cast(to_tag: AngleType, self: Self) Angle(T, to_tag) {
            switch (to_tag) {
                .radians => self.inRadians(),
                .turns => self.inTurns(),
                .degrees => self.inDegrees(),
            }
        }

        pub const tag: AngleType = angle_tag;

        pub const zero: Self = .{ .value = 0 };
        pub const one_turn: Self = .cast(tag, turns(1));

        pub const value_type: ValueType = .angle;

        const Self = @This();
    };
}

///A rational number
pub fn Rational(comptime T: type) type {
    return packed struct {
        a: T,
        b: T,

        pub fn add() Self {
            return undefined;
        }

        pub fn sub() Self {
            return undefined;
        }

        pub fn mul() Self {
            return undefined;
        }

        pub fn div() Self {
            return undefined;
        }

        const Self = @This();
    };
}

///The set theory module
pub const set = struct {};

///The algebra module
pub const alg = struct {
    ///Evaluates an algebraic expression
    ///Can perform dimensional analysis verification and algebraic expansion
    /////Use the SI unit dimension and abbreviations
    ///using phys.si.abreviations;
    ///m := phys.si.units.metres;
    ///L := phys.si.dims.Length;
    ///s := phys.si.seconds;
    ///T := phys.si.dims.Time;
    ///
    /////units act like algebraic expressions, and can be combined (juxtaposed) just like variables
    ///
    ///x0 := 5m; // (x0 is given the value of 5 metres, and therefore )
    ///x = 5m => x : R(L); //holds (if x = 5m then x is an element of R with dimension Length)
    ///
    ///x : R(L); //this is an assertion/statement that x is an element of R(L) (and it holds)
    ///
    ///s^2 = s*s; //(an expression that will be verified, compile error if false)
    ///R = R(any)[any] //R is an alias for Reals with any dimension and any representation
    ///func f(x: R, y: R) := x^2 + xy + 1;
    ///func f((x, y): R^2) := x^2 + 2xy + 1;
    ///func f((x, i): R x Z) := x^2 + x^i;
    ///
    /////types are sets
    /////Define a pair type
    ///P := C x R;
    ///P = C x R; //Pairs are not distinct
    ///P_d := distinct(C x R); //The distinct operator makes a set distinct from another set
    ///P_d != P; //compiles
    ///
    ///// A set can have each element associated with a dimension (or unit)
    /// S := R(m) //S is a set of real values with dimension m (metres)
    /// S != R //this holds
    ///
    /// A set can also have a representation (a repr)
    /// S_0 := R[f32];
    /// S_1 := R(m)[f32]; //A set can have both a dimension with it and a repr associated with it
    /// S_0 != S_1 // this holds
    /// R = R[any] //The type/set R is essentially R over the 'any' repr (basically like anytype in zig)
    /////This function takes two sets and returns its' cartesian product (the pair set of X and Y)
    ///func Type(X: Set, Y: Set) -> Set := X x Y;
    /////While procedures can evaluate functions, functions cannot call procedures
    ///proc f(x: C, y: R) := {
    /// var x := 2;
    /// x := 3; //variables can be reassigned (only allowed in procedures)
    /// //As well as variables procedures can use if statements, loops and matches
    /// (x+1)^2 = x^2 + 2x + 1 //holds
    ///
    /// int(x)[c: R] = 1/2(x^2) + c //holds
    /// if (x = 3) {
    ///     x := 4;
    /// }
    /// else {
    ///     x := 5;
    /// }
    /// var some_var: Z[i32][3...3] = 3;
    ///
    /// *some_var^ := 3;
    ///
    /// some_var := 6; //some_var Z[i32][6..6]
    ///
    /// var ptr: Z[i32]^ = *some_var^;
    ///
    /// val := ^*ptr;
    ///
    /// x := match x {
    ///     3 => 4,
    ///     else => 5,
    /// };
    ///};
    /////Arrays and vectors:
    /// A = [2]R //array of reals
    /// V_0 := V(2, R) //2 dimensional vector space over the reals
    /// A != V_0 //holds
    /// f : differentiable => f' : integrable //holds
    /// v: V(3, R) := xe0 + ye1 + ze2; //vectors can be constructed from pairs or from the standard orthonormal basis {e0, e1, e2..e[n]..}
    /// v0: V(3, R) := (x, y, z); //pairs coerce to vectors and vice versa
    ///
    /// Set coercion:
    /// //V(S, n) -> S^n
    /// //R[repr] -> R.
    /// //N -> Z -> Q -> R
    ///
    /// //Algebraic operations:
    ///
    /// //int(f) (compute the indefinite integral of f (f must be a function that is provably integrable))
    /// //grad(f) (compute the derivative of f (f must be provably differentiable)
    /// eval[R[f32]] f(2)
    ///integer_func(x: Z) := x;
    ///rat_func(x: Q) := x / 2;
    ///avgvel(d: V(2, R(m)) t: R(s)) -> V(2, R(m/s)) := d / t;
    ///piecewise(x: R) -> R := { x : x < 2, -x : x >= 2 };
    pub fn evalComptime(
        alg_string: []const u8,
    ) void {
        _ = alg_string; // autofix

    }
};

///The geometry module
pub const geo = struct {
    ///Represents a box over T of dimension dim
    pub fn Box(comptime T: type, comptime dim: usize) type {
        return extern struct {
            ///The extents of the box in the x axis
            x: ComponentScalar(T, 0, dim),
            ///The extents of the box in the y axis
            y: ComponentScalar(T, 1, dim),
            ///The extents of the box in the z axis
            z: ComponentScalar(T, 2, dim),
            ///The extents of the box in the w axis
            w: ComponentScalar(T, 3, dim),
        };
    }
};

pub const numeric = struct {
    ///Converts a float to a fixed point number
    pub fn quantiseFloat(comptime Integer: type, comptime Float: type, float: Float) Integer {
        _ = float; // autofix
    }
};

///The clifford algebra module
pub const cliff = struct {};

///The analysis module
pub const analysis = struct {};

///The trigonometry module
pub const trig = struct {
    ///Returns the cosine of angle
    pub fn cos(comptime T: type, angle: anytype) T {
        return @cos(angle.inRadians());
    }

    ///Returns the sin of angle
    pub fn sin(comptime T: type, angle: anytype) T {
        return @sin(angle.inRadians());
    }

    ///Returns the rotor (sin(angle), cos(angle))
    pub fn euler(comptime T: type, angle: anytype) Rotor(2, T) {
        //TODO: compute sin and cos together
        return .{
            .a = cos(T, angle),
            .x = sin(T, angle),
        };
    }
};

///Returns the type that should be returns when multiplying values of type Lhs, and Rhs respectively
pub fn ProductType(
    comptime Lhs: type,
    comptime Rhs: type,
) type {
    const lhs_type: ValueType = .of(Lhs);
    const rhs_type: ValueType = .of(Rhs);

    if (Lhs == Rhs) {
        return Lhs;
    }

    if (lhs_type == .rotor and rhs_type == .rotor) {
        return Rhs;
    }

    if (lhs_type == .rotor and rhs_type == .vector) {
        return Rhs;
    }

    if (lhs_type == .matrix and rhs_type == .vector) {
        return Vec(ValueType.dim(Rhs), ValueType.FieldType(Rhs));
    }

    if (lhs_type == .vector and rhs_type == .vector) {
        return Rotor(ValueType.dim(Rhs), ValueType.FieldType(Rhs));
    }

    if (lhs_type == .vector and rhs_type == .scalar) {
        return Lhs;
    }

    if (lhs_type == .scalar and rhs_type == .vector) {
        return Rhs;
    }

    if (lhs_type == .vector and rhs_type == .decl_literal) {
        return Rotor(ValueType.dim(Lhs), ValueType.FieldType(Lhs));
    }

    return Lhs;
}

///Returns the type that should be returns when adding values of type Lhs, and Rhs respectively
pub fn SumType(
    comptime Scalar: type,
    comptime Lhs: type,
    comptime Rhs: type,
) type {
    const lhs_type: ValueType = .of(Lhs);
    const rhs_type: ValueType = .of(Rhs);

    if (lhs_type == rhs_type) {
        return Rhs;
    }

    if (lhs_type == .scalar and rhs_type == .rotor) {
        return Rhs;
    }

    if (lhs_type == .scalar and rhs_type == .decl_literal) {
        return Rotor(2, Scalar);
    }

    return Lhs;
}

const math = @This();
const std = @import("std");
