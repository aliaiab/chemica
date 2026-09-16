//! MTLBlitCommandEncoder wrapper using zig-objc

const objc = @import("../objc_minimal.zig");

const Buffer = @import("buffer.zig").MetalBuffer;

/// Metal blit encoder wrapper
pub const MetalBlitEncoder = struct {
    handle: objc.Object,

    pub fn deinit(self: *MetalBlitEncoder) void {
        self.handle.msgSend(void, objc.sel("release"), .{});
    }

    pub fn copyBuffer(self: *MetalBlitEncoder, src: *Buffer, dst: *Buffer, size: u32) void {
        self.handle.msgSend(
            void,
            objc.sel("copyFromBuffer:sourceOffset:toBuffer:destinationOffset:size:"),
            .{ src.handle, @as(c_ulong, 0), dst.handle, @as(c_ulong, 0), @as(c_ulong, size) },
        );
    }

    pub fn end(self: *MetalBlitEncoder) void {
        self.handle.msgSend(void, objc.sel("endEncoding"), .{});
    }
};
