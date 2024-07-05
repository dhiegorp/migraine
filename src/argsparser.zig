const std = @import("std");
const Allocator = std.mem.Allocator;

const InterpreterOptions = struct {
    var help: bool = false;
    var file: ?[]const u8 = null;
    var eval: ?[]const u8 = null;
    var verbose: bool = false;
    var size: ?i32 = null;
    var dyna: bool = false;
    var input: ?[]const u8 = null;
    var inputDec: ?[]const u8 = null;
    var alwaysFlush: bool = true;
    var buffered: bool = false;
};

fn compareTermFlag(literal: []const u8, term: []const u8) bool {
    if (std.mem.indexOf(u8, term, literal)) |_| {
        return true;
    }
    return false;
}

fn recoverArgValue(term: []const u8) ?[]const u8 {
    if (std.mem.indexOf(u8, term, "=")) |pos| {
        return term[pos..];
    }
    return null;
}

pub fn main() !void {}

pub fn parseArguments(allocator: Allocator, options: anytype) !void {
    var Type = @TypeOf(options);
    var typeInfo = @typeInfo(Type);

    if (typeInfo != .Pointer) {
        return error.InvalidOptionsTypePointer;
    } else {
        Type = @TypeOf(options.*);
        typeInfo = @typeInfo(Type);

        if (typeInfo != .Struct) {
            return error.InvalidOptionsType;
        }
    }

    var args = try std.process.argsWithAllocator(allocator);
    _ = args.skip(); //skipping the program`s name!

    var double_dash: ?usize = null;
    var equal: ?usize = null;

    while (args.next()) |term| {
        double_dash = std.mem.indexOf(u8, term, "--");
        equal = std.mem.indexOf(u8, term, "=");

        if (double_dash != null and equal != null) {
            //*
            //* is option. if no value is provided, evaluate the case: ignore
            //*

        } else if (double_dash != null and equal == null) {
            //* is flag
        } else {
            //* invalid
        }
    }
}
