const std = @import("std");
const migraine = @import("interpreter.zig");
const io = std.io;

pub fn main() !void {
    const givenProgram = ",.,>.,.";

    var output = std.ArrayList(u8).init(std.heap.page_allocator);
    defer output.deinit();

    const interpreter = try migraine.Interpreter.init(std.heap.page_allocator);
    defer interpreter.deinit();
    std.debug.print("{s}\n\t{s}\n[OUTPUT]:\n\t", .{ "[PROGRAM]:", givenProgram });
    try interpreter.eval(givenProgram, io.getStdIn().reader(), io.getStdOut().writer(), null);
    std.debug.print("\n", .{});
}
