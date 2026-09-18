//! MTLComputePipelineState wrapper using zig-objc

const objc = @import("../objc_minimal.zig");

/// Compute pipeline state
pub const MetalPipeline = struct {
    handle: objc.Object,

    pub fn deinit(self: *MetalPipeline) void {
        self.handle.msgSend(void, objc.sel("release"), .{});
    }
};
