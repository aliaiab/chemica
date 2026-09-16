//! MTLDevice wrapper using zig-objc

const std = @import("std");
const objc = @import("../objc_minimal.zig");
const errors = @import("errors.zig");
const enums = @import("enums.zig");

pub const MetalError = errors.MetalError;
pub const ResourceStorageMode = enums.ResourceStorageMode;

const CommandQueue = @import("command_queue.zig").MetalCommandQueue;
const Library = @import("library.zig").MetalLibrary;
const Buffer = @import("buffer.zig").MetalBuffer;
const Texture = @import("texture.zig").MetalTexture;

/// Represents a Metal GPU device
pub const MetalDevice = struct {
    handle: objc.Object,

    /// Create Metal device using system default GPU
    pub fn init() MetalError!MetalDevice {
        const MTLCreateSystemDefaultDevice = @extern(*const fn () callconv(.c) ?*anyopaque, .{
            .name = "MTLCreateSystemDefaultDevice",
        });

        const device_ptr = MTLCreateSystemDefaultDevice() orelse return MetalError.DeviceNotFound;
        const device = objc.Object.fromId(device_ptr);

        return .{ .handle = device };
    }

    /// Create Metal device by index
    pub fn initAtIndex(index: u32) MetalError!MetalDevice {
        const MTLCopyAllDevices = @extern(*const fn () callconv(.c) ?*anyopaque, .{
            .name = "MTLCopyAllDevices",
        });

        const devices_ptr = MTLCopyAllDevices() orelse return MetalError.DeviceNotFound;
        const devices = objc.Object.fromId(devices_ptr);
        defer devices.msgSend(void, objc.sel("release"), .{});

        const count = devices.msgSend(c_ulong, objc.sel("count"), .{});
        if (index >= count) return MetalError.DeviceNotFound;

        const device = devices.msgSend(objc.Object, objc.sel("objectAtIndex:"), .{@as(c_ulong, index)});
        _ = device.msgSend(objc.Object, objc.sel("retain"), .{});

        return .{ .handle = device };
    }

    pub fn deinit(self: *MetalDevice) void {
        self.handle.msgSend(void, objc.sel("release"), .{});
    }

    /// Get device name (e.g., "Apple M1 Pro")
    pub fn getName(self: *const MetalDevice) ?[]const u8 {
        const name = self.handle.msgSend(objc.Object, objc.sel("name"), .{});
        const name_ptr = name.msgSend(?[*:0]const u8, objc.sel("UTF8String"), .{}) orelse return null;
        return std.mem.span(name_ptr);
    }

    /// Create command queue for submitting GPU work
    pub fn createCommandQueue(self: *MetalDevice) MetalError!CommandQueue {
        const queue = self.handle.msgSend(objc.Object, objc.sel("newCommandQueue"), .{});
        if (queue.value == null) return MetalError.DeviceNotFound;

        return .{ .handle = queue };
    }

    /// Compile Metal shader from source code at runtime
    pub fn createLibraryFromSource(self: *MetalDevice, source: [:0]const u8) MetalError!Library {
        // Create NSString from source
        const NSString = objc.getClass("NSString").?;
        const source_str = NSString.msgSend(
            objc.Object,
            objc.sel("stringWithUTF8String:"),
            .{source.ptr},
        );

        var err: ?*anyopaque = null;
        const library = self.handle.msgSend(
            objc.Object,
            objc.sel("newLibraryWithSource:options:error:"),
            .{ source_str, @as(?*anyopaque, null), &err },
        );

        if (err) |e| {
            const nserr = objc.Object.fromId(e);
            const desc = nserr.msgSend(objc.Object, objc.sel("localizedDescription"), .{});
            const desc_str = desc.msgSend(?[*:0]const u8, objc.sel("UTF8String"), .{});
            if (desc_str) |s| {
                std.debug.print("Shader compilation error: {s}\n", .{std.mem.span(s)});
            }
            return MetalError.LibraryCreationFailed;
        }

        if (library.value == null) return MetalError.LibraryCreationFailed;

        return .{ .handle = library };
    }

    /// Create GPU buffer with shared storage mode (default, CPU/GPU accessible)
    pub fn createBuffer(self: *MetalDevice, size: u32) MetalError!Buffer {
        return self.createBufferWithOptions(size, .shared);
    }

    /// Create GPU buffer with specific storage mode
    pub fn createBufferWithOptions(self: *MetalDevice, size: u32, mode: ResourceStorageMode) MetalError!Buffer {
        const buffer = self.handle.msgSend(
            objc.Object,
            objc.sel("newBufferWithLength:options:"),
            .{ @as(c_ulong, size), @intFromEnum(mode) },
        );

        if (buffer.value == null) return MetalError.BufferCreationFailed;

        return .{ .handle = buffer, .len = size };
    }

    /// Create 2D texture
    pub fn createTextureWithFormat(self: *MetalDevice, width: u32, height: u32, format: enums.PixelFormat, writable: bool) MetalError!Texture {
        // Create MTLTextureDescriptor
        const MTLTextureDescriptor = objc.getClass("MTLTextureDescriptor").?;
        const desc = MTLTextureDescriptor.msgSend(
            objc.Object,
            objc.sel("texture2DDescriptorWithPixelFormat:width:height:mipmapped:"),
            .{
                @intFromEnum(format),
                @as(c_ulong, width),
                @as(c_ulong, height),
                false,
            },
        );

        // Set usage
        const usage: c_ulong = if (writable) 2 else 1; // MTLTextureUsageShaderWrite : MTLTextureUsageShaderRead
        desc.setProperty("usage", usage);

        const texture = self.handle.msgSend(objc.Object, objc.sel("newTextureWithDescriptor:"), .{desc});
        if (texture.value == null) return MetalError.TextureCreationFailed;

        return .{ .handle = texture };
    }

    /// Create 2D texture with default RGBA32Float format
    pub fn createTexture(self: *MetalDevice, width: u32, height: u32, writable: bool) MetalError!Texture {
        return self.createTextureWithFormat(width, height, .rgba32_float, writable);
    }
};

/// Check if Metal is available on this system
pub fn isAvailable() bool {
    const MTLCreateSystemDefaultDevice = @extern(*const fn () callconv(.c) ?*anyopaque, .{
        .name = "MTLCreateSystemDefaultDevice",
    });

    return MTLCreateSystemDefaultDevice() != null;
}

/// Get the number of Metal-capable GPU devices available
pub fn getDeviceCount() u32 {
    const MTLCopyAllDevices = @extern(*const fn () callconv(.c) ?*anyopaque, .{
        .name = "MTLCopyAllDevices",
    });

    const devices_ptr = MTLCopyAllDevices() orelse return 0;
    const devices = objc.Object.fromId(devices_ptr);
    defer devices.msgSend(void, objc.sel("release"), .{});

    return @intCast(devices.msgSend(c_ulong, objc.sel("count"), .{}));
}

/// Get all available Metal devices
pub fn getAllDevices(allocator: std.mem.Allocator) ![]MetalDevice {
    const count = getDeviceCount();
    if (count == 0) return &[_]MetalDevice{};

    var result = try allocator.alloc(MetalDevice, count);
    for (0..count) |i| {
        result[i] = try MetalDevice.initAtIndex(@intCast(i));
    }
    return result;
}
