io: std.Io,
child_compiler: gpu.pipelines.Compiler,
watcher: watchers.Watcher,
is_watching: bool = false,

pub fn init(
    io: std.Io,
    allocator: std.mem.Allocator,
    child_compiler: gpu.pipelines.Compiler,
) !WatchCompiler {
    return .{
        .io = io,
        .watcher = try .init(io, allocator),
        .child_compiler = child_compiler,
    };
}

pub fn startWatching(
    self: *WatchCompiler,
) !void {
    if (self.is_watching) return;

    self.watcher.setCallback(watcherCallback, self);

    _ = try self.io.concurrent(watcherThread, .{
        &self.watcher,
    });
    self.is_watching = true;
}

pub fn compiler(self: *WatchCompiler) gpu.pipelines.Compiler {
    return .{
        .vtable = &.{
            .addModuleFile = &addModuleFile,
            .compileRasterVertexPipeline = &compileRasterVertexPipeline,
            .compileComputePipeline = &compileComputePipeline,
            .freePipeline = &freePipeline,
        },
        .ptr = self,
        .modules = self.child_compiler.modules,
        .pipelines = self.child_compiler.pipelines,
    };
}

pub fn addModuleFile(
    ptr: *anyopaque,
    module_path: [:0]const u8,
) !gpu.pipelines.Compiler.ModuleIndex {
    const self: *WatchCompiler = @ptrCast(@alignCast(ptr));
    const module_index = try self.child_compiler.addModuleFile(module_path);
    try self.watcher.addFile(module_path);

    try self.startWatching();

    return module_index;
}

pub fn compileRasterVertexPipeline(
    ptr: *anyopaque,
    exported: gpu.kernel.ExportedRasterPipeline,
    description: gpu.RasterPipelineDescription,
) !PipelineIndex {
    const self: *WatchCompiler = @ptrCast(@alignCast(ptr));

    return self.child_compiler.compileRasterVertexPipeline(exported, description);
}

pub fn compileComputePipeline(
    ptr: *anyopaque,
    exported: gpu.kernel.ExportedComputePipeline,
) !PipelineIndex {
    const self: *WatchCompiler = @ptrCast(@alignCast(ptr));

    return self.child_compiler.compileComputePipeline(exported);
}

pub fn freePipeline(
    ptr: *anyopaque,
    pipeline: PipelineIndex,
) void {
    const self: *WatchCompiler = @ptrCast(@alignCast(ptr));

    self.child_compiler.freePipeline(pipeline);
}

fn watcherCallback(context: ?*anyopaque, path: [:0]const u8, event: watchers.Event) !void {
    const watcher_compiler: *WatchCompiler = @ptrCast(@alignCast(context.?));

    const module_index = watcher_compiler.child_compiler.getModuleFromPath(path).?;
    const contents = try std.Io.Dir.cwd().readFileAlloc(
        watcher_compiler.io,
        path,
        std.heap.page_allocator,
        .unlimited,
    );

    watcher_compiler.child_compiler.modules.*[@backingInt(module_index)].contents = contents;

    switch (event) {
        .modified => {
            for (watcher_compiler.child_compiler.pipelines.*) |*pipeline_entry| {
                switch (pipeline_entry.description) {
                    .raster_vertex => |raster_vertex| {
                        pipeline_entry.pipeline = immediateCompileRasterVertexPipeline(
                            watcher_compiler.compiler(),
                            raster_vertex.exported,
                            raster_vertex.description,
                        );
                    },
                    .compute => {},
                }
            }
        },
    }
}

fn immediateCompileRasterVertexPipeline(
    self: gpu.pipelines.Compiler,
    exported: gpu.kernel.ExportedRasterPipeline,
    description: gpu.RasterPipelineDescription,
) *gpu.Pipeline {
    var actual_description = description;
    actual_description.vertex_entry_point = exported.vertex_entry_point;
    actual_description.fragment_entry_point = exported.fragment_entry_point;

    const module_contents = self.modules.*[0].contents;

    return gpu.createRasterVertexPipeline(
        module_contents,
        module_contents,
        actual_description,
    );
}

fn watcherThread(watcher: *watchers.Watcher) !void {
    try watcher.start(.{});
}

const PipelineIndex = gpu.pipelines.Compiler.PipelineIndex;
const Pipeline = gpu.Pipeline;
const watchers = @import("../watchers.zig");
const gpu = @import("../../gpu.zig");
const std = @import("std");
const WatchCompiler = @This();
