//! MTLRenderPassDescriptor wrapper using zig-objc

const objc = @import("../objc_minimal.zig");

const Texture = @import("texture.zig").MetalTexture;

/// Metal render pass descriptor
pub const MetalRenderPassDescriptor = struct {
    handle: objc.Object,

    pub fn init() MetalRenderPassDescriptor {
        const MTLRenderPassDescriptor = objc.getClass("MTLRenderPassDescriptor").?;
        const desc = MTLRenderPassDescriptor.msgSend(
            objc.Object,
            objc.sel("renderPassDescriptor"),
            .{},
        );

        // Retain the autoreleased descriptor so we own it
        _ = desc.msgSend(objc.Object, objc.sel("retain"), .{});

        return .{ .handle = desc };
    }

    pub fn deinit(self: *MetalRenderPassDescriptor) void {
        self.handle.msgSend(void, objc.sel("release"), .{});
    }

    pub fn setColorTexture(self: *MetalRenderPassDescriptor, texture: *Texture, index: u32) void {
        const colorAttachments = objc.Object.fromId(
            self.handle.getProperty(?*anyopaque, "colorAttachments"),
        );

        const attachment = colorAttachments.msgSend(
            objc.Object,
            objc.sel("objectAtIndexedSubscript:"),
            .{@as(c_ulong, index)},
        );

        attachment.setProperty("texture", texture.handle);
        attachment.setProperty("loadAction", @as(c_ulong, 2)); // MTLLoadActionClear
        attachment.setProperty("storeAction", @as(c_ulong, 1)); // MTLStoreActionStore
    }

    pub fn setClearColor(self: *MetalRenderPassDescriptor, r: f64, g: f64, b: f64, a: f64, index: u32) void {
        const MTLClearColor = extern struct {
            red: f64,
            green: f64,
            blue: f64,
            alpha: f64,
        };

        const color = MTLClearColor{ .red = r, .green = g, .blue = b, .alpha = a };

        const colorAttachments = objc.Object.fromId(
            self.handle.getProperty(?*anyopaque, "colorAttachments"),
        );

        const attachment = colorAttachments.msgSend(
            objc.Object,
            objc.sel("objectAtIndexedSubscript:"),
            .{@as(c_ulong, index)},
        );

        // Use msgSend directly to pass the struct - setClearColor: expects an MTLClearColor struct
        attachment.msgSend(void, objc.sel("setClearColor:"), .{color});
    }
};
