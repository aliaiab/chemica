//! MTLCommandBuffer wrapper using zig-objc

const std = @import("std");
const objc = @import("../objc_minimal.zig");
const errors = @import("errors.zig");

pub const MetalError = errors.MetalError;

const ComputeEncoder = @import("compute_encoder.zig").MetalComputeEncoder;
const RenderEncoder = @import("render_encoder.zig").MetalRenderEncoder;
const BlitEncoder = @import("blit_encoder.zig").MetalBlitEncoder;
const RenderPassDescriptor = @import("render_pass.zig").MetalRenderPassDescriptor;

/// Metal command buffer wrapper
pub const MetalCommandBuffer = struct {
    handle: objc.Object,

    pub fn deinit(self: *MetalCommandBuffer) void {
        self.handle.msgSend(void, objc.sel("release"), .{});
    }

    pub fn commit(self: *MetalCommandBuffer) void {
        self.handle.msgSend(void, objc.sel("commit"), .{});
    }

    pub fn waitForCompletion(self: *MetalCommandBuffer) void {
        self.handle.msgSend(void, objc.sel("waitUntilCompleted"), .{});
    }

    /// Schedule presentation of a drawable when command buffer completes
    pub fn present(self: *MetalCommandBuffer, drawable_ptr: ?*anyopaque) void {
        if (drawable_ptr) |ptr| {
            const drawable = objc.Object.fromId(ptr);
            self.handle.msgSend(void, objc.sel("presentDrawable:"), .{drawable});
        }
    }

    pub fn createComputeEncoder(self: *MetalCommandBuffer) MetalError!ComputeEncoder {
        const encoder = self.handle.msgSend(objc.Object, objc.sel("computeCommandEncoder"), .{});
        if (encoder.value == null) return MetalError.CommandBufferCreationFailed;

        _ = encoder.msgSend(objc.Object, objc.sel("retain"), .{});
        return .{ .handle = encoder };
    }

    pub fn createBlitEncoder(self: *MetalCommandBuffer) MetalError!BlitEncoder {
        const encoder = self.handle.msgSend(objc.Object, objc.sel("blitCommandEncoder"), .{});
        if (encoder.value == null) return MetalError.CommandBufferCreationFailed;

        _ = encoder.msgSend(objc.Object, objc.sel("retain"), .{});
        return .{ .handle = encoder };
    }

    pub fn createRenderEncoder(self: *MetalCommandBuffer, render_pass: *RenderPassDescriptor) MetalError!RenderEncoder {
        const encoder = self.handle.msgSend(
            objc.Object,
            objc.sel("renderCommandEncoderWithDescriptor:"),
            .{render_pass.handle},
        );
        if (encoder.value == null) return MetalError.CommandBufferCreationFailed;

        _ = encoder.msgSend(objc.Object, objc.sel("retain"), .{});
        return .{ .handle = encoder };
    }
};
