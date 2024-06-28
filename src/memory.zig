const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const static_memory = @import("static_memory.zig");

pub const StaticSizeMemory = static_memory.StaticSizeMemory;

pub const MemoryPanic = error{
    RangeOverflow,
    RangeUnderflow,
    ReadOperationError,
    WriteOperationError,
    ShiftOperationError,
    HeadPointerError,
};
