/// The type of `sampled_image` must be a pointer to a SPIR-V sampled image.
pub inline fn imageSampleImplicitLod(
    sampled_image: anytype,
    coordinate: ImageCoordinate(std.meta.Child(@TypeOf(sampled_image)), f32),
) @Vector(4, ImageSampledType(std.meta.Child(@TypeOf(sampled_image)))) {
    const SampledImage = switch (@typeInfo(@TypeOf(sampled_image))) {
        .pointer => |pointer| pointer.child,
        else => @compileError("Expected a pointer to SPIR-V sampled image type, found '" ++ @typeName(@TypeOf(sampled_image)) ++ "'"),
    };
    const Result = @Vector(4, ImageSampledType(SampledImage));

    const image_info = switch (@typeInfo(SampledImage)) {
        .spirv => |spirv| switch (spirv) {
            .sampled_image => |sampled_image_info| @typeInfo(sampled_image_info).spirv.image,
            else => @compileError("Expected SPIR-V sampled image type, found '" ++ @typeName(SampledImage) ++ "'"),
        },
        else => @compileError("Expected SPIR-V sampled image type, found '" ++ @typeName(SampledImage) ++ "'"),
    };

    if (image_info.multisampled)
        @compileError("Can not implicitly sample a sampled image that was multisampled");

    // TOOD: If buffer dim is added, throw a compile error if the dimension is a buffer.

    return asm volatile (
        \\%loaded_sampler = OpLoad %SampledImage %sampled_image
        \\%ret            = OpImageSampleImplicitLod %Result %loaded_sampler %coordinate
        : [ret] "" (-> Result),
        : [SampledImage] "t" (SampledImage),
          [sampled_image] "" (sampled_image),
          [Result] "t" (Result),
          [coordinate] "" (coordinate),
    );
}

/// Write a texel to an image without a sampler.
/// The type of `image` must be a pointer to a SPIR-V image.
pub inline fn imageFetch(
    image: anytype,
    T: type,
    coordinate: ImageCoordinate(std.meta.Child(@TypeOf(image)), T),
) @Vector(4, ImageSampledType(std.meta.Child(@TypeOf(image)))) {
    const ReturnType = @Vector(4, ImageSampledType(std.meta.Child(@TypeOf(image))));
    switch (T) {
        u32, i32 => {},
        else => @compileError("Expected one of u32, i32 and f32 types. Found '" ++ @typeName(T) ++ "'"),
    }

    const Image = switch (@typeInfo(@TypeOf(image))) {
        .pointer => |pointer| pointer.child,
        else => @compileError("Expected a pointer to SPIR-V image type, found '" ++ @typeName(@TypeOf(image)) ++ "'"),
    };

    return asm volatile (
        \\%loaded_image = OpLoad %Image %image
        \\%texel = OpImageRead %Result %loaded_image %coordinate
        : [texel] "" (-> ReturnType),
        : [Image] "t" (Image),
          [Result] "t" (ReturnType),
          [image] "" (image),
          [coordinate] "" (coordinate),
    );
}

/// The type of the components that result from sampling or reading from the given SPIR-V image or sampled image type.
fn ImageSampledType(Image: type) type {
    const image_info = switch (@typeInfo(Image)) {
        .spirv => |spirv| switch (spirv) {
            .sampled_image => |sampled_image| @typeInfo(sampled_image).spirv.image,
            .image => |image| image,
            else => @compileError("Expected SPIR-V image or sampled image type, found '" ++ @typeName(Image) ++ "'"),
        },
        else => @compileError("Expected SPIR-V image or sampled image type, found '" ++ @typeName(Image) ++ "'"),
    };
    return switch (image_info.usage) {
        inline else => |usage| usage,
    };
}

/// Get the type that specifies a coordinate for a SPIR-V image or sampled image.
fn ImageCoordinate(Image: type, Element: type) type {
    const image_info = switch (@typeInfo(Image)) {
        .spirv => |spv| switch (spv) {
            .sampled_image => |sampled_image| @typeInfo(sampled_image).spirv.image,
            .image => |image| image,
            else => @compileError("Expected SPIR-V image or sampled image type, found '" ++ @typeName(Image) ++ "'"),
        },
        else => @compileError("Expected SPIR-V image or sampled image type, found '" ++ @typeName(Image) ++ "'"),
    };
    const dim = switch (image_info.dim) {
        .@"1d" => 1 + @as(u8, @intFromBool(image_info.arrayed)),
        .@"2d" => 2 + @as(u8, @intFromBool(image_info.arrayed)),
        .@"3d", .cube => 3 + @as(u8, @intFromBool(image_info.arrayed)),
    };
    if (dim == 1) return Element else return @Vector(dim, Element);
}

const std = @import("std");
