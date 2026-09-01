descriptors: []gpu.TextureDescriptor,
sampler_descriptors: []gpu.TextureDescriptor,

pub fn init(
    descriptor_allocator: gpu.mem.Allocator,
    sampler_descriptor_allocator: gpu.mem.Allocator,
) RendererImGui {
    _ = sampler_descriptor_allocator; // autofix
    _ = descriptor_allocator; // autofix
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
