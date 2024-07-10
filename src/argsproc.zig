const std = @import("std");
const Allocator = std.mem.Allocator;

const InterpreterOptions = struct { help: bool = false, file: ?[]const u8 = null, eval: ?[]const u8 = null, verbose: bool = false, size: ?usize = null, dyna: bool = false, input: ?[]const u8 = null, inputDec: ?[]const u8 = null, alwaysFlush: bool = true, buffered: bool = false };

const HELP_OPTION = "help";
const ABOUT_OPTION = "about";

fn compareTermFlag(literal: []const u8, term: []const u8) bool {
    return std.mem.indexOf(u8, term, literal) > 0 orelse false;
}

fn recoverArgValue(term: []const u8) ?[]const u8 {
    if (std.mem.indexOf(u8, term, "=")) |pos| {
        return term[pos..];
    }
    return null;
}

fn preProcessArguments(allocator: Allocator, stdErr: anytype, args: [][]const u8) !std.StringHashMap(?[]const u8) {
    const symb_eq = "=";
    const symb_dd = "--";

    var argsMap = std.StringHashMap(?[]const u8).init(allocator);

    for (args) |arg| {
        const equalIdx = std.mem.indexOf(u8, arg, symb_eq);
        const doubleDashIdx = std.mem.indexOf(u8, arg, symb_dd);

        if (doubleDashIdx) |dId| {
            if (equalIdx) |eId| {
                if (arg.len <= eId) {
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

fn processCmdArguments(argsMap: std.StringHashMap(?[]const u8), options: *InterpreterOptions, stdErr: anytype) !void {
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
        //there are argument errors
        //removeAll printing errors
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

test "preProcessArguments should return errors for invalid parse situations" {
    @panic("implement!");
}

test "preProcessArguments pre process options supported successfuly" {
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
