const std = @import("std");
const lua = @import("lua.zig");

const Lua = lua.Lua;

pub fn main() !void {
    const vm = Lua.init();
    _ = vm;
    std.debug.print("Hello, world\n", .{});
}

test {
    _ = lua;
}
