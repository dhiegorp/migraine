const std = @import("std");
const migraine = @import("migraine.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    //when using windows

    var args = try std.process.argsWithAllocator(allocator);

    _ = args.skip();

    var path_arg: []const u8 = undefined;

    if (args.next()) |arg| {
        path_arg = arg;
    }

    const interpreter = try migraine.Interpreter.init(allocator);
    const loaded = try migraine.loadProgram(allocator, path_arg);
    var diagnostics = migraine.InterpreterDiagnostics{ .detailed_message = undefined, .failed_opcode = undefined };

    try interpreter.eval(loaded, std.io.getStdIn().reader(), std.io.getStdOut().writer(), &diagnostics);
}
