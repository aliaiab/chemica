//! MTLRenderPipelineState wrapper using zig-objc

const objc = @import("../objc_minimal.zig");
const enums = @import("enums.zig");

/// Render pipeline descriptor for creating render pipelines
pub const RenderPipelineDescriptor = struct {
    pixel_format: enums.PixelFormat = .bgra8_unorm,
    blend_enabled: bool = false,
    source_rgb_blend_factor: enums.BlendFactor = .one,
    destination_rgb_blend_factor: enums.BlendFactor = .zero,
    rgb_blend_operation: enums.BlendOperation = .add,
    source_alpha_blend_factor: enums.BlendFactor = .one,
    destination_alpha_blend_factor: enums.BlendFactor = .zero,
    alpha_blend_operation: enums.BlendOperation = .add,
};

/// Metal render pipeline state
pub const MetalRenderPipelineState = struct {
    handle: objc.Object,

    pub fn deinit(self: *MetalRenderPipelineState) void {
        self.handle.msgSend(void, objc.sel("release"), .{});
    }
};
