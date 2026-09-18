//! MTLComputeCommandEncoder wrapper using zig-objc

const objc = @import("../objc_minimal.zig");

const Pipeline = @import("pipeline.zig").MetalPipeline;
const Texture = @import("texture.zig").MetalTexture;
const Buffer = @import("buffer.zig").MetalBuffer;

/// Metal compute encoder wrapper
pub const MetalComputeEncoder = struct {
    handle: objc.Object,

    pub fn deinit(self: *MetalComputeEncoder) void {
        self.handle.msgSend(void, objc.sel("release"), .{});
    }

    pub fn setPipeline(self: *MetalComputeEncoder, pipeline: *Pipeline) void {
        self.handle.msgSend(void, objc.sel("setComputePipelineState:"), .{pipeline.handle});
    }

    pub fn setTexture(self: *MetalComputeEncoder, texture: *Texture, index: u32) void {
        self.handle.msgSend(
            void,
            objc.sel("setTexture:atIndex:"),
            .{ texture.handle, @as(c_ulong, index) },
        );
    }

    pub fn setBuffer(self: *MetalComputeEncoder, buffer: *Buffer, index: u32) void {
        self.handle.msgSend(
            void,
            objc.sel("setBuffer:offset:atIndex:"),
            .{ buffer.handle, @as(c_ulong, 0), @as(c_ulong, index) },
        );
    }

    pub fn setBytes(self: *MetalComputeEncoder, bytes: *const anyopaque, length: u32, index: u32) void {
        self.handle.msgSend(
            void,
            objc.sel("setBytes:length:atIndex:"),
            .{ bytes, @as(c_ulong, length), @as(c_ulong, index) },
        );
    }

    pub fn dispatch(self: *MetalComputeEncoder, grid_w: u32, grid_h: u32, group_w: u32, group_h: u32) void {
        const MTLSize = extern struct {
            width: c_ulong,
            height: c_ulong,
            depth: c_ulong,
        };

        const grid_size = MTLSize{ .width = grid_w, .height = grid_h, .depth = 1 };
        const threadgroup_size = MTLSize{ .width = group_w, .height = group_h, .depth = 1 };

        self.handle.msgSend(
            void,
            objc.sel("dispatchThreadgroups:threadsPerThreadgroup:"),
            .{ grid_size, threadgroup_size },
        );
    }

    pub fn end(self: *MetalComputeEncoder) void {
        self.handle.msgSend(void, objc.sel("endEncoding"), .{});
    }
};
