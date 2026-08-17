pub const Context = struct {};

///Compute the sheetmap bounds (width and height in ems) for a given string
pub fn computeBounds(string: []const u8) [2]f32 {
    _ = string; // autofix
    return @splat(0);
}

///Compile a sheetmap from a utf8 string
pub fn construct(
    string: []const u8,
) void {
    _ = string; // autofix
}

///Update a sheetmap line range with a utf8 string
pub fn update(
    string: []const u8,
) void {
    _ = string; // autofix
}

pub const CommandBuffer = struct {};

pub fn encodeConstructCommand(
    command_buffer: *CommandBuffer,
    string: []const u8,
) void {
    _ = command_buffer; // autofix
    _ = string; // autofix
}

pub fn encodeUpdateCommand(
    command_buffer: *CommandBuffer,
    string: []const u8,
) void {
    _ = command_buffer; // autofix
    _ = string; // autofix
}

pub const Sheetmap = extern struct {
    quadrat_buffer_begin: u32 = 0,
    kern_buffer_begin: u32 = 0,
    foreground_buffer_begin: u32 = 0,
    bakcground_buffer_begin: u32 = 0,
    width: u32,
    height: u32,
};

pub const SheetmapSampler = extern struct {
    spacing_x: f32,
    spacing_y: f32,
    uv_rotation_quadrat: [2]f32,
    uv_rotation_glyph: [2]f32,
    foreground_colour: u32,
    background_colour: u32,
    typeface_texel_sampler: u32,
    typeface: u32,
};

pub const CombinedSheetmapSampler = extern struct {
    map: Sheetmap,
    sampler: SheetmapSampler,
};
