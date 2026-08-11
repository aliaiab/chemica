export fn main() callconv(.{ .spirv_fragment = .{} }) void {
    out_colour.* = @splat(1);

    var frag_coord = spirv.frag_coord;
    frag_coord -= @Vector(4, f32){ 1920.0 / 2.0, 1080.0 / 2.0, 0, 0 };

    out_colour.* = @splat(1);

    var pos = in.position;
    pos[3] = 0;

    const radius = 0.2;
    const frag_length = @reduce(.Add, pos * pos);
    
    if (frag_length <= radius * radius) {
        out_colour.* = @splat(0.8);
    } else {
        out_colour.* = @splat(0.3);
    }
}

const spirv = @import("std").spirv;

const out_colour = @extern(
    *addrspace(.output) @Vector(4, f32),
    .{
        .name = "out_colour",
        .decoration = .{
            .location = 0,
        },
    },
);

const in = @extern(
    *addrspace(.input) extern struct {
        position: @Vector(4, f32),
        colour: @Vector(4, f32),
    },
    .{
        .name = "in",
        .decoration = .{
            .location = 0,
        },
    },
);
