//! MTLCommandQueue wrapper using zig-objc

const std = @import("std");
const objc = @import("../objc_minimal.zig");
const errors = @import("errors.zig");

pub const MetalError = errors.MetalError;

const CommandBuffer = @import("command_buffer.zig").MetalCommandBuffer;

/// Command queue for submitting GPU work
pub const MetalCommandQueue = struct {
    handle: objc.Object,

    pub fn deinit(self: *MetalCommandQueue) void {
        self.handle.msgSend(void, objc.sel("release"), .{});
    }

    /// Create command buffer for recording GPU commands
    pub fn createCommandBuffer(self: *MetalCommandQueue) MetalError!CommandBuffer {
        const buffer = self.handle.msgSend(objc.Object, objc.sel("commandBuffer"), .{});
        if (buffer.value == null) return MetalError.CommandBufferCreationFailed;

        // Retain the command buffer
        _ = buffer.msgSend(objc.Object, objc.sel("retain"), .{});

        return .{ .handle = buffer };
    }
};
