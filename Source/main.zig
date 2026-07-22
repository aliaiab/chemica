extern fn cppMain(argc: c_int, argv: [*][*]const u8) void;

export const embedded_environment_map = @embedFile("Assets/vintage_measuring_lab_2k.png");
export const embedded_environment_map_length = embedded_environment_map.len;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    const argv = try arena.alloc([*]const u8, args.len);

    for (argv, args) |*argv_arg, arg| {
        argv_arg.* = arg.ptr;
    }

    cppMain(@intCast(args.len), argv.ptr);
}

const std = @import("std");
