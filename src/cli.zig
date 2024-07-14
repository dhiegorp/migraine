const std = @import("std");
const Allocator = std.mem.Allocator;

const argsproc = @import("argsproc.zig");
const InterpreterOptions = argsproc.InterpreterOptions;

const migraine = @import("migraine.zig");
const InterpreterDiagnostics = migraine.InterpreterDiagnostics;

const MIGRAINE = "Migraine";
const HELP = @embedFile("./metadata/.help");
const VERSION = @embedFile("./metadata/.version");
const ABOUT = @embedFile("./metadata/.about");

pub fn version(writer: anytype) !void {
    try writer.print("{s}\n", .{VERSION});
}

pub fn header(writer: anytype) !void {
    try writer.print("{s} {s}\n", .{ MIGRAINE, VERSION });
}

pub fn help(writer: anytype) !void {
    try header(writer);
    try writer.print("{s}\n", .{HELP});
}

pub fn about(writer: anytype) !void {
    try header(writer);
    try writer.print("{s}\n", .{ABOUT});
}

pub fn process(allocator: Allocator) !void {
    const err = std.io.getStdErr().writer();
    const out = std.io.getStdOut().writer();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var argsMap = try argsproc.preProcessArguments(allocator, err, args[1..]);
    defer argsMap.deinit();

    var options = argsproc.InterpreterOptions{};

    try argsproc.processCmdArguments(&argsMap, &options, err);

    if (options.help) {
        try help(out);
    } else if (options.about) {
        try about(out);
    } else {
        const interpreter = try migraine.Interpreter.init(allocator);
        defer interpreter.deinit();

        var diagnostics = InterpreterDiagnostics{ .detailed_message = undefined, .failed_opcode = undefined };

        if (options.file) |path| {
            if (options.verbose) {
                try out.print("\tOpening '{s}'\n", .{path});
            }

            if (migraine.loadProgram(allocator, path)) |program| {
                const in = std.io.getStdIn().reader();
                interpreter.eval(program, in, out, &diagnostics) catch |e| {
                    try err.print("\nAn error occurred while interpreting '{s}'\n{}: \n\t{s}({d})", .{ path, e, diagnostics.detailed_message, diagnostics.failed_opcode });
                };
            } else |e| switch (e) {
                error.FileNotFound => {
                    try header(out);
                    err.print("\nCannot load program from file '{s}'\n", .{path}) catch unreachable;
                },
                error.CannotLoadProgramFromDirectory => {
                    try header(out);
                    err.print("\n'{s}' is a directory, not a valid brainfuck source-code file.\n", .{path}) catch unreachable;
                },
                else => {},
            }

            try out.print("\n", .{});
        }
    }
}
