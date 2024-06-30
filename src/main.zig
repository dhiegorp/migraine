const std = @import("std");
const migraine = @import("migraine.zig");
const err = std.io.getStdErr().writer();
const out = std.io.getStdOut().writer();
const in = std.io.getStdIn().reader();

pub fn main() !void {
    try out.print("Migraine 0.0.1a\n", .{});
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    //when using windows

    var args = try std.process.argsWithAllocator(allocator);
    _ = args.skip();

    if (args.next()) |path_arg| {
        const loaded = try migraine.loadProgram(allocator, path_arg);
        var diagnostics = migraine.InterpreterDiagnostics{ .detailed_message = undefined, .failed_opcode = undefined };
        const interpreter = try migraine.Interpreter.init(allocator);
        try interpreter.eval(loaded, in, out, &diagnostics);
    } else {
        try err.print("No source file found!\nUsage: \n\tmigraine <program.bf>\n", .{});
        return;
    }
}
