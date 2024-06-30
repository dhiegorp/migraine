const std = @import("std");
const io = std.io;
const Writer = std.fs.File.Writer;
const Reader = std.fs.File.Reader;
const Allocator = std.mem.Allocator;
const testing = std.testing;
const mem = @import("memory.zig");

pub const InterpreterDiagnostics = struct { failed_opcode: usize, detailed_message: []const u8 };

const InterpreterPanic = error{
    UnbalancedJumpOperation,
    MemoryNotInitialized,
    MemoryAccessError,
    UnmappedJumpOperation,
};

///
/// if a pointer for a InterpreterDiagnostics is provided, it is filled with message and failed_opcode.
///
fn report(message: []const u8, failed_opcode: usize, diagnostics: ?*InterpreterDiagnostics) void {
    if (diagnostics) |diag| {
        diag.detailed_message = message;
        diag.failed_opcode = failed_opcode;
    }
}

///
/// Load the program from a file, given the path
///
pub fn loadProgram(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const metadata = try file.stat();

    const program = try file.readToEndAlloc(allocator, metadata.size);
    return program;
}

///
/// Eagerly maps the jumping pairs positions, analyzing if jumping operations are balanced throughout the entire program.
/// It populates a std.AutoHashMap(usize, usize) with the mapping of the indexes of opening brackets '[' and the equivalent closing instructions ']', and vice versa, based on the given 'program' string.
/// Maybe its possible to optimize it.
///
fn mapJumpOperations(allocator: std.mem.Allocator, map: *std.AutoHashMap(usize, usize), program: []const u8, diagnostics: ?*InterpreterDiagnostics) !void {
    var control = std.ArrayList(usize).init(allocator);
    defer control.deinit();

    for (program, 0..) |opcode, index| {
        switch (opcode) {
            '[' => {
                try control.append(index);
            },
            ']' => {
                if (control.popOrNull()) |opening_idx| {
                    //double link '[' -> ']' and '[' <- ']'
                    try map.putNoClobber(opening_idx, index);
                    try map.putNoClobber(index, opening_idx);
                } else {
                    report("Unbalanced jump detected at position", index, diagnostics);
                    return InterpreterPanic.UnbalancedJumpOperation;
                }
            },
            else => {}, //ignore other symbols
        }
    }

    //if the control stack still has opening brackets, than an unbalanced error should be returned
    if (control.popOrNull()) |err_idx| {
        report("Unbalanced jump detected at position", err_idx, diagnostics);
        return InterpreterPanic.UnbalancedJumpOperation;
    }
}

pub const DEFAULT_MEMORY_CAPACITY: usize = 30000;

///
/// Interpreter controller structure.
///
pub const Interpreter = struct {
    memory: ?*mem.StaticSizeMemory,
    allocator: ?Allocator,

    ///
    /// Tries to instantiate an Interpreter with the given memory capacity.
    ///
    pub fn initWithCapacity(allocator: Allocator, memoryCapacity: usize) !*Interpreter {
        const static_mem = try mem.StaticSizeMemory.init(allocator, memoryCapacity);
        const ptr = try allocator.create(@This());
        ptr.allocator = allocator;
        ptr.memory = static_mem;
        return ptr;
    }

    ///
    /// Tries to instantiate an Interpreter with default memory capacity -- 30KB as in the original Brainfuck implementation.
    ///
    pub fn init(allocator: Allocator) !*Interpreter {
        return initWithCapacity(allocator, DEFAULT_MEMORY_CAPACITY);
    }

    pub fn deinit(self: *Interpreter) void {
        if (self.allocator) |alloc| {
            if (self.memory) |memory| {
                memory.deinit();
            }
            alloc.destroy(self);
        }
    }

    ///
    /// Execute the given program.
    /// Ideally it should use a 'step' function to allow 'interactive debugging'.
    ///
    pub fn eval(self: *Interpreter, program: []const u8, input: anytype, output: anytype, diagnostics: ?*InterpreterDiagnostics) anyerror!void {
        if (self.allocator) |alloc| {
            var mapping = std.AutoHashMap(usize, usize).init(alloc);
            defer mapping.deinit();

            try mapJumpOperations(alloc, &mapping, program, diagnostics);

            var pc: usize = 0;

            if (self.memory) |memory| {
                while (pc < program.len) {
                    const opcode = program[pc];
                    switch (opcode) {
                        '<' => try memory.shiftLeft(),
                        '>' => try memory.shiftRight(),
                        '+' => try memory.increment(),
                        '-' => try memory.decrement(),
                        ']' => {
                            if (try memory.read()) |cell_value| {
                                if (cell_value > 0) {
                                    if (mapping.get(pc)) |matching_pos| {
                                        pc = matching_pos;
                                        continue;
                                    } else {
                                        report("Impossible to find a match for the closing bracket", pc, diagnostics);
                                        return InterpreterPanic.UnmappedJumpOperation;
                                    }
                                }
                            } else {
                                report("Impossible to evaluate jump. A problem occurred while accessing the current memory cell.", pc, diagnostics);
                                return InterpreterPanic.MemoryAccessError;
                            }
                        },
                        '[' => {
                            if (try memory.read()) |cell_value| {
                                if (cell_value == 0) {
                                    if (mapping.get(pc)) |matching_pos| {
                                        pc = matching_pos;
                                        continue;
                                    } else {
                                        report("Impossible to find a match for the opening bracket", pc, diagnostics);
                                        return InterpreterPanic.UnmappedJumpOperation;
                                    }
                                }
                            } else {
                                report("Impossible to evaluate jump. A problem occurred while accessing the current memory cell.", pc, diagnostics);
                                return InterpreterPanic.MemoryAccessError;
                            }
                        },
                        '.' => {
                            if (try memory.read()) |cell_value| {
                                try output.writeByte(cell_value);
                            } else {
                                report("Impossible to output value. A problem occurred while accessing the current memory cell.", pc, diagnostics);
                                return InterpreterPanic.MemoryAccessError;
                            }
                        },
                        ',' => {
                            const byte = input.readByte() catch 0;
                            try memory.write(byte);
                        },
                        else => {
                            //every other symbol MUST be ignored and should be interpreted as comments
                        },
                    }
                    pc += 1;
                }
            } else {
                //TODO changing report to not rely on opcode references
                report("Impossible to increment. Memory was not initialized.", 0, diagnostics);
                return InterpreterPanic.MemoryNotInitialized;
            }
        }
    }
};

test "empty program should not register any jump mappings" {
    const givenProgram = "";
    const expected = 0;

    var mapping = std.AutoHashMap(usize, usize).init(testing.allocator);
    defer mapping.deinit();

    try mapJumpOperations(testing.allocator, &mapping, givenProgram, null);

    try testing.expect(expected == mapping.count());
}

test "balanced brackets: program with deep structure must result in hashmap with all 'linked jumps'" {
    const givenProgram = "[[[[[[[[[[[]]]]]]]]]][[[[[[[[[[[[[[[[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]]]]]]]]]]]]]]]][[[[[[[[[]]]]]]]]]][[[[[[[[[[]]]]]]]]]][[[[[[[[[[]]]]]]]]]][[[[[]]]]]";
    const expectedLinks = 150;

    var mapping = std.AutoHashMap(usize, usize).init(testing.allocator);
    defer mapping.deinit();

    try mapJumpOperations(testing.allocator, &mapping, givenProgram, null);

    try testing.expectEqual(expectedLinks, mapping.count());
}

test "balanced brackets: program with simple structure should result in hashmap with 'linked jumps'" {
    const givenProgram = "[+]";

    var mapping = std.AutoHashMap(usize, usize).init(testing.allocator);
    defer mapping.deinit();

    try mapJumpOperations(testing.allocator, &mapping, givenProgram, null);

    try testing.expectEqual(2, mapping.get(0).?);
    try testing.expectEqual(0, mapping.get(2).?);
}

test "unbalanced brackets: must result in error" {
    const givenProgram = "++[++++><><><>><+++<<-][+[]>++++";
    const expectedPosition: usize = 23;

    var diag = InterpreterDiagnostics{ .detailed_message = undefined, .failed_opcode = undefined };
    var mapping = std.AutoHashMap(usize, usize).init(testing.allocator);
    defer mapping.deinit();

    try testing.expectError(InterpreterPanic.UnbalancedJumpOperation, mapJumpOperations(testing.allocator, &mapping, givenProgram, &diag));
    try testing.expectEqual(expectedPosition, diag.failed_opcode);
}

test "unbalanced brackets: inverted jump opcodes must result in error" {
    const givenProgram = "+][.";
    var diag = InterpreterDiagnostics{ .detailed_message = undefined, .failed_opcode = undefined };
    var mapping = std.AutoHashMap(usize, usize).init(testing.allocator);
    defer mapping.deinit();

    try testing.expectError(InterpreterPanic.UnbalancedJumpOperation, mapJumpOperations(testing.allocator, &mapping, givenProgram, &diag));
    try testing.expectEqual(1, diag.failed_opcode);
}

test "report errors: setting values must work" {
    var diag = InterpreterDiagnostics{ .detailed_message = undefined, .failed_opcode = 0 };
    const expectedMessage = "an diag message";
    const failedIndex = 82;
    report(expectedMessage, failedIndex, &diag);

    try testing.expectEqualStrings(expectedMessage, diag.detailed_message);
    try testing.expectEqual(failedIndex, diag.failed_opcode);
}

test "eval 'hello world' program should output correctly" {
    const givenProgram = ">++++++++[<+++++++++>-]<.>++++[<+++++++>-]<+.+++++++..+++.>>++++++[<+++++++>-]<++.------------.>++++++[<+++++++++>-]<+.<.+++.------.--------.>>>++++[<++++++++>-]<+.";

    var output = std.ArrayList(u8).init(testing.allocator);
    defer output.deinit();

    const interpreter = try Interpreter.init(testing.allocator);
    defer interpreter.deinit();

    try interpreter.eval(givenProgram, io.getStdIn().reader(), output.writer(), null);

    const actualString = try output.toOwnedSlice();
    defer testing.allocator.free(actualString);

    try testing.expectEqualStrings("Hello, World!", actualString);
}

test "loadProgram on an empty path should return an error" {
    //given an empty path should result in error
    try testing.expectError(std.fs.File.OpenError.FileNotFound, loadProgram(testing.allocator, ""));
}

test "loadProgram on an non existant path should return an error" {
    const unvalid_path = "./x/y/mockery.bf";

    //given an non-existant path should result in error
    try testing.expectError(std.fs.File.OpenError.FileNotFound, loadProgram(testing.allocator, unvalid_path));
}

fn mkTestFile(tempDir: testing.TmpDir, name: []const u8, content: []const u8) !std.fs.File {
    var tempFile = try tempDir.dir.createFile(name, .{});
    try tempFile.writeAll(content);
    return tempFile;
}

test "loadProgram on a valid file should read program content" {
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const expectedFileName = "countdown.bf";

    const content = "++++[>+++++<-]>[<+++++>-]+<+[>[>+>+<<-]++>>[<<+>>-]>>>[-]++>[-]+>>>+[[-]++++++>>>]<<<[[<++++++++<++>>-]+<.<[>----<-]<]<<[>>>>>[>>>[-]+++++++++<[>-<-]+++++++++>[-[<->-]+[<<<]]<[>+<-]>]<<-]<<-]";

    const programFile = try mkTestFile(tmp_dir, expectedFileName, content);
    defer programFile.close();

    const pathToDir = try tmp_dir.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(pathToDir);

    const pathToProgram = try std.fmt.allocPrint(testing.allocator, "{s}/{s}", .{ pathToDir, expectedFileName });
    defer testing.allocator.free(pathToProgram);

    const loaded = try loadProgram(testing.allocator, pathToProgram);
    defer testing.allocator.free(loaded);

    try testing.expectEqualStrings(content, loaded);
}
