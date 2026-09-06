pub fn computeMain(
    params: start.ComputeCommandParameters,
) void {
    _ = params; // autofix
}

comptime {
    start.exportComputePipeline(.{
        .x = 8,
        .y = 8,
        .z = 8,
    });
}

const start = @import("shader_start");
