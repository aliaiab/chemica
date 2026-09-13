const std = @import("std");
const interfaces = @import("interfaces.zig");
const linux = std.os.linux;

pub const LinuxWatcher = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    wd_to_path: std.AutoHashMap(usize, [:0]const u8),
    path_to_wd: std.StringHashMap(usize),
    file_count: u32,
    fd: i32,
    callback: ?*const interfaces.Callback,
    context: ?*anyopaque,
    running: bool,

    pub fn init(io: std.Io, allocator: std.mem.Allocator) !LinuxWatcher {
        const fd = std.os.linux.inotify_init1(linux.IN.NONBLOCK);
        errdefer std.os.linux.close(fd);

        return LinuxWatcher{
            .allocator = allocator,
            .io = io,
            .wd_to_path = .init(allocator),
            .path_to_wd = .init(allocator),
            .file_count = 0,
            .fd = @intCast(fd),
            .callback = null,
            .context = null,
            .running = false,
        };
    }

    pub fn deinit(self: *LinuxWatcher) void {
        self.stop();
        self.wd_to_path.deinit();
        self.path_to_wd.deinit();
        std.posix.close(self.fd);
    }

    pub fn addFile(self: *LinuxWatcher, path: [:0]const u8) !void {
        try self._addFile(path);
        self.file_count += 1;
    }

    fn _addFile(self: *LinuxWatcher, path: [:0]const u8) !void {
        const wd = std.os.linux.inotify_add_watch(
            self.fd,
            path,
            linux.IN.MODIFY | linux.IN.CLOSE_WRITE | linux.IN.ATTRIB | linux.IN.MOVE_SELF |
                linux.IN.DELETE_SELF | linux.IN.IGNORED,
        );

        if (wd == std.math.maxInt(u32)) {
            return error.BadF;
        }

        try self.wd_to_path.put(wd, path);
        try self.path_to_wd.put(path, @intCast(wd));
        self.file_count += 1;
    }

    pub fn removeFile(self: *LinuxWatcher, path: []const u8) !void {
        if (self.path_to_wd.get(path)) |wd| {
            _ = std.posix.inotify_rm_watch(self.fd, wd);
            _ = self.path_to_wd.remove(path);
            _ = self.wd_to_path.remove(wd);
            self.file_count -= 1;
        }
    }

    pub fn getNumberOfFilesBeingWatched(self: *LinuxWatcher) u32 {
        std.debug.assert(self.file_count == self.wd_to_path.count());
        std.debug.assert(self.file_count == self.path_to_wd.count());
        return self.file_count;
    }

    pub fn setCallback(
        self: *LinuxWatcher,
        callback: interfaces.Callback,
        context: ?*anyopaque,
    ) void {
        self.callback = callback;
        self.context = context;
    }

    pub fn start(self: *LinuxWatcher, opts: interfaces.Opts) !void {
        // TODO add polling instead of busy waiting
        if (self.file_count == 0) return error.NoFilesToWatch;

        self.running = true;
        var buffer: [65536]u8 = undefined;

        while (self.running) {
            const length = std.posix.read(
                self.fd,
                &buffer,
            ) catch |err| switch (err) {
                error.WouldBlock => {
                    try std.Io.sleep(self.io, .fromSeconds(@intFromFloat(opts.latency)), .cpu_thread);
                    continue;
                },
                else => {
                    return err;
                },
            };

            // in bytes
            var i: usize = 0;
            while (i < length) {
                const ev_ptr: *align(1) linux.inotify_event =
                    @ptrCast(buffer[i..][0..@sizeOf(linux.inotify_event)].ptr);

                const ev = ev_ptr.*;
                const step = @sizeOf(linux.inotify_event) + ev.len;

                const rec_size = @sizeOf(linux.inotify_event) + ev.len;
                if (i + rec_size > length) break;

                const path = self.wd_to_path.get(@intCast(ev.wd)) orelse break;

                // Editors like vim create temporary files when saving
                // So we have to re-add the file to the watcher
                if (ev.mask & (linux.IN.DELETE_SELF | linux.IN.MOVE_SELF |
                    linux.IN.IGNORED) != 0)
                {
                    _ = self.wd_to_path.remove(@intCast(ev.wd));
                    _ = self.path_to_wd.remove(path);
                    try self._addFile(path);
                }

                if (self.callback) |callback| try callback(self.context, path, .modified);

                i += step;
            }
        }
    }

    pub fn stop(self: *LinuxWatcher) void {
        self.running = false;
    }
};
