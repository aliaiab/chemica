pub fn loadTypeFaceFromTTf(
    context: *geo.Context,
    ttf_data: []const u8,
) !geo.TextTypeFaceHandle {
    var info: stbtt.struct_stbtt_fontinfo = undefined;
    if (stbtt.stbtt_InitFont(&info, ttf_data.ptr, 0) == 0) {
        return error.TTFLoadFailure;
    }

    const type_face_handle: geo.TextTypeFaceHandle = @fromBackingInt(@intCast(context.type_faces.items.len));
    var type_face_data = try context.type_faces.addOne(context.arena.allocator());
    type_face_data.* = .{
        .codepoints_to_glyph = .empty,
    };

    for (0..255) |index| {
        const ascii: u8 = @intCast(index);
        if (!std.ascii.isAscii(ascii)) {
            continue;
        }
        var ax: c_int = 0;
        var lsb: c_int = 0;

        stbtt.stbtt_GetCodepointHMetrics(
            &info,
            ascii,
            &ax,
            &lsb,
        );

        const aspect_ratio: f32 = @floatFromInt(ax);

        try type_face_data.codepoints_to_glyph.put(
            context.arena.allocator(),
            ascii,
            .{
                .aspect_ratio = aspect_ratio,
                .advance = @floatFromInt(ax),
                .bearing_x = @floatFromInt(lsb),
                .bearing_y = 0,
            },
        );
    }

    return type_face_handle;
}

const std = @import("std");
const geo = @import("geo.zig");
const stbtt = @import("stb_truetype.zig");
