//! MTLBuffer wrapper using zig-objc

const std = @import("std");
const objc = @import("../objc_minimal.zig");

/// Metal Buffer wrapper
pub const MetalBuffer = struct {
    handle: objc.Object,
    len: u32,

    pub fn deinit(self: *MetalBuffer) void {
        self.handle.msgSend(void, objc.sel("release"), .{});
    }

    /// Get direct pointer to buffer contents (for shared storage mode)
    pub fn getContents(self: *MetalBuffer) ?[]u8 {
        const ptr = self.handle.msgSend(?*anyopaque, objc.sel("contents"), .{}) orelse return null;
        const bytes: [*]u8 = @ptrCast(@alignCast(ptr));
        return bytes[0..self.len];
    }

    /// Get buffer contents as typed slice
    pub fn getContentsAs(self: *MetalBuffer, comptime T: type) ?[]T {
        const bytes = self.getContents() orelse return null;
        return @alignCast(std.mem.bytesAsSlice(T, bytes));
    }

    /// Upload data to buffer (copies from CPU to GPU)
    pub fn upload(self: *MetalBuffer, data: []const u8) void {
        const contents = self.getContents() orelse return;
        @memcpy(contents[0..data.len], data);
    }

    /// Download data from buffer (copies from GPU to CPU)
    pub fn download(self: *MetalBuffer, data: []u8) void {
        const contents = self.getContents() orelse return;
        @memcpy(data, contents[0..data.len]);
    }
};
