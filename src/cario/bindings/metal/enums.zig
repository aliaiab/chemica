//! Metal enumerations and constants

/// Resource storage mode for Metal buffers.
///
/// Determines how memory is shared between CPU and GPU:
/// - `.shared`: CPU and GPU both have direct access (default, easiest)
/// - `.managed`: Automatic synchronization between CPU and GPU copies
/// - `.private`: GPU-only memory (fastest for GPU operations)
pub const ResourceStorageMode = enum(u32) {
    shared = 0,
    managed = 1 << 4,
    private = 2 << 4,
};

/// Pixel format for textures and render targets
/// https://developer.apple.com/documentation/metal/mtlpixelformat
pub const PixelFormat = enum(u32) {
    r8_unorm = 10,
    rgba8_unorm = 70,
    bgra8_unorm = 80,
    bgra8_unorm_srgb = 81,  // sRGB variant: auto gamma-encode after blending
    rgb10a2_unorm = 90,     // 10-bit RGB + 2-bit alpha (standard HDR format)
    rgba32_float = 125,
    bgra10_xr = 554,        // 10-bit extended range BGR (wide color)
    bgr10_xr = 555,         // 10-bit extended range BGR, no alpha
};

/// Blend factor for render pipeline blending
/// https://developer.apple.com/documentation/metal/mtlblendfactor
pub const BlendFactor = enum(u32) {
    zero = 0,
    one = 1,
    source_color = 2,
    one_minus_source_color = 3,
    source_alpha = 4,
    one_minus_source_alpha = 5,
    dest_color = 6,
    one_minus_dest_color = 7,
    dest_alpha = 8,
    one_minus_dest_alpha = 9,
};

/// Blend operation for render pipeline blending
pub const BlendOperation = enum(u32) {
    add = 0,
};

/// Primitive type for rendering
pub const PrimitiveType = enum(u32) {
    point = 0,
    line = 1,
    line_strip = 2,
    triangle = 3,
    triangle_strip = 4,
};

/// Index type for indexed drawing
pub const IndexType = enum(u32) {
    uint16 = 0,
    uint32 = 1,
};

/// Vertex step function (per-vertex vs per-instance)
pub const VertexStepFunction = enum(u32) {
    per_vertex = 0,
    per_instance = 1,
};

/// Vertex format for vertex attributes
pub const VertexFormat = enum(u32) {
    uchar = 45,
    uchar4 = 52,
    short2 = 26,
    ushort2 = 32,
    uint = 36,
    uint2 = 37,
    float = 28,
    float2 = 29,
    float4 = 31,
};
