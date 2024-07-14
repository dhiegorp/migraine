const std = @import("std");
const Allocator = std.mem.Allocator;
const migraine = @import("migraine.zig");
const argsproc = @import("argsproc.zig");
const CLI = @import("cli.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    try CLI.process(allocator);
}

test {
    std.testing.refAllDecls(@This());
}
