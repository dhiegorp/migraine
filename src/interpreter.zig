const std = @import("std");
const io = std.io;
const Writer = std.fs.File.Writer;
const Reader = std.fs.File.Reader;
const Allocator = std.mem.Allocator;
const testing = std.testing;
const mem = @import("memory.zig");

pub const InterpreterDiagnostics = struct {
    failed_opcode: ?usize = null,
    detailed_message: ?[]const u8 = null,
};

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

    switch (metadata.kind) {
        .directory => return error.CannotLoadProgramFromDirectory,
        .file => return try file.readToEndAlloc(allocator, metadata.size),
        else => unreachable,
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
    memory: *mem.StaticSizeMemory,
    allocator: Allocator,

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
        self.memory.deinit();
        self.allocator.destroy(self);
    }

    pub fn step(self: *Interpreter, program: []const u8, mapping: anytype, input: anytype, output: anytype, diagnostics: ?*InterpreterDiagnostics, instr_pointer: *usize) anyerror!void {
        if (instr_pointer.* < program.len) {
            const opcode = program[instr_pointer.*];
            switch (opcode) {
                '<' => self.memory.shiftLeft() catch |err| {
                    switch (err) {
                        mem.MemoryPanic.RangeUnderflow => report("A shift left instruction caused an underflow at position", opcode, diagnostics),
                        mem.MemoryPanic.ShiftOperationError => report("An undefined behaviour occurred while performing a shift left operation at position ", opcode, diagnostics),
                        else => {},
                    }
                    return err;
                },
                '>' => self.memory.shiftRight() catch |err| {
                    switch (err) {
                        mem.MemoryPanic.RangeUnderflow => report("A shift left instruction caused an underflow at position", opcode, diagnostics),
                        mem.MemoryPanic.ShiftOperationError => report("An undefined behaviour occurred while performing a shift left operation at position ", opcode, diagnostics),
                        else => {},
                    }
                    return err;
                },
                '+' => try self.memory.increment(),
                '-' => try self.memory.decrement(),
                ']' => {
                    const cell_value = self.memory.read() catch |er| {
                        report("Impossible to evaluate jump. A problem occurred while accessing the current memory cell.", instr_pointer.*, diagnostics);
                        return er;
                    };
                    if (cell_value > 0) {
                        if (mapping.get(instr_pointer.*)) |matching_pos| {
                            instr_pointer.* = matching_pos;
                            return;
                        } else {
                            report("Impossible to find a match for the closing bracket", instr_pointer.*, diagnostics);
                            return InterpreterPanic.UnmappedJumpOperation;
                        }
                    }
                },
                '[' => {
                    const cell_value = self.memory.read() catch |er| {
                        report("Impossible to evaluate jump. A problem occurred while accessing the current memory cell.", instr_pointer.*, diagnostics);
                        return er;
                    };
                    if (cell_value == 0) {
                        if (mapping.get(instr_pointer.*)) |matching_pos| {
                            instr_pointer.* = matching_pos;
                            return;
                        } else {
                            report("Impossible to find a match for the opening bracket", instr_pointer.*, diagnostics);
                            return InterpreterPanic.UnmappedJumpOperation;
                        }
                    }
                },
                '.' => {
                    const cell_value = self.memory.read() catch |er| {
                        report("Impossible to output value. A problem occurred while accessing the current memory cell.", instr_pointer.*, diagnostics);
                        return er;
                    };
                    try output.writeByte(cell_value);
                },
                ',' => {
                    try output.print("\n\tin: ", .{});
                    const byte = input.readByte() catch 0;
                    try self.memory.write(byte);
                },
                else => {
                    //every other symbol MUST be ignored and should be interpreted as comments
                },
            }
        }
    }

    ///
    /// Execute the given program.
    /// Ideally it should use a 'step' function to allow 'interactive debugging'.
    ///
    pub fn eval(self: *Interpreter, program: []const u8, input: anytype, output: anytype, diagnostics: ?*InterpreterDiagnostics) anyerror!void {
        var mapping = std.AutoHashMap(usize, usize).init(self.allocator);
        defer mapping.deinit();

        try mapJumpOperations(self.allocator, &mapping, program, diagnostics);
        var init_counter: usize = 0;
        const pc: *usize = &init_counter;

        while (pc.* < program.len) {
            try step(self, program, &mapping, input, output, diagnostics, pc);
            pc.* += 1;
        }
    }
};

test "mapJumpOperations - empty program should not register any jump mappings" {
    const givenProgram = "";
    const expected = 0;

    var mapping = std.AutoHashMap(usize, usize).init(testing.allocator);
    defer mapping.deinit();

    try mapJumpOperations(testing.allocator, &mapping, givenProgram, null);

    try testing.expect(expected == mapping.count());
}

test "mapJumpOperations - balanced brackets: program with deep structure must result in hashmap with all 'linked jumps'" {
    const givenProgram = "[[[[[[[[[[[]]]]]]]]]][[[[[[[[[[[[[[[[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]]]]]]]]]]]]]]]][[[[[[[[[]]]]]]]]]][[[[[[[[[[]]]]]]]]]][[[[[[[[[[]]]]]]]]]][[[[[]]]]]";
    const expectedLinks = 150;

    var mapping = std.AutoHashMap(usize, usize).init(testing.allocator);
    defer mapping.deinit();

    try mapJumpOperations(testing.allocator, &mapping, givenProgram, null);

    try testing.expectEqual(expectedLinks, mapping.count());
}

test "mapJumpOperations - balanced brackets: program with simple structure should result in hashmap with 'linked jumps'" {
    const givenProgram = "[+]";

    var mapping = std.AutoHashMap(usize, usize).init(testing.allocator);
    defer mapping.deinit();

    try mapJumpOperations(testing.allocator, &mapping, givenProgram, null);

    try testing.expectEqual(2, mapping.get(0).?);
    try testing.expectEqual(0, mapping.get(2).?);
}

test "mapJumpOperations - unbalanced brackets: must result in error" {
    const givenProgram = "++[++++><><><>><+++<<-][+[]>++++";
    const expectedPosition: usize = 23;

    var diag = InterpreterDiagnostics{};
    var mapping = std.AutoHashMap(usize, usize).init(testing.allocator);
    defer mapping.deinit();

    try testing.expectError(InterpreterPanic.UnbalancedJumpOperation, mapJumpOperations(testing.allocator, &mapping, givenProgram, &diag));
    try testing.expectEqual(expectedPosition, diag.failed_opcode);
}

test "mapJumpOperations - unbalanced brackets: inverted jump opcodes must result in error" {
    const givenProgram = "+][.";
    var diag = InterpreterDiagnostics{};
    var mapping = std.AutoHashMap(usize, usize).init(testing.allocator);
    defer mapping.deinit();

    try testing.expectError(InterpreterPanic.UnbalancedJumpOperation, mapJumpOperations(testing.allocator, &mapping, givenProgram, &diag));
    try testing.expectEqual(1, diag.failed_opcode);
}

test "report - setting values must work" {
    var diag = InterpreterDiagnostics{};
    const expectedMessage = "an diag message";
    const failedIndex = 82;
    report(expectedMessage, failedIndex, &diag);

    try testing.expectEqualStrings(expectedMessage, diag.detailed_message.?);
    try testing.expectEqual(failedIndex, diag.failed_opcode);
}

test "eval - 'hello world' program should output correctly" {
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

test "loadProgram - on an empty path should return an error" {
    //given an empty path should result in error
    try testing.expectError(error.FileNotFound, loadProgram(testing.allocator, ""));
}

test "loadProgram - on an non existant path should return an error" {
    const unvalid_path = "./x/y/mockery.bf";

    //given an non-existant path should result in error
    try testing.expectError(error.FileNotFound, loadProgram(testing.allocator, unvalid_path));
}

test "loadProgram - on a directory should return an error" {
    try testing.expectError(error.CannotLoadProgramFromDirectory, loadProgram(testing.allocator, "./examples/"));
}

fn mkTestFile(tempDir: testing.TmpDir, name: []const u8, content: []const u8) !std.fs.File {
    var tempFile = try tempDir.dir.createFile(name, .{});
    try tempFile.writeAll(content);
    return tempFile;
}

test "loadProgram -  on a valid file should read program content" {
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
