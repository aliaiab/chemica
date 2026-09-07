child_allocator: gpu.mem.Allocator,
blocks: std.ArrayList(Block) = .empty,

pub fn reset(self: ArenaAllocator, mode: ResetMode) bool {
    _ = mode; // autofix
    _ = self; // autofix
    return true;
}

pub fn allocator(self: ArenaAllocator) gpu.mem.Allocator {
    _ = self; // autofix
    return undefined;
}

pub const Block = struct {
    memory: []u8,
    position: u64,
};

pub const ResetMode = union(enum) {
    /// Releases all allocated memory in the arena.
    free_all,
    /// This will pre-heat the arena for future allocations by allocating a
    /// large enough buffer for all previously done allocations.
    /// Preheating will speed up the allocation process by invoking the backing allocator
    /// less often than before. If `reset()` is used in a loop, this means that after the
    /// biggest operation, no memory allocations are performed anymore.
    retain_capacity,
    /// This is the same as `retain_capacity`, but the memory will be shrunk to
    /// this value if it exceeds the limit.
    retain_with_limit: usize,
};

const gpu = @import("../gpu.zig");
const std = @import("std");
const ArenaAllocator = @This();
