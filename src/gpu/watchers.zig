const std = @import("std");
const builtin = @import("builtin");
pub const Event = @import("watchers/interfaces.zig").Event;
const interfaces = @import("watchers/interfaces.zig");

const watchers = struct {
    pub const linux = @import("watchers/linux.zig");
};

const EmptyWatcher = struct {
    pub fn init(_: std.Io, _: std.mem.Allocator) !EmptyWatcher {
        return .{};
    }

    pub fn deinit(_: *EmptyWatcher) void {}
    pub fn addFile(_: *EmptyWatcher, _: [:0]const u8) !void {}
    pub fn stop(_: *EmptyWatcher) void {}
    pub fn setCallback(
        _: *EmptyWatcher,
        _: interfaces.Callback,
        _: ?*anyopaque,
    ) void {}

    pub fn start(_: *EmptyWatcher, _: interfaces.Opts) !void {}
};

pub const Watcher = switch (builtin.os.tag) {
    .linux => watchers.linux.LinuxWatcher,
    .macos => EmptyWatcher,
    else => @compileError("Unsupported OS"),
};
