const root = @import("root");

comptime {
    if (@hasDecl(root, "vertexMain")) {}
}

fn _vertexMain() callconv(.spirv_vertex) void {}
