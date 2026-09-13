io: std.Io,
gpa: std.mem.Allocator,
module_path: []const u8,
modules: std.ArrayList(Compiler.ModuleEntry) = .empty,
pipelines: std.ArrayList(Compiler.PipelineEntry) = .empty,

pub fn compiler(self: *IoCompiler) Compiler {
    return .{
        .vtable = &.{
            .addModuleFile = &addModuleFile,
            .compileRasterVertexPipeline = &defaultCompileRasterVertexPipeline,
            .compileComputePipeline = &defaultCompileComputePipeline,
            .freePipeline = &defaultFreePipeline,
        },
        .ptr = self,
        .pipelines = &self.pipelines.items,
        .modules = &self.modules.items,
    };
}

pub fn addModuleFile(
    ptr: *anyopaque,
    module_path: []const u8,
) !Compiler.ModuleIndex {
    const self: *IoCompiler = @ptrCast(@alignCast(ptr));

    const contents = try std.Io.Dir.cwd().readFileAlloc(
        self.io,
        module_path,
        self.gpa,
        .unlimited,
    );

    const module_index: Compiler.ModuleIndex = @fromBackingInt(@intCast(self.modules.items.len));

    try self.modules.append(self.gpa, .{
        .contents = contents,
        .file_path = module_path,
    });

    return module_index;
}

pub fn defaultCompileRasterVertexPipeline(
    ptr: *anyopaque,
    exported: gpu.kernel.ExportedRasterPipeline,
    description: gpu.RasterPipelineDescription,
) !PipelineIndex {
    const self: *IoCompiler = @ptrCast(@alignCast(ptr));

    const module_index: Compiler.PipelineIndex = @fromBackingInt(@intCast(self.pipelines.items.len));

    const pipeline = try self.pipelines.addOne(
        self.gpa,
    );

    _ = self.io.async(compileRasterVertexPipeline, .{
        self,
        exported,
        description,
        pipeline,
    });
    pipeline.pipeline = null;
    pipeline.description = .{ .raster_vertex = .{
        .description = description,
        .exported = exported,
    } };

    return module_index;
}

fn compileRasterVertexPipeline(
    self: *IoCompiler,
    exported: gpu.kernel.ExportedRasterPipeline,
    description: gpu.RasterPipelineDescription,
    result: *Compiler.PipelineEntry,
) void {
    var actual_description = description;
    actual_description.vertex_entry_point = exported.vertex_entry_point;
    actual_description.fragment_entry_point = exported.fragment_entry_point;

    const module_contents = self.modules.items[0].contents;

    result.pipeline = gpu.createRasterVertexPipeline(
        module_contents,
        module_contents,
        actual_description,
    );
}

pub fn defaultCompileComputePipeline(
    ptr: *anyopaque,
    exported: gpu.kernel.ExportedComputePipeline,
) !PipelineIndex {
    const self: *IoCompiler = @ptrCast(@alignCast(ptr));
    _ = exported; // autofix
    const result = try self.pipelines.addOne(std.heap.page_allocator);

    result.pipeline = gpu.createComputePipeline(
        @embedFile("main.spv"),
    );

    return undefined;
}

pub fn defaultFreePipeline(
    ptr: *anyopaque,
    pipeline: PipelineIndex,
) void {
    const self: *IoCompiler = @ptrCast(@alignCast(ptr));
    _ = compiler; // autofix
    gpu.freePipeline(self.compiler().getPipeline(pipeline).?);
}

const PipelineIndex = Compiler.PipelineIndex;
const Compiler = gpu.pipelines.Compiler;
const Pipeline = gpu.Pipeline;
const std = @import("std");
const gpu = @import("../../gpu.zig");
const IoCompiler = @This();
