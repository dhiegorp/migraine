const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

pub const MemoryPanic = error{
    RangeOverflow,
    RangeUnderflow,
    ReadOperationError,
    WriteOperationError,
    ShiftOperationError,
    HeadPointerError,
};

pub const StaticSizeMemory = struct {
    head: ?usize,
    allocator: ?Allocator,
    tape: ?[]u8,

    pub fn init(allocator: Allocator, numberOfCells: usize) !*StaticSizeMemory {
        const ptr = try allocator.create(@This());
        ptr.allocator = allocator;
        ptr.head = 0;
        ptr.tape = try allocator.alloc(u8, numberOfCells);
        @memset(ptr.tape.?, 0);
        return ptr;
    }

    pub fn deinit(self: *StaticSizeMemory) void {
        if (self.allocator) |alloc| {
            if (self.tape) |tape| {
                alloc.free(tape);
            }
            alloc.destroy(self);
        }
    }

    pub fn currentAddress(self: *StaticSizeMemory) ?usize {
        return self.head;
    }

    pub fn headTo(self: *StaticSizeMemory, address: usize) !void {
        if (self.tape) |tape| {
            if (tape.len > 0) {
                if (address > tape.len - 1) {
                    return MemoryPanic.RangeOverflow;
                }
                self.head = address;
                return;
            }
        }
        return MemoryPanic.HeadPointerError;
    }

    pub fn increment(self: *StaticSizeMemory) !void {
        if (self.tape) |tape| {
            if (tape.len > 0) {
                if (self.head) |head| {
                    tape[head] +%= 1;
                    return;
                }
            }
        }
        return MemoryPanic.WriteOperationError;
    }

    pub fn decrement(self: *StaticSizeMemory) !void {
        if (self.tape) |tape| {
            if (tape.len > 0) {
                if (self.head) |head| {
                    tape[head] -%= 1;
                    return;
                }
            }
        }
        return MemoryPanic.WriteOperationError;
    }

    pub fn shiftRight(self: *StaticSizeMemory) !void {
        if (self.tape) |tape| {
            if (self.head) |head| {
                if (head == tape.len - 1) {
                    return MemoryPanic.RangeOverflow;
                }
                self.head = head + 1;
                return;
            }
        }
        return MemoryPanic.ShiftOperationError;
    }

    pub fn shiftLeft(self: *StaticSizeMemory) !void {
        if (self.head) |head| {
            //logger.debug("[MEM][SHIFT_LEFT] FROM HEAD: {d} ", .{head});
            if (head == 0) {
                return MemoryPanic.RangeUnderflow;
            }
            self.head = head - 1;
            //logger.debug("[MEM][SHIFT_LEFT] TO HEAD: {d} ", .{head});
            return;
        }
        return MemoryPanic.ShiftOperationError;
    }

    pub fn write(self: *StaticSizeMemory, data: u8) !void {
        if (self.tape) |tape| {
            if (tape.len > 0) {
                if (self.head) |head| {
                    tape[head] = data;
                    return;
                }
            }
        }
        return MemoryPanic.WriteOperationError;
    }

    pub fn read(self: *StaticSizeMemory) !?u8 {
        if (self.tape) |tape| {
            if (tape.len > 0) {
                if (self.head) |head| {
                    return tape[head];
                }
            }
        }
        return MemoryPanic.ReadOperationError;
    }
};

test "StaticSizeMemory - currentAddress should return the exact value from the head" {
    var mem = try StaticSizeMemory.init(testing.allocator, 10);
    defer mem.deinit();

    try mem.headTo(9);
    try testing.expectEqual(9, mem.currentAddress().?);

    try mem.headTo(0);
    try testing.expectEqual(0, mem.currentAddress().?);

    try mem.headTo(5);
    try testing.expectEqual(5, mem.currentAddress().?);

    try mem.headTo(3);
    try testing.expectEqual(3, mem.currentAddress().?);
}

test "StaticSizeMemory - decrement on an invalid memory should return an error" {
    var mem = try StaticSizeMemory.init(testing.allocator, 0);
    defer mem.deinit();

    try testing.expectError(MemoryPanic.WriteOperationError, mem.decrement());
}

test "StaticSizeMemory - decrement should subtract one from the stored value at the current address" {
    var mem = try StaticSizeMemory.init(testing.allocator, 1);
    defer mem.deinit();

    try mem.write(5);

    try mem.decrement();

    try testing.expect(4 == try mem.read());
}

test "StaticSizeMemory - decrement should handle integer overflow without returning errors" {
    var mem = try StaticSizeMemory.init(testing.allocator, 1);
    defer mem.deinit();

    try mem.decrement(); //given that each memory cell is of type u8, and initialized with zero, the next value should be 255
    try testing.expectEqual(255, try mem.read());
}

test "StaticSizeMemory - increment should handle integer overflow without returning errors" {
    var mem = try StaticSizeMemory.init(testing.allocator, 1);
    defer mem.deinit();

    try mem.write(255); //given that each memory cell is of type u8, the next value should be 0
    try mem.increment();
    try testing.expectEqual(0, try mem.read());
}

test "StaticSizeMemory - increment on an invalid memory should return an error" {
    var mem = try StaticSizeMemory.init(testing.allocator, 0);
    defer mem.deinit();

    try testing.expectError(MemoryPanic.WriteOperationError, mem.increment());
}

test "StaticSizeMemory - increment should add one to the stored value at the current address" {
    var mem = try StaticSizeMemory.init(testing.allocator, 1);
    defer mem.deinit();

    try mem.increment();

    try testing.expect(1 == try mem.read());
}

test "StaticSizeMemory - write in an invalid memory should return an error" {
    var mem = try StaticSizeMemory.init(testing.allocator, 0);
    defer mem.deinit();

    try testing.expectError(MemoryPanic.WriteOperationError, mem.write(10));
}

test "StaticSizeMemory - write in a valid memory position should store the value" {
    var mem = try StaticSizeMemory.init(testing.allocator, 1);
    defer mem.deinit();

    try testing.expect(0 == try mem.read());

    try mem.write(100);

    try testing.expect(100 == try mem.read());
}

test "StaticSizeMemory - read should return zero for recently init memory" {
    var mem = try StaticSizeMemory.init(testing.allocator, 5);
    defer mem.deinit();

    comptime var i = 0;
    inline while (i < 5) : (i += 1) {
        try mem.headTo(i);
        try testing.expectEqual(0, mem.read());
    }
}

test "StaticSizeMemory - read in an invalid memory should return an error" {
    var mem = try StaticSizeMemory.init(testing.allocator, 0);
    defer mem.deinit();

    try testing.expectError(MemoryPanic.ReadOperationError, mem.read());
}

test "StaticSizeMemory - memory should always initialize with head set to zero" {
    var mem = try StaticSizeMemory.init(testing.allocator, 1);
    var mem2 = try StaticSizeMemory.init(testing.allocator, 100);

    defer {
        mem.deinit();
        mem2.deinit();
    }

    try testing.expect(0 == mem.currentAddress());
    try testing.expect(0 == mem2.currentAddress());
}

test "StaticSizeMemory - memory with zero cells should work but is unusable" {
    var mem = try StaticSizeMemory.init(testing.allocator, 0);
    defer mem.deinit();

    try testing.expect(mem.tape.?.len == 0);
}

test "StaticSizeMemory - call headTo without memory cells should return error" {
    const mem = try StaticSizeMemory.init(testing.allocator, 0);
    defer mem.deinit();
    errdefer mem.deinit();

    try testing.expectError(MemoryPanic.HeadPointerError, mem.headTo(1));
}

test "StaticSizeMemory - set head to an address outside the valid memory range should return an error" {
    const mem = try StaticSizeMemory.init(testing.allocator, 1);
    defer mem.deinit();
    try testing.expectError(MemoryPanic.RangeOverflow, mem.headTo(1));
}

test "StaticSizeMemory - set head to an 'address' should update head correctly" {
    const mem = try StaticSizeMemory.init(testing.allocator, 10);
    defer mem.deinit();

    try mem.headTo(1);
    try testing.expect(mem.currentAddress().? == 1);
    try mem.headTo(9);
    try testing.expect(mem.currentAddress().? == 9);
    try mem.headTo(5);
    try testing.expect(mem.currentAddress().? == 5);
    try mem.headTo(0);
    try testing.expect(mem.currentAddress().? == 0);
}

test "StaticSizeMemory - shift left should work while head is pointing to an address greater than zero" {
    const mem = try StaticSizeMemory.init(testing.allocator, 10);
    defer mem.deinit();

    try mem.headTo(5); //set head to 5
    try mem.shiftLeft(); //should've set head to 4
    try mem.shiftLeft(); //should've set head to 3
    try mem.shiftLeft(); //should've set head to 2
    try mem.shiftLeft(); //should've set head to 1
    try mem.shiftLeft(); //should've set head to 0

    try testing.expectEqual(0, mem.currentAddress().?);

    try testing.expectError(MemoryPanic.RangeUnderflow, mem.shiftLeft());
}

test "StaticSizeMemory - shift left when head is zero should result in underflow" {
    const mem = try StaticSizeMemory.init(testing.allocator, 1);
    defer mem.deinit();
    try testing.expectError(MemoryPanic.RangeUnderflow, mem.shiftLeft());
}

test "StaticSizeMemory - shift right when head is set to last memory cell should result in overflow" {
    const mem = try StaticSizeMemory.init(testing.allocator, 1);
    defer mem.deinit();
    try testing.expectError(MemoryPanic.RangeOverflow, mem.shiftRight());
}

test "StaticSizeMemory - shift right should work while head is not pointing to the end of the tape" {
    const mem = try StaticSizeMemory.init(testing.allocator, 10);
    defer mem.deinit();

    try mem.headTo(7); //set head to 7
    try mem.shiftRight(); //should've set head to 8
    try mem.shiftRight(); //should've set head to 9

    try testing.expectEqual(9, mem.currentAddress().?);

    try testing.expectError(MemoryPanic.RangeOverflow, mem.shiftRight());
}
