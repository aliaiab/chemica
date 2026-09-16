//! Pure Zig Metal bindings using zig-objc
//! Provides a clean Zig wrapper around Metal API for GPU compute and rendering

const std = @import("std");

// Re-export all types from metal/ directory
pub const MetalError = @import("metal/errors.zig").MetalError;
pub const ResourceStorageMode = @import("metal/enums.zig").ResourceStorageMode;
pub const PixelFormat = @import("metal/enums.zig").PixelFormat;
pub const BlendFactor = @import("metal/enums.zig").BlendFactor;
pub const BlendOperation = @import("metal/enums.zig").BlendOperation;
pub const PrimitiveType = @import("metal/enums.zig").PrimitiveType;
pub const IndexType = @import("metal/enums.zig").IndexType;
pub const VertexStepFunction = @import("metal/enums.zig").VertexStepFunction;
pub const VertexFormat = @import("metal/enums.zig").VertexFormat;

pub const MetalDevice = @import("metal/device.zig").MetalDevice;
pub const MetalCommandQueue = @import("metal/command_queue.zig").MetalCommandQueue;
pub const MetalLibrary = @import("metal/library.zig").MetalLibrary;
pub const MetalFunction = @import("metal/library.zig").MetalFunction;
pub const MetalPipeline = @import("metal/pipeline.zig").MetalPipeline;
pub const MetalRenderPipelineState = @import("metal/render_pipeline.zig").MetalRenderPipelineState;
pub const RenderPipelineDescriptor = @import("metal/render_pipeline.zig").RenderPipelineDescriptor;
pub const MetalCommandBuffer = @import("metal/command_buffer.zig").MetalCommandBuffer;
pub const MetalComputeEncoder = @import("metal/compute_encoder.zig").MetalComputeEncoder;
pub const MetalRenderEncoder = @import("metal/render_encoder.zig").MetalRenderEncoder;
pub const MetalBlitEncoder = @import("metal/blit_encoder.zig").MetalBlitEncoder;
pub const MetalRenderPassDescriptor = @import("metal/render_pass.zig").MetalRenderPassDescriptor;
pub const MetalTexture = @import("metal/texture.zig").MetalTexture;
pub const MetalBuffer = @import("metal/buffer.zig").MetalBuffer;

// Re-export convenience functions
pub const isAvailable = @import("metal/device.zig").isAvailable;
pub const getDeviceCount = @import("metal/device.zig").getDeviceCount;
pub const getAllDevices = @import("metal/device.zig").getAllDevices;

test "Metal availability" {
    try std.testing.expect(isAvailable());
}

test "Metal device creation" {
    if (!isAvailable()) return error.SkipZigTest;

    var device = try MetalDevice.init();
    defer device.deinit();

    try std.testing.expect(device.handle.value != null);
}

test "Command queue creation" {
    if (!isAvailable()) return error.SkipZigTest;

    var device = try MetalDevice.init();
    defer device.deinit();

    var queue = try device.createCommandQueue();
    defer queue.deinit();

    try std.testing.expect(queue.handle.value != null);
}

test "Simple compute shader" {
    if (!isAvailable()) return error.SkipZigTest;

    var device = try MetalDevice.init();
    defer device.deinit();

    var queue = try device.createCommandQueue();
    defer queue.deinit();

    const shader =
        \\#include <metal_stdlib>
        \\using namespace metal;
        \\kernel void double_values(
        \\    device float* data [[buffer(0)]],
        \\    uint index [[thread_position_in_grid]])
        \\{
        \\    data[index] *= 2.0;
        \\}
    ;

    var library = try device.createLibraryFromSource(shader);
    defer library.deinit();

    var function = try library.createFunction("double_values");
    defer function.deinit();

    var pipeline = try function.createPipeline(&device);
    defer pipeline.deinit();

    var buffer = try device.createBuffer(16);
    defer buffer.deinit();

    var data = [_]f32{ 1.0, 2.0, 3.0, 4.0 };
    buffer.upload(std.mem.sliceAsBytes(&data));

    var cmdBuffer = try queue.createCommandBuffer();
    defer cmdBuffer.deinit();

    var encoder = try cmdBuffer.createComputeEncoder();
    defer encoder.deinit();

    encoder.setPipeline(&pipeline);
    encoder.setBuffer(&buffer, 0);
    encoder.dispatch(1, 1, 4, 1);
    encoder.end();

    cmdBuffer.commit();
    cmdBuffer.waitForCompletion();

    buffer.download(std.mem.sliceAsBytes(&data));
    try std.testing.expectEqual(@as(f32, 2.0), data[0]);
    try std.testing.expectEqual(@as(f32, 4.0), data[1]);
    try std.testing.expectEqual(@as(f32, 6.0), data[2]);
    try std.testing.expectEqual(@as(f32, 8.0), data[3]);
}

test "Direct buffer access with getContentsAs" {
    if (!isAvailable()) return error.SkipZigTest;

    var device = try MetalDevice.init();
    defer device.deinit();

    var buffer = try device.createBuffer(16);
    defer buffer.deinit();

    const data = buffer.getContentsAs(f32) orelse return error.BufferAccessFailed;
    try std.testing.expectEqual(@as(usize, 4), data.len);

    data[0] = 10.0;
    data[1] = 20.0;
    data[2] = 30.0;
    data[3] = 40.0;

    try std.testing.expectEqual(@as(f32, 10.0), data[0]);
    try std.testing.expectEqual(@as(f32, 20.0), data[1]);
    try std.testing.expectEqual(@as(f32, 30.0), data[2]);
    try std.testing.expectEqual(@as(f32, 40.0), data[3]);
}

test "Device enumeration" {
    if (!isAvailable()) return error.SkipZigTest;

    const count = getDeviceCount();
    try std.testing.expect(count > 0);

    var device = try MetalDevice.initAtIndex(0);
    defer device.deinit();

    const name = device.getName();
    try std.testing.expect(name != null);
}
