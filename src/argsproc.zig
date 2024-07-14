///
/// Rudimentary command line arguments 'parser'
///
const std = @import("std");
const Allocator = std.mem.Allocator;

const HELP_OPTION = "help";
const ABOUT_OPTION = "about";

///
/// InterpreterOptions represent the set of available commands
///
pub const InterpreterOptions = struct { help: bool = false, file: ?[]const u8 = null, eval: ?[]const u8 = null, verbose: bool = false, size: ?usize = null, dyna: bool = false, input: ?[]const u8 = null, inputDec: ?[]const u8 = null, alwaysFlush: bool = true, buffered: bool = false, about: bool = false };

///
/// Given a set of command line arguments, validate it matching the following patterns:
///  - options passed without values --<OPTION_VALUE> are stored as an entry in which K = <OPTION_NAME> and V = null; e.g, "--help"
///  - options with values following the pattern --<OPTION_NAME>=<VALUE> are stored as an entry in which K = <OPTION_NAME> and V=<VALUE>; e.g. "--file=example.bf"
///  - options followed by an equal sign and no value result in error; e.g. "--file="
///
pub fn preProcessArguments(allocator: Allocator, stdErr: anytype, args: [][]const u8) !std.StringHashMap(?[]const u8) {
    const symb_eq = "=";
    const symb_dd = "--";

    var argsMap = std.StringHashMap(?[]const u8).init(allocator);

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "")) {
            continue;
        }

        const equalIdx = std.mem.indexOf(u8, arg, symb_eq);
        const doubleDashIdx = std.mem.indexOf(u8, arg, symb_dd);

        if (doubleDashIdx) |dId| {
            if (equalIdx) |eId| {
                if (arg.len - 1 <= eId) {
                    try stdErr.print("\nError: '{s}' is not a valid command line option!", .{arg});
                    return error.InvalidArgumentFound;
                }
                try argsMap.putNoClobber(arg[dId + symb_dd.len .. eId], arg[eId + 1 ..]);
            } else {
                try argsMap.putNoClobber(arg[dId + symb_dd.len ..], null);
            }
        } else {
            try stdErr.print("\nError: '{s}' is not a valid command line option!", .{arg});
            return error.InvalidArgumentFound;
        }
    }

    return argsMap;
}

///
/// Given a map with arguments and values, fill InterpreterOptions.
/// The command line arguments must match the struct`s attributes name and The type of each attribute determines how it will be parsed, although
/// an error is not returned for a invalid value; e.g. --help=1234 , a bool attribute associated with an option mapped with an invalid value would
/// result in false instead of an error.
/// Another case of error is when the argsMap still has entries after the InterpreterOptions attributes` loop -- which means that invalid options
/// were passed.
///
pub fn processCmdArguments(argsMap: *std.StringHashMap(?[]const u8), options: *InterpreterOptions, stdErr: anytype) !void {
    if (argsMap.count() == 0) {
        //if no args, show help
        options.help = true;
        return;
    }
    if (argsMap.fetchRemove(HELP_OPTION)) |_| {
        //if help flag is detected, stops right away
        options.help = true;
        return;
    }

    if (argsMap.fetchRemove(ABOUT_OPTION)) |_| {
        options.about = true;
        return;
    }

    inline for (std.meta.fields(@TypeOf(options.*))) |field| {
        if (argsMap.contains(field.name)) {
            const entry = argsMap.fetchRemove(field.name);
            if (field.type == bool) {
                if (entry) |e| {
                    if (e.value) |val| {
                        @field(options, field.name) = std.mem.eql(u8, "true", val);
                    } else {
                        @field(options, field.name) = true;
                    }
                } else {
                    try stdErr.print("\nError: Expected value not assigned to option '--{s}'!", .{field.name});
                    return error.InvalidArgumentFound;
                }
            } else if (field.type == ?[]const u8) {
                if (entry) |e| {
                    @field(options, field.name) = e.value;
                } else {
                    try stdErr.print("\nError: Expected value not assigned to option '--{s}'!", .{field.name});
                    return error.InvalidArgumentFound;
                }
            }
        }
    }

    //check if there are any arguments left, which means its an error and generate some error messages!
    if (argsMap.count() > 0) {
        //still there are arguments not processed, so removeAll entries printing errors
        try stdErr.print("Error: option(s) found without resolution:\n\t", .{});
        var keys = argsMap.keyIterator();
        while (keys.next()) |key| {
            if (argsMap.fetchRemove(key.*)) |entry| {
                try stdErr.print("--{s}", .{entry.key});
                if (entry.value) |val| {
                    try stdErr.print("={s}", .{val});
                }
                try stdErr.print("\n", .{});
            }
        }
        return error.InvalidArgumentFound;
    }
}

test "preProcessArguments should return errors for invalid options args" {
    var errBuff = std.ArrayList(u8).init(std.testing.allocator);
    defer errBuff.deinit();

    const mockStdErr = errBuff.writer();

    var args = [_][]const u8{"-field"};
    try std.testing.expectError(error.InvalidArgumentFound, preProcessArguments(std.testing.allocator, mockStdErr, &args));
    try std.testing.expect(errBuff.items.len > 0);
    errBuff.clearAndFree();

    args = [_][]const u8{"-field=test"};
    try std.testing.expectError(error.InvalidArgumentFound, preProcessArguments(std.testing.allocator, mockStdErr, &args));
    try std.testing.expect(errBuff.items.len > 0);
    errBuff.clearAndFree();

    args = [_][]const u8{"field"};
    try std.testing.expectError(error.InvalidArgumentFound, preProcessArguments(std.testing.allocator, mockStdErr, &args));
    try std.testing.expect(errBuff.items.len > 0);
    errBuff.clearAndFree();

    args = [_][]const u8{"field=mockery"};
    try std.testing.expectError(error.InvalidArgumentFound, preProcessArguments(std.testing.allocator, mockStdErr, &args));
    try std.testing.expect(errBuff.items.len > 0);
    errBuff.clearAndFree();

    args = [_][]const u8{"--field="};
    try std.testing.expectError(error.InvalidArgumentFound, preProcessArguments(std.testing.allocator, mockStdErr, &args));
    try std.testing.expect(errBuff.items.len > 0);
    errBuff.clearAndFree();
}

test "preProcessArguments - when no args passed then should result in empty map" {
    var args = [_][]const u8{""};

    var errBuff = std.ArrayList(u8).init(std.testing.allocator);
    defer errBuff.deinit();
    const mockStdErr = errBuff.writer();

    var map = try preProcessArguments(std.testing.allocator, mockStdErr, &args);
    defer {
        var keys = map.keyIterator();
        while (keys.next()) |k| std.testing.allocator.free(k.*);
        map.deinit();
    }

    try std.testing.expectEqual(0, map.count());

    try std.testing.expect(errBuff.items.len == 0);
}

test "preProcessArguments - when supported options passed then should map each one successfully" {
    const expectedKeys = [_][]const u8{ "flag1", "key", "flag2", "flag3", "flag4" };
    const expectedValues = [_]?[]const u8{ null, "value", null, "false", "true" };

    var args = [_][]const u8{ "--flag1", "--key=value", "--flag2", "--flag3=false", "--flag4=true" };

    var errBuff = std.ArrayList(u8).init(std.testing.allocator);
    defer errBuff.deinit();
    const mockStdErr = errBuff.writer();

    var map = try preProcessArguments(std.testing.allocator, mockStdErr, &args);
    defer map.deinit();

    try std.testing.expectEqual(expectedKeys.len, map.count());

    for (expectedKeys, 0..) |k, idx| {
        try std.testing.expect(map.contains(k));

        const mappedValue = map.get(k);
        try std.testing.expect(mappedValue != null);

        if (mappedValue) |val| {
            if (val) |v| {
                try std.testing.expectEqualStrings(v, expectedValues[idx].?);
            } else {
                try std.testing.expect(expectedValues[idx] == null and val == null);
            }
        }
    }

    //ensure that no error message written to buffer
    try std.testing.expect(errBuff.items.len == 0);
}

test "processCmdArguments - when setting option value string, then text is stored correctly at struct" {
    const expectedValue = "./example/os.bf";

    var argsMap = std.StringHashMap(?[]const u8).init(std.testing.allocator);
    defer {
        var keys = argsMap.keyIterator();
        while (keys.next()) |k| std.testing.allocator.free(k.*);
        argsMap.deinit();
    }

    try argsMap.putNoClobber("file", expectedValue);

    var errBuff = std.ArrayList(u8).init(std.testing.allocator);
    defer errBuff.deinit();

    const mockStdErr = errBuff.writer();

    const expected = InterpreterOptions{ .file = expectedValue };
    var actual = InterpreterOptions{};

    try processCmdArguments(&argsMap, &actual, mockStdErr);

    try std.testing.expectEqualDeep(expected, actual);

    try std.testing.expect(errBuff.items.len == 0);
}

test "processCmdArguments - when setting option flag equals to true, then flag is enabled" {
    var argsMap = std.StringHashMap(?[]const u8).init(std.testing.allocator);
    defer {
        var keys = argsMap.keyIterator();
        while (keys.next()) |k| std.testing.allocator.free(k.*);
        argsMap.deinit();
    }

    try argsMap.putNoClobber("verbose", "true");

    var errBuff = std.ArrayList(u8).init(std.testing.allocator);
    defer errBuff.deinit();

    const mockStdErr = errBuff.writer();

    const expected = InterpreterOptions{ .verbose = true };
    var actual = InterpreterOptions{};

    try processCmdArguments(&argsMap, &actual, mockStdErr);

    try std.testing.expectEqualDeep(expected, actual);

    try std.testing.expect(errBuff.items.len == 0);
}

test "processCmdArguments - when setting option flag equals to false, then flag is disabled" {
    var argsMap = std.StringHashMap(?[]const u8).init(std.testing.allocator);
    defer {
        var keys = argsMap.keyIterator();
        while (keys.next()) |k| std.testing.allocator.free(k.*);
        argsMap.deinit();
    }

    try argsMap.putNoClobber("alwaysFlush", "false");

    var errBuff = std.ArrayList(u8).init(std.testing.allocator);
    defer errBuff.deinit();

    const mockStdErr = errBuff.writer();

    const expected = InterpreterOptions{ .alwaysFlush = false };
    var actual = InterpreterOptions{};

    try processCmdArguments(&argsMap, &actual, mockStdErr);

    try std.testing.expectEqualDeep(expected, actual);

    try std.testing.expect(errBuff.items.len == 0);
}

test "processCmdArguments - when argsMap has help and other options, help has precedence" {
    var argsMap = std.StringHashMap(?[]const u8).init(std.testing.allocator);
    defer argsMap.deinit();

    try argsMap.putNoClobber(HELP_OPTION, null);
    try argsMap.putNoClobber(ABOUT_OPTION, null);
    try argsMap.putNoClobber("file", "./examples/ola_mundo.bf");

    var errBuff = std.ArrayList(u8).init(std.testing.allocator);
    defer errBuff.deinit();

    const mockStdErr = errBuff.writer();

    const expected = InterpreterOptions{ .help = true };
    var actual = InterpreterOptions{};

    try processCmdArguments(&argsMap, &actual, mockStdErr);

    try std.testing.expectEqualDeep(expected, actual);

    try std.testing.expect(errBuff.items.len == 0);
}

test "processCmdArguments - when argsMap has help option then should set options.help to true" {
    var argsMap = std.StringHashMap(?[]const u8).init(std.testing.allocator);
    defer {
        var keys = argsMap.keyIterator();
        while (keys.next()) |k| std.testing.allocator.free(k.*);
        argsMap.deinit();
    }

    try argsMap.putNoClobber(HELP_OPTION, null);

    var errBuff = std.ArrayList(u8).init(std.testing.allocator);
    defer errBuff.deinit();

    const mockStdErr = errBuff.writer();

    const expected = InterpreterOptions{ .help = true };
    var actual = InterpreterOptions{};

    try processCmdArguments(&argsMap, &actual, mockStdErr);

    try std.testing.expectEqualDeep(expected, actual);

    try std.testing.expect(errBuff.items.len == 0);
}

test "processCmdArguments - when argsMap has about option then should set options.about to true" {
    var argsMap = std.StringHashMap(?[]const u8).init(std.testing.allocator);
    defer {
        var keys = argsMap.keyIterator();
        while (keys.next()) |k| std.testing.allocator.free(k.*);
        argsMap.deinit();
    }

    try argsMap.putNoClobber(ABOUT_OPTION, null);

    var errBuff = std.ArrayList(u8).init(std.testing.allocator);
    defer errBuff.deinit();

    const mockStdErr = errBuff.writer();

    const expected = InterpreterOptions{ .about = true };
    var actual = InterpreterOptions{};

    try processCmdArguments(&argsMap, &actual, mockStdErr);

    try std.testing.expectEqualDeep(expected, actual);

    try std.testing.expect(errBuff.items.len == 0);
}

test "processCmdArguments - when argsMap has unexpected arg then should return an error" {
    var argsMap = std.StringHashMap(?[]const u8).init(std.testing.allocator);
    defer {
        var keys = argsMap.keyIterator();
        while (keys.next()) |k| std.testing.allocator.free(k.*);
        argsMap.deinit();
    }

    try argsMap.putNoClobber("File", "./os.bf");

    var errBuff = std.ArrayList(u8).init(std.testing.allocator);
    defer errBuff.deinit();

    const mockStdErr = errBuff.writer();

    var actual = InterpreterOptions{};

    try std.testing.expectError(error.InvalidArgumentFound, processCmdArguments(&argsMap, &actual, mockStdErr));
    try std.testing.expect(actual.file == null);
    try std.testing.expect(errBuff.items.len > 0);
}

test "processCmdArguments - when argsMap is empty then should set options.help to true" {
    var argsMap = std.StringHashMap(?[]const u8).init(std.testing.allocator);
    defer argsMap.deinit();

    var errBuff = std.ArrayList(u8).init(std.testing.allocator);
    defer errBuff.deinit();

    const mockStdErr = errBuff.writer();

    const expected = InterpreterOptions{ .help = true };
    var actual = InterpreterOptions{};

    try processCmdArguments(&argsMap, &actual, mockStdErr);

    try std.testing.expectEqualDeep(expected, actual);

    try std.testing.expect(errBuff.items.len == 0);
}
