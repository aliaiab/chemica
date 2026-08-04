pub fn mulQuat(a: @Vector(4, f32), b: @Vector(4, f32)) @Vector(4, f32) {
    var result: @Vector(4, f32) = undefined;

    const lhs_w: @Vector(4, f32) = @splat(a[3]);
    const rhs_w: @Vector(4, f32) = @splat(b[3]);

    result = lhs_w * b + rhs_w * a - zmath.cross3(a, b);

    result[3] = a[3] * b[3] - zmath.dot3(a, b)[0];

    return result;
}

const zmath = @import("zmath");
