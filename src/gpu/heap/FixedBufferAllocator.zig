end_index: usize,
buffer: []u8,

pub fn init(
    buffer: []u8,
) FixedBufferAllocator {
    return .{
        .end_index = 0,
        .buffer = buffer,
    };
}

pub fn allocator(self: *FixedBufferAllocator) gpu.mem.Allocator {
    return .{
        .ptr = self,
        .vtable = &.{
            .alloc = &alloc,
            .free = &free,
            .resize = &resize,
            .remap = &remap,
        },
    };
}

pub fn alloc(
    ptr: *anyopaque,
    len: usize,
    alignment: std.mem.Alignment,
    memory_type: gpu.mem.Allocator.MemoryType,
    _: usize,
) ?[*]u8 {
    const fba: *FixedBufferAllocator = @ptrCast(@alignCast(ptr));

    if (gpu.mem.getMemoryType(fba.buffer) != memory_type) {
        return null;
    }

    const ptr_align = alignment.toByteUnits();
    const adjust_off = std.mem.alignPointerOffset(fba.buffer.ptr + fba.end_index, ptr_align) orelse return null;
    const adjusted_index = fba.end_index + adjust_off;
    const new_index = adjusted_index + len;

    if (new_index > fba.buffer.len) return null;

    fba.end_index = new_index;
    return fba.buffer.ptr + adjusted_index;
}

pub fn resize(
    _: *anyopaque,
    memory: []u8,
    alignment: std.mem.Alignment,
    memory_type: gpu.mem.Allocator.MemoryType,
    new_len: usize,
    _: usize,
) bool {
    _ = memory; // autofix
    _ = alignment; // autofix
    _ = memory_type; // autofix
    _ = new_len; // autofix
    return false;
}

pub fn remap(
    _: *anyopaque,
    memory: []u8,
    alignment: std.mem.Alignment,
    memory_type: gpu.mem.Allocator.MemoryType,
    new_len: usize,
    _: usize,
) ?[*]u8 {
    _ = memory; // autofix
    _ = alignment; // autofix
    _ = memory_type; // autofix
    _ = new_len; // autofix
    return null;
}

pub fn free(
    _: *anyopaque,
    memory: []u8,
    _: std.mem.Alignment,
    _: gpu.mem.Allocator.MemoryType,
    _: usize,
) void {
    _ = memory; // autofix
}

const FixedBufferAllocator = @This();
const std = @import("std");
const gpu = @import("../../gpu.zig");
