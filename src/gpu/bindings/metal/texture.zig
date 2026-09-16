//! MTLTexture wrapper using zig-objc

const std = @import("std");
const objc = @import("../objc_minimal.zig");

/// Metal Texture wrapper
pub const MetalTexture = struct {
    handle: objc.Object,

    pub fn deinit(self: *MetalTexture) void {
        self.handle.msgSend(void, objc.sel("release"), .{});
    }

    /// Create MetalTexture from existing texture pointer (for drawable textures)
    pub fn initFromPtr(texture_ptr: ?*anyopaque) MetalTexture {
        return .{ .handle = objc.Object.fromId(texture_ptr.?) };
    }

    /// Upload data to texture
    pub fn upload(self: *MetalTexture, data: []const u8, width: u32, height: u32, bytes_per_row: u32) void {
        // MTLRegion is a C struct, so we can create it directly
        const MTLRegion = extern struct {
            origin: extern struct { x: u64, y: u64, z: u64 },
            size: extern struct { width: u64, height: u64, depth: u64 },
        };

        const region = MTLRegion{
            .origin = .{ .x = 0, .y = 0, .z = 0 },
            .size = .{ .width = width, .height = height, .depth = 1 },
        };

        self.handle.msgSend(
            void,
            objc.sel("replaceRegion:mipmapLevel:withBytes:bytesPerRow:"),
            .{ region, @as(c_ulong, 0), data.ptr, @as(c_ulong, bytes_per_row) },
        );
    }

    /// Download data from texture
    pub fn download(self: *MetalTexture, data: []u8, width: u32, height: u32, bytes_per_row: u32) void {
        const MTLRegion = extern struct {
            origin: extern struct { x: u64, y: u64, z: u64 },
            size: extern struct { width: u64, height: u64, depth: u64 },
        };

        const region = MTLRegion{
            .origin = .{ .x = 0, .y = 0, .z = 0 },
            .size = .{ .width = width, .height = height, .depth = 1 },
        };

        self.handle.msgSend(
            void,
            objc.sel("getBytes:bytesPerRow:fromRegion:mipmapLevel:"),
            .{ data.ptr, @as(c_ulong, bytes_per_row), region, @as(c_ulong, 0) },
        );
    }

    /// Get texture width
    pub fn getWidth(self: *const MetalTexture) u64 {
        return self.handle.msgSend(u64, objc.sel("width"), .{});
    }

    /// Get texture height
    pub fn getHeight(self: *const MetalTexture) u64 {
        return self.handle.msgSend(u64, objc.sel("height"), .{});
    }
};
