const interpreter_module = @import("interpreter.zig");
const memory_module = @import("memory.zig");

pub const Interpreter = interpreter_module.Interpreter;
pub const InterpreterDiagnostics = interpreter_module.InterpreterDiagnostics;
pub const loadProgram = interpreter_module.loadProgram;

test {
    _ = interpreter_module;
    _ = memory_module;
}
