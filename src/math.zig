pub fn mulQuat(a: @Vector(4, f32), b: @Vector(4, f32)) @Vector(4, f32) {
    var result: @Vector(4, f32) = undefined;

    const lhs_w: @Vector(4, f32) = @splat(a[3]);
    const rhs_w: @Vector(4, f32) = @splat(b[3]);

    result = lhs_w * b + rhs_w * a - zmath.cross3(a, b);

    result[3] = a[3] * b[3] - zmath.dot3(a, b)[0];

    return result;
}

///Compute the nth root of x
pub fn rootn(comptime T: type, x: T, n: T) T {
    return @exp((1.0 / n) * @log(x));
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

///Represents a linear algebra vector of dimension N
pub fn Vec(comptime T: type, dim: comptime_int) type {
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
        pub fn pow(vector: Self, k: T) T {
            _ = vector; // autofix
            _ = k; // autofix
            //TODO: implement pow
            unreachable;
        }

        ///Compute the euclidean 2-norm of vector
        pub fn norm(vector: Self) T {
            return @sqrt(vector.square());
        }

        ///Compute the euclidean k-norm of vector
        pub fn knorm(vector: Self, k: usize) T {
            return rootn(vector.pow(k));
        }

        ///Computes the inner product of lhs and rhs
        pub fn inner(lhs: Self, rhs: Self) T {
            return lhs.toComponents().inner(rhs.toComponents());
        }

        ///Computes the outer product of lhs and rhs
        pub fn outer(lhs: Self, rhs: Self) Bivec(T, dim) {
            _ = lhs; // autofix
            _ = rhs; // autofix
        }

        ///Computes the hadamard product of lhs and rhs
        pub fn hadamard(lhs: Self, rhs: Self) Self {
            return .fromComponents(lhs.toComponents().hadamard(rhs.toComponents()));
        }

        ///Computes the grassmann product of lhs and rhs
        pub fn mul(lhs: Self, rhs: Self) Rotor(T, dim) {
            var result: Rotor(T, dim) = undefined;

            result.w = lhs.inner(rhs);
            result.vectorPtr().* = lhs.outer(rhs).vector();

            return result;
        }

        ///Returns the conjugate of the vector
        pub inline fn conjugate(vector: Self) Self {
            return vector;
        }

        ///Compute the multiplicative inverse
        pub fn inverse(vector: Self) Self {
            return vector.conjugate().scale(reciprocal(vector.square()));
        }

        const Self = @This();
    };
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
        pub fn vector(bivector: Self) Vec(T, n) {
            return .fromComponents(bivector.toComponents());
        }

        pub const n: comptime_int = blk: {
            break :blk switch (dim) {
                0 => 0,
                1 => 1,
                2 => 1,
                3 => 3,
                else => unreachable,
            };
        };

        const Self = @This();
    };
}

///Alias for a Rotor(T, 2)
pub fn Complex(comptime T: type) type {
    return Rotor(T, 2);
}

///Alias for Rotor(T, 3)
pub fn Quaternion(comptime T: type) type {
    //TODO: add rotor handedness
    return Rotor(T, 3);
}

///Storage for a named component (x, y, z, w, ect..)
pub fn ComponentScalar(comptime T: type, i: comptime_int, dim: comptime_int) type {
    if (i >= dim) {
        return u0;
    }

    return T;
}

comptime {
    std.debug.assert(@sizeOf(ComponentScalar(f32, 3, 3)) == 0);
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

            array[0] = self.x;
            array[1] = self.y;
            array[2] = self.z;
            array[3] = self.w;

            if (dim > 4) {
                @memcpy(array[4..], &self.trailing.values);
            }

            return array;
        }

        pub fn fromArray(array: [dim]T) Self {
            var self: Self = undefined;

            self.x = array[0];
            self.y = array[1];
            self.z = array[2];
            self.w = array[3];

            if (dim > 4) {
                @memcpy(&self.trailng.values, array[4..]);
            }

            return self;
        }

        pub fn xyzw(self: Self) Vec(T, 4) {
            return .{ .x = self.x, .y = self.y, .z = self.z, .w = self.w };
        }

        pub fn yxwz(self: Self) Vec(T, 4) {
            return .{ .x = self.y, .y = self.x, .z = self.w, .w = self.z };
        }

        pub fn wzyx(self: Self) Vec(T, 4) {
            return .{ .x = self.w, .y = self.z, .z = self.y, .w = self.x };
        }

        pub fn xxy(self: Self) Vec(T, 3) {
            return .{ .x = self.x, .y = self.x, .z = self.y };
        }

        pub fn yxx(self: Self) Vec(T, 3) {
            return .{ .x = self.y, .y = self.x, .z = self.x };
        }

        pub fn xyz(self: Self) Vec(T, 3) {
            return .{ .x = self.x, .y = self.y, .z = self.z };
        }

        pub fn xzy(self: Self) Vec(T, 3) {
            return .{ .x = self.x, .y = self.z, .z = self.y };
        }

        pub fn zyx(self: Self) Vec(T, 3) {
            return .{ .x = self.z, .y = self.y, .z = self.x };
        }

        pub fn yzx(self: Self) Vec(T, 3) {
            return .{ .x = self.y, .y = self.z, .z = self.x };
        }

        pub fn xy(self: Self) Vec(T, 2) {
            return .{ .x = self.x, .y = self.y };
        }

        pub fn xx(self: Self) Vec(T, 2) {
            return .{ .x = self.x, .y = self.x };
        }

        pub fn yx(self: Self) Vec(T, 2) {
            return .{ .x = self.y, .y = self.x };
        }

        pub fn yy(self: Self) Vec(T, 2) {
            return .{ .x = self.y, .y = self.y };
        }

        ///Add lhs and rhs
        pub fn add(lhs: Self, rhs: Self) Self {
            var result: Self = undefined;

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

            result += lhs.x * rhs.x;
            result += lhs.y * rhs.y;
            result += lhs.z * rhs.z;
            result += lhs.w * rhs.w;
            result += .dot(lhs.trailing, rhs.trailing);

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

            result.x = lhs.x * rhs.x;
            result.y = lhs.y * rhs.y;
            result.z = lhs.z * rhs.z;
            result.w = lhs.w * rhs.w;
            result.trailing = lhs.trailing.hadamard(rhs.trailing);

            return result;
        }

        const Self = @This();
    };
}

///Represents a clifford algebra rotor in dimension N
///Rotor(T, 2) == Complex number
///Rotor(T, 3) == Negative quaternion
pub fn Rotor(comptime T: type, dim: comptime_int) type {
    return extern struct {
        w: ComponentScalar(T, 0, n) = 0,
        x: ComponentScalar(T, 1, n) = 0,
        y: ComponentScalar(T, 2, n) = 0,
        z: ComponentScalar(T, 3, n) = 0,
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

        ///Returns the real part of the rotor (the scalar part)
        pub fn real(self: Self) T {
            return self.w;
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

        ///Returns the vector part of the rotor
        pub fn vector(self: Self) Vec(T, dim) {
            if (dim <= 2) {
                @compileError("Rotors of dimension 2 or less don't have a vector part");
            }

            return .{ .coeffs = .{ self.x, self.y, self.z } };
        }

        ///Returns the vector part of the rotor
        pub fn vectorPtr(self: Self) *Vec(T, dim) {
            if (dim <= 2) {
                @compileError("Rotors of dimension 2 or less don't have a vector part");
            }

            return @ptrCast(&self.x);
        }

        ///Returns the rotor represented by the axis and an angle of rotation
        pub fn axisAngle(angle: anytype, axis: Vec(T, dim)) Self {
            const sin_cos = trig.sinAndCos(T, angle);
            var result: Self = .{ .w = sin_cos.y };

            result.vectorPtr().* = axis.scale(sin_cos.x);

            return result;
        }

        ///Scale the rotor by rhs
        pub fn scale(lhs: Self, rhs: T) Self {
            return .fromComponents(lhs.toComponents().scale(rhs));
        }

        ///Negate the rotor
        pub fn negate(lhs: Self) Self {
            return lhs.scale(-1);
        }

        pub fn add(lhs: Self, rhs: Self) Self {
            return .fromComponents(lhs.toComponents().add(rhs));
        }

        pub fn sub(lhs: Self, rhs: Self) Self {
            return lhs.add(rhs.negate());
        }

        ///Multiply lhs by rhs
        pub fn mul(lhs: Self, rhs: Self) Self {
            switch (dim) {
                0 => return .{},
                1 => return lhs.w * rhs.w,
                2 => {
                    return .{
                        .w = lhs.w * rhs.w - lhs.x * rhs.x,
                        .x = lhs.w * rhs.x + lhs.x * lhs.x * rhs.w,
                    };
                },
                3 => {
                    var result: Self = undefined;

                    result.w = lhs.w * rhs.w + lhs.vector().inner(rhs.vector());
                    const lhs_v = lhs.vector();
                    const rhs_v = rhs.vector();

                    result.vectorPtr().* = rhs_v.scale(lhs.w()).add(lhs_v.scale(rhs.w())).add(lhs_v.outer(rhs_v));

                    return result;
                },
            }
        }

        ///Return the conjugate of the rotor (r*)
        pub fn conjugate(rotor: Self) Self {
            var result: Self = rotor;

            result.vectorPtr().negate();

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

        ///Multiply rhs by lhs
        pub fn mulVec(lhs: Self, rhs: Vec(T, dim)) Vec(T, dim) {
            _ = lhs; // autofix
            _ = rhs; // autofix
        }

        pub const identity: Self = blk: {
            break :blk switch (dim) {
                0 => .{},
                1 => .{ .w = 1 },
                2 => .{ .w = 1, .x = 0 },
                3 => .{ .w = 1, .x = 0, .y = 0, .z = 0 },
                else => unreachable,
            };
        };

        pub const n: comptime_int = blk: {
            break :blk switch (dim) {
                0 => 0,
                1 => 1,
                2 => 2,
                3 => 4,
                else => unreachable,
            };
        };

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

        pub fn row(lhs: Self, i: usize) Vec(T, m) {
            return .{ .coeffs = lhs.coeffs[i * m .. i * m + m].* };
        }

        pub fn column(lhs: Self, j: usize) Vec(T, n) {
            var coeffs: [n]T = undefined;

            for (0..n) |i| {
                coeffs[i] = lhs.row(i).coeffs[j];
            }

            return .{
                .coeffs = coeffs,
            };
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

        const Self = @This();
    };
}

///Represents an affine transform in dimension N with unfiform scaling
pub fn AffineTransform(comptime T: type, dim: comptime_int) type {
    return extern struct {
        translation: Vec(T, dim),
        scale: T,
        rotation: Rotor(T, dim),

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

        const Self = @This();
    };
}

///Represents an affine transrform in dimension N with non-uniform scaling
pub fn AffineTransformNonUniform(comptime T: type, dim: comptime_int) type {
    return extern struct {
        translation: Vec(T, dim),
        scale: Vec(T, dim),
        rotation: Rotor(T, dim),

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
    return extern struct {
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

    ///Returns the vector (sin(angle), cos(angle))
    pub fn sinAndCos(comptime T: type, angle: anytype) Vec(T, 2) {
        //TODO: compute sin and cos together
        return .{
            .x = sin(T, angle),
            .y = cos(T, angle),
        };
    }
};

const zmath = @import("zmath");
const std = @import("std");
