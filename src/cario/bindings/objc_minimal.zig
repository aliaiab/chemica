//! Objective-C runtime wrapper with platform-specific helpers
//! Provides BOOL conversion helpers and re-exports zig-objc functionality

const objc_full = @import("objc");

pub const c = objc_full.c;

/// On some targets, Objective-C uses `i8` instead of `bool`.
/// This helper casts a `bool` value to the target BOOL type.
pub fn boolParam(param: bool) c.BOOL {
    return switch (c.BOOL) {
        bool => param,
        i8 => @intFromBool(param),
        else => @compileError("unexpected boolean type"),
    };
}

/// On some targets, Objective-C uses `i8` instead of `bool`.
/// This helper casts a BOOL value to Zig `bool`.
pub fn boolResult(result: c.BOOL) bool {
    return switch (c.BOOL) {
        bool => result,
        i8 => result == 1,
        else => @compileError("unexpected boolean type"),
    };
}

// Re-export zig-objc types
pub const AutoreleasePool = objc_full.AutoreleasePool;
pub const Class = objc_full.Class;
pub const getClass = objc_full.getClass;
pub const getMetaClass = objc_full.getMetaClass;
pub const allocateClassPair = objc_full.allocateClassPair;
pub const registerClassPair = objc_full.registerClassPair;
pub const disposeClassPair = objc_full.disposeClassPair;
pub const Encoding = objc_full.Encoding;
pub const Iterator = objc_full.Iterator;
pub const Object = objc_full.Object;
pub const Property = objc_full.Property;
pub const Protocol = objc_full.Protocol;
pub const getProtocol = objc_full.getProtocol;
pub const sel = objc_full.sel;
pub const Sel = objc_full.Sel;
pub const free = objc_full.free;
pub const Block = objc_full.Block;
