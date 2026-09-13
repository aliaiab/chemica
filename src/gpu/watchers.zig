const std = @import("std");
const builtin = @import("builtin");
pub const Event = @import("watchers/interfaces.zig").Event;

const watchers = struct {
    pub const linux = @import("watchers/linux.zig");
};

pub const Watcher = switch (builtin.os.tag) {
    .linux => watchers.linux.LinuxWatcher,
    else => @compileError("Unsupported OS"),
};
