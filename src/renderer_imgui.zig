pub fn init(
    sampler_heap: []gpu.TextureDescriptor,
    sampler_allocator: gpu.mem.Allocator,
) RendererImGui {
    _ = sampler_allocator; // autofix
    _ = sampler_heap; // autofix
    const self: RendererImGui = .{};

    return self;
}

pub fn render(
    self: RendererImGui,
    command_buffer: *gpu.CommandBuffer,
    draw_data: *const imgui.DrawData,
    transient_arena: gpu.mem.Allocator,
) void {
    _ = self; // autofix
    _ = transient_arena; // autofix
    _ = command_buffer; // autofix
    _ = draw_data; // autofix
}

const std = @import("std");
const gpu = @import("gpu.zig");
const imgui = @import("imgui.zig");
const RendererImGui = @This();
