const std = @import("std");
const Allocator = std.mem.Allocator;

const ArgTest = struct { file: ?[]const u8 = null, help: bool = false };

fn processCmd(alloc: Allocator) !std.StringHashMap(?[]const u8) {
    var args = try std.process.argsWithAllocator(alloc);
    _ = args.skip();

    var map = std.StringHashMap(?[]const u8).init(alloc);

    while (args.next()) |arg| {
        const eqIdx = std.mem.indexOf(u8, arg, "=");
        const ddashIdx = std.mem.indexOf(u8, arg, "--");
        if (eqIdx) |id| {
            std.debug.print("\n-- {s} --\n", .{arg[id + 1 ..]});
            try map.putNoClobber(arg[0..id], arg[id + 1 ..]);
        } else {
            try map.putNoClobber(arg, null);
        }
    }

    return map;
}

pub fn another(argstr: *ArgTest) !void {
    var map = try processCmd(std.heap.page_allocator);
    defer map.deinit();

    inline for (std.meta.fields(@TypeOf(argstr.*))) |field| {
        std.debug.print("name: {s}, type: {any}\n", .{ field.name, field.type });
        if (map.contains(field.name)) {
            if (field.type == bool) {
                @field(argstr, field.name) = true;
            } else if (field.type == ?[]const u8) {
                @field(argstr, field.name) = map.fetchRemove(field.name).?.value;
            }
        }
    }
}

pub fn main() !void {
    var argstr = ArgTest{};
    try another(&argstr);
    std.debug.print("\n\t: {any}, .file: {s}\n", .{ argstr, argstr.file.? });
}
