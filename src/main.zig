const std = @import("std");
const Allocator = std.mem.Allocator;
const migraine = @import("migraine.zig");
const argsproc = @import("argsproc.zig");
const CLI = @import("cli.zig");

///
/// migraine --help
///
pub fn main() !void {
    //const err = std.io.getStdErr().writer();
    //const out = std.io.getStdOut().writer();
    //const in = std.io.getStdIn().reader();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    try CLI.process(allocator);
}

test {
    _ = argsproc;
    _ = migraine;
}
