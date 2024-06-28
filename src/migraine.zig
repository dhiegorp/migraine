const interpreter_module = @import("interpreter.zig");

pub const Interpreter = interpreter_module.Interpreter;
pub const InterpreterDiagnostics = interpreter_module.InterpreterDiagnostics;
pub const loadProgram = interpreter_module.loadProgram;
