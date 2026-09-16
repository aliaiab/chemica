//! MTLRenderCommandEncoder wrapper using zig-objc

const objc = @import("../objc_minimal.zig");
const enums = @import("enums.zig");

const RenderPipeline = @import("render_pipeline.zig").MetalRenderPipelineState;
const Buffer = @import("buffer.zig").MetalBuffer;
const Texture = @import("texture.zig").MetalTexture;

/// Metal render command encoder
pub const MetalRenderEncoder = struct {
    handle: objc.Object,

    pub fn deinit(self: *MetalRenderEncoder) void {
        self.handle.msgSend(void, objc.sel("release"), .{});
    }

    pub fn setPipeline(self: *MetalRenderEncoder, pipeline: *RenderPipeline) void {
        self.handle.msgSend(void, objc.sel("setRenderPipelineState:"), .{pipeline.handle});
    }

    pub fn setVertexBuffer(self: *MetalRenderEncoder, buffer: *Buffer, offset: u32, index: u32) void {
        self.handle.msgSend(
            void,
            objc.sel("setVertexBuffer:offset:atIndex:"),
            .{ buffer.handle, @as(c_ulong, offset), @as(c_ulong, index) },
        );
    }

    pub fn setVertexBytes(self: *MetalRenderEncoder, bytes: *const anyopaque, length: u32, index: u32) void {
        self.handle.msgSend(
            void,
            objc.sel("setVertexBytes:length:atIndex:"),
            .{ bytes, @as(c_ulong, length), @as(c_ulong, index) },
        );
    }

    pub fn setFragmentBuffer(self: *MetalRenderEncoder, buffer: *Buffer, offset: u32, index: u32) void {
        self.handle.msgSend(
            void,
            objc.sel("setFragmentBuffer:offset:atIndex:"),
            .{ buffer.handle, @as(c_ulong, offset), @as(c_ulong, index) },
        );
    }

    pub fn setFragmentBytes(self: *MetalRenderEncoder, bytes: *const anyopaque, length: u32, index: u32) void {
        self.handle.msgSend(
            void,
            objc.sel("setFragmentBytes:length:atIndex:"),
            .{ bytes, @as(c_ulong, length), @as(c_ulong, index) },
        );
    }

    pub fn setFragmentTexture(self: *MetalRenderEncoder, texture: *Texture, index: u32) void {
        self.handle.msgSend(
            void,
            objc.sel("setFragmentTexture:atIndex:"),
            .{ texture.handle, @as(c_ulong, index) },
        );
    }

    pub fn drawPrimitives(self: *MetalRenderEncoder, primitive_type: enums.PrimitiveType, vertex_start: u32, vertex_count: u32) void {
        self.handle.msgSend(
            void,
            objc.sel("drawPrimitives:vertexStart:vertexCount:"),
            .{ @intFromEnum(primitive_type), @as(c_ulong, vertex_start), @as(c_ulong, vertex_count) },
        );
    }

    pub fn drawPrimitivesInstanced(
        self: *MetalRenderEncoder,
        primitive_type: enums.PrimitiveType,
        vertex_start: u32,
        vertex_count: u32,
        instance_count: u32,
    ) void {
        self.handle.msgSend(
            void,
            objc.sel("drawPrimitives:vertexStart:vertexCount:instanceCount:"),
            .{ @intFromEnum(primitive_type), @as(c_ulong, vertex_start), @as(c_ulong, vertex_count), @as(c_ulong, instance_count) },
        );
    }

    pub fn drawIndexedPrimitives(
        self: *MetalRenderEncoder,
        primitive_type: enums.PrimitiveType,
        index_count: u32,
        index_buffer: *Buffer,
        index_buffer_offset: u32,
    ) void {
        self.handle.msgSend(
            void,
            objc.sel("drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:"),
            .{
                @intFromEnum(primitive_type),
                @as(c_ulong, index_count),
                @intFromEnum(enums.IndexType.uint16),
                index_buffer.handle,
                @as(c_ulong, index_buffer_offset),
            },
        );
    }

    pub fn drawIndexedPrimitivesInstanced(
        self: *MetalRenderEncoder,
        primitive_type: enums.PrimitiveType,
        index_count: u32,
        index_buffer: *Buffer,
        index_buffer_offset: u32,
        instance_count: u32,
    ) void {
        self.handle.msgSend(
            void,
            objc.sel("drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:instanceCount:"),
            .{
                @intFromEnum(primitive_type),
                @as(c_ulong, index_count),
                @intFromEnum(enums.IndexType.uint16),
                index_buffer.handle,
                @as(c_ulong, index_buffer_offset),
                @as(c_ulong, instance_count),
            },
        );
    }

    pub fn setScissorRect(self: *MetalRenderEncoder, x: u32, y: u32, width: u32, height: u32) void {
        const ScissorRect = extern struct {
            x: c_ulong,
            y: c_ulong,
            width: c_ulong,
            height: c_ulong,
        };
        const rect = ScissorRect{
            .x = @as(c_ulong, x),
            .y = @as(c_ulong, y),
            .width = @as(c_ulong, width),
            .height = @as(c_ulong, height),
        };
        self.handle.msgSend(void, objc.sel("setScissorRect:"), .{rect});
    }

    pub fn end(self: *MetalRenderEncoder) void {
        self.handle.msgSend(void, objc.sel("endEncoding"), .{});
    }
};
