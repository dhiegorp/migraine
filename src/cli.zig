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
    try writer.print("{s}\n", .{HELP});
}

pub fn about(writer: anytype) !void {
    try writer.print("{s}\n", .{ABOUT});
}

pub fn process(allocator: Allocator) !void {
    const err = std.io.getStdErr().writer();
    const out = std.io.getStdOut().writer();

    header(out) catch unreachable;

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var argsMap = try argsproc.preProcessArguments(allocator, err, args[1..]);
    defer argsMap.deinit();

    var options = InterpreterOptions{};
    var diagnostics = InterpreterDiagnostics{ .detailed_message = undefined, .failed_opcode = undefined };

    try argsproc.processCmdArguments(&argsMap, &options, err);

    if (options.help) {
        help(out) catch unreachable;
    } else if (options.about) {
        about(out) catch unreachable;
    } else if (options.file == null and options.eval == null) {
        help(out) catch unreachable;
    } else if (options.file != null) {
        executeBFSourceFile(allocator, &options, &diagnostics);
        out.print("\n", .{}) catch unreachable;
    } else if (options.eval != null) {
        executeString(allocator, &options, &diagnostics);
        out.print("\n", .{}) catch unreachable;
    }
}

fn executeOnInterpreter(allocator: Allocator, program: []const u8, options: *InterpreterOptions, diagnostics: *InterpreterDiagnostics) !void {
    const in = std.io.getStdIn().reader();
    const out = std.io.getStdOut().writer();

    var interpreter: *migraine.Interpreter = undefined;

    if (options.size) |size| {
        if (options.verbose) out.print("Initializing memory with {d} B\n", .{size}) catch unreachable;
        interpreter = try migraine.Interpreter.initWithCapacity(allocator, size);
    } else {
        if (options.verbose) out.print("Initializing memory with 30 KB\n", .{}) catch unreachable;
        interpreter = try migraine.Interpreter.init(allocator);
    }
    defer interpreter.deinit();

    try interpreter.eval(program, in, out, diagnostics);
}

fn executeString(allocator: Allocator, options: *InterpreterOptions, diagnostics: *InterpreterDiagnostics) void {
    const err = std.io.getStdErr().writer();

    if (options.eval) |program| {
        executeOnInterpreter(allocator, program, options, diagnostics) catch {
            err.print("An error occurred while interpreting a program. \n\t{?s} ({?d})", .{ diagnostics.detailed_message, diagnostics.failed_opcode }) catch unreachable;
        };
    } else {
        err.print("\n Unexpected attempt to read a file without a path! ", .{}) catch unreachable;
    }
}

fn executeBFSourceFile(allocator: Allocator, options: *InterpreterOptions, diagnostics: *InterpreterDiagnostics) void {
    const out = std.io.getStdOut().writer();
    const err = std.io.getStdErr().writer();

    if (options.file) |path| {
        if (options.verbose) {
            out.print("\tOpening '{s}'\n", .{path}) catch unreachable;
        }
        if (migraine.loadProgram(allocator, path)) |program| {
            executeOnInterpreter(allocator, program, options, diagnostics) catch {
                err.print("An error occurred while interpreting a program. \n\t{?s} ({?d})", .{ diagnostics.detailed_message, diagnostics.failed_opcode }) catch unreachable;
            };
        } else |e| switch (e) {
            error.FileNotFound => {
                err.print("\nCannot load program from file '{s}'\n", .{path}) catch unreachable;
            },
            error.CannotLoadProgramFromDirectory => {
                header(out) catch unreachable;
                err.print("\n'{s}' is a directory, not a valid brainfuck source-code file.\n", .{path}) catch unreachable;
            },
            else => {
                header(out) catch unreachable;
                err.print("\nAn unexpected error occurred while loading '{s}'\n", .{path}) catch unreachable;
            },
        }
    } else {
        err.print("\n Unexpected attempt to read a file without a path! ", .{}) catch unreachable;
    }
}
