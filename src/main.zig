const std = @import("std");
const Allocator = std.mem.Allocator;
const migraine = @import("migraine.zig");

///
/// migraine --help
///
const MIGRAINE = "Migraine";
const HELP = @embedFile("./metadata/.help");
const VERSION = @embedFile("./metadata/.version");
const ABOUT = @embedFile("./metadata/.about");

pub fn main() !void {
    const err = std.io.getStdErr().writer();
    const out = std.io.getStdOut().writer();
    const in = std.io.getStdIn().reader();

    try help(out);
    //try header(out);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    //to compile to windows its mandatory to use 'argsWithAllocator'
    var args = try std.process.argsWithAllocator(allocator);
    _ = args.skip();

    if (args.next()) |path_arg| {
        const loaded = try migraine.loadProgram(allocator, path_arg);
        var diagnostics = migraine.InterpreterDiagnostics{ .detailed_message = undefined, .failed_opcode = undefined };
        const interpreter = try migraine.Interpreter.init(allocator);
        interpreter.eval(loaded, in, out, &diagnostics) catch |er| {
            try err.print("{}:\n\t{s} {d}\n", .{ er, diagnostics.detailed_message, diagnostics.failed_opcode });
            return;
        };
    } else {
        try err.print("No source file found!\nUsage: \n\tmigraine <program.bf>\n", .{});
        return;
    }
}

fn version(writer: anytype) !void {
    try writer.print("{s}\n", .{VERSION});
}

fn header(writer: anytype) !void {
    try writer.print("{s} {s}\n", .{ MIGRAINE, VERSION });
}

fn help(writer: anytype) !void {
    try header(writer);
    try writer.print("{s}\n", .{HELP});
}

fn about(writer: anytype) !void {
    try header(writer);
    try writer.print("{s}\n", .{ABOUT});
}
