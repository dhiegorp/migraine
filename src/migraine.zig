const std = @import("std");
const interpreter_module = @import("interpreter.zig");
const memory_module = @import("memory.zig");

pub const Interpreter = interpreter_module.Interpreter;
pub const InterpreterDiagnostics = interpreter_module.InterpreterDiagnostics;
pub const loadProgram = interpreter_module.loadProgram;
pub const memory = memory_module.StaticSizeMemory;

test {
    std.testing.refAllDeclsRecursive(@This());
}
