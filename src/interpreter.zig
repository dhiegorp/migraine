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

pub const Interpreter = struct {
    memory: ?*mem.StaticSizeMemory,
    allocator: ?Allocator,

    pub fn initWithCapacity(allocator: Allocator, memoryCapacity: usize) !*Interpreter {
        const static_mem = try mem.StaticSizeMemory.init(allocator, memoryCapacity);
        const ptr = try allocator.create(@This());
        ptr.allocator = allocator;
        ptr.memory = static_mem;
        return ptr;
    }

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
            while (pc < program.len) {
                const opcode = program[pc];
                switch (opcode) {
                    '<' => {
                        if (self.memory) |memory| {
                            try memory.shiftLeft();
                        }
                    },
                    '>' => {
                        if (self.memory) |memory| {
                            try memory.shiftRight();
                        }
                    },
                    '+' => {
                        if (self.memory) |memory| {
                            try memory.increment();
                        } else {
                            report("Impossible to increment. Memory was not initialized.", pc, diagnostics);
                            return InterpreterPanic.MemoryNotInitialized;
                        }
                    },
                    '-' => {
                        if (self.memory) |memory| {
                            try memory.decrement();
                        } else {
                            report("Impossible to decrement. Memory was not initialized.", pc, diagnostics);
                            return InterpreterPanic.MemoryNotInitialized;
                        }
                    },
                    ']' => {
                        if (self.memory) |memory| {
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
                        } else {
                            report("Impossible to evaluate jump. Memory was not initialized.", pc, diagnostics);
                            return InterpreterPanic.MemoryNotInitialized;
                        }
                    },
                    '[' => {
                        if (self.memory) |memory| {
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
                        } else {
                            report("Impossible to evaluate jump:  Memory was not initialized.", pc, diagnostics);
                            return InterpreterPanic.MemoryNotInitialized;
                        }
                    },
                    '.' => {
                        if (self.memory) |memory| {
                            if (try memory.read()) |cell_value| {
                                try output.writeByte(cell_value);
                            } else {
                                report("Impossible to output value. A problem occurred while accessing the current memory cell.", pc, diagnostics);
                                return InterpreterPanic.MemoryAccessError;
                            }
                        } else {
                            report("Impossible to read from memory:  Memory was not initialized.", pc, diagnostics);
                            return InterpreterPanic.MemoryNotInitialized;
                        }
                    },
                    ',' => {
                        if (self.memory) |memory| {
                            const byte = input.readByte() catch 0; //in case of input stream error, zero should be written
                            try memory.write(byte);
                        } else {
                            report("Impossible to write to memory:  Memory was not initialized", pc, diagnostics);
                            return InterpreterPanic.MemoryNotInitialized;
                        }
                    },
                    else => {
                        //every other symbol MUST be ignored and should be interpreted as comments
                    },
                }
                pc += 1;
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

test "report errors: settng values must work" {
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
    try testing.expectEqualStrings("Hello, World!\n", actualString);
}
