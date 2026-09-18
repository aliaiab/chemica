//! MTLLibrary and MTLFunction wrappers using zig-objc

const std = @import("std");
const objc = @import("../objc_minimal.zig");
const errors = @import("errors.zig");
const enums = @import("enums.zig");

pub const MetalError = errors.MetalError;

const Device = @import("device.zig").MetalDevice;
const Pipeline = @import("pipeline.zig").MetalPipeline;
const RenderPipeline = @import("render_pipeline.zig").MetalRenderPipelineState;
const RenderPipelineDescriptor = @import("render_pipeline.zig").RenderPipelineDescriptor;

/// Compiled Metal shader library
pub const MetalLibrary = struct {
    handle: objc.Object,

    pub fn deinit(self: *MetalLibrary) void {
        self.handle.msgSend(void, objc.sel("release"), .{});
    }

    /// Get kernel function by name from this library
    pub fn createFunction(self: *MetalLibrary, name: [:0]const u8) MetalError!MetalFunction {
        const NSString = objc.getClass("NSString").?;
        const name_str = NSString.msgSend(
            objc.Object,
            objc.sel("stringWithUTF8String:"),
            .{name.ptr},
        );

        const function = self.handle.msgSend(
            objc.Object,
            objc.sel("newFunctionWithName:"),
            .{name_str},
        );

        if (function.value == null) return MetalError.FunctionNotFound;

        return .{ .handle = function };
    }
};

/// Metal kernel function
pub const MetalFunction = struct {
    handle: objc.Object,

    pub fn deinit(self: *MetalFunction) void {
        self.handle.msgSend(void, objc.sel("release"), .{});
    }

    /// Create compute pipeline from this function
    pub fn createPipeline(self: *MetalFunction, device: *Device) MetalError!Pipeline {
        var err: ?*anyopaque = null;
        const pipeline = device.handle.msgSend(
            objc.Object,
            objc.sel("newComputePipelineStateWithFunction:error:"),
            .{ self.handle, &err },
        );

        if (err) |e| {
            const nserr = objc.Object.fromId(e);
            const desc = nserr.msgSend(objc.Object, objc.sel("localizedDescription"), .{});
            const desc_str = desc.msgSend(?[*:0]const u8, objc.sel("UTF8String"), .{});
            if (desc_str) |s| {
                std.debug.print("Pipeline creation error: {s}\n", .{std.mem.span(s)});
            }
            return MetalError.PipelineCreationFailed;
        }

        if (pipeline.value == null) return MetalError.PipelineCreationFailed;

        return .{ .handle = pipeline };
    }

    /// Create render pipeline from vertex and fragment functions
    pub fn createRenderPipeline(
        self: *MetalFunction,
        device: *Device,
        fragment_function: *MetalFunction,
        descriptor: RenderPipelineDescriptor,
    ) MetalError!RenderPipeline {
        // Create MTLRenderPipelineDescriptor
        const MTLRenderPipelineDescriptor = objc.getClass("MTLRenderPipelineDescriptor").?;
        const desc = MTLRenderPipelineDescriptor.msgSend(
            objc.Object,
            objc.sel("alloc"),
            .{},
        ).msgSend(objc.Object, objc.sel("init"), .{});
        defer desc.msgSend(void, objc.sel("release"), .{});

        // Set vertex and fragment functions
        desc.setProperty("vertexFunction", self.handle);
        desc.setProperty("fragmentFunction", fragment_function.handle);

        // Get color attachments
        const attachments = objc.Object.fromId(desc.getProperty(?*anyopaque, "colorAttachments"));
        const attachment = attachments.msgSend(
            objc.Object,
            objc.sel("objectAtIndexedSubscript:"),
            .{@as(c_ulong, 0)},
        );

        // Set pixel format
        attachment.setProperty("pixelFormat", @intFromEnum(descriptor.pixel_format));

        // Set write mask to write all channels (RGBA)
        // MTLColorWriteMaskAll = 0xF (write red, green, blue, alpha)
        attachment.setProperty("writeMask", @as(c_ulong, 0xF));

        // Set blending configuration
        // Convert bool to BOOL (i8 or bool depending on platform)
        const objc_bool = objc.boolParam(descriptor.blend_enabled);
        attachment.setProperty("blendingEnabled", objc_bool);
        if (descriptor.blend_enabled) {
            attachment.setProperty("sourceRGBBlendFactor", @intFromEnum(descriptor.source_rgb_blend_factor));
            attachment.setProperty("destinationRGBBlendFactor", @intFromEnum(descriptor.destination_rgb_blend_factor));
            attachment.setProperty("rgbBlendOperation", @intFromEnum(descriptor.rgb_blend_operation));
            attachment.setProperty("sourceAlphaBlendFactor", @intFromEnum(descriptor.source_alpha_blend_factor));
            attachment.setProperty("destinationAlphaBlendFactor", @intFromEnum(descriptor.destination_alpha_blend_factor));
            attachment.setProperty("alphaBlendOperation", @intFromEnum(descriptor.alpha_blend_operation));
        }

        // Create pipeline state
        var err: ?*anyopaque = null;
        const pipeline = device.handle.msgSend(
            objc.Object,
            objc.sel("newRenderPipelineStateWithDescriptor:error:"),
            .{ desc, &err },
        );

        if (err) |e| {
            const nserr = objc.Object.fromId(e);
            const err_desc = nserr.msgSend(objc.Object, objc.sel("localizedDescription"), .{});
            const desc_str = err_desc.msgSend(?[*:0]const u8, objc.sel("UTF8String"), .{});
            if (desc_str) |s| {
                std.debug.print("Render pipeline error: {s}\n", .{std.mem.span(s)});
            }
            return MetalError.PipelineCreationFailed;
        }

        if (pipeline.value == null) return MetalError.PipelineCreationFailed;

        return .{ .handle = pipeline };
    }
};
