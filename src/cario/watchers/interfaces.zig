pub const Event = enum { modified };
pub const Callback = fn (context: ?*anyopaque, path: [:0]const u8, event: Event) anyerror!void;
pub const Opts = struct { latency: f16 = 1.0 };
