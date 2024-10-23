// Lua utils lib that we expose to our scripts
const std = @import("std");
const lua = @import("lua.zig");
const sql = @import("sql.zig");

fn encodeJsonValue(L: ?*lua.LuaState, writer: anytype) anyerror!void {
    const typ = lua.lua_type(L, -1);
    switch (typ) {
        .TABLE => {
            lua.lua_pushnil(L); // table is at -1
            if (lua.lua_next(L, -2) != 0) { // table at -2, nil at -1
                if (lua.lua_isnumber(L, -2)) { // table at -3, key at -2, value at -1
                    try writer.beginArray();

                    // then encode the the value
                    try encodeJsonValue(L, writer);
                    // pop the value
                    lua.lua_pop(L, 1);

                    // then keep encoding and popping until we're done
                    while (lua.lua_next(L, -2) != 0) {
                        try encodeJsonValue(L, writer);
                        lua.lua_pop(L, 1);
                    }

                    // finally end the array
                    try writer.endArray();
                } else {
                    try writer.beginObject();

                    // encode the key/value we ar ecurrently at
                    try writer.objectField(lua.cStrAsSlice(lua.lua_tostring(L, -2)));
                    try encodeJsonValue(L, writer);
                    lua.lua_pop(L, 1);

                    // keep encoding and popping
                    while (lua.lua_next(L, -2) != 0) {
                        const key = lua.cStrAsSlice(lua.lua_tostring(L, -2));
                        try writer.objectField(key);
                        try encodeJsonValue(L, writer);
                        lua.lua_pop(L, 1);
                    }

                    // then end the object
                    try writer.endObject();
                }
            } else {
                try writer.beginObject();
                try writer.endObject();
            }
        },
        .STRING => {
            const key = lua.cStrAsSlice(lua.lua_tostring(L, -1));
            try writer.write(key);
        },
        .NUMBER => {
            try writer.write(lua.lua_tonumber(L, -1));
        },
        .BOOLEAN => {
            try writer.write(lua.lua_toboolean(L, -1));
        },
        else => {
            std.log.err("TODO: handle type {any}", .{typ});
            return error.UnparsableJsonType;
        },
    }
}

fn encodeJsonInner(L: ?*lua.LuaState) !c_int {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const alloc = arena.allocator();

    var outStream = std.ArrayList(u8).init(alloc);
    var jsonWriter = std.json.writeStream(outStream.writer(), .{});
    try encodeJsonValue(L, &jsonWriter);
    // pop the argument when we are done with it
    lua.lua_pop(L, 1);

    // then push the return value
    lua.lua_pushlstring(L, @ptrCast(outStream.items.ptr), outStream.items.len);
    return 1;
}

fn encodeLuaTableAsJson(L: ?*lua.LuaState) c_int {
    return encodeJsonInner(L) catch |err| {
        std.log.err("internal (not lua) error encoding json: {any}", .{err});
        lua.show_lua_error(L, "could not encode json", .{});
        return 0;
    };
}

fn defaultLuaHashFn(L: ?*lua.LuaState) c_int {
    if (!lua.lua_isstring(L, -1)) {
        const typ = lua.lua_type(L, -1);
        const typename = lua.lua_typename(L, @intFromEnum(typ));
        lua.show_lua_error(L, "expected first argument to hash() to be a string, received %s", .{typename});
        return 0;
    }

    const arg1 = lua.cStrAsSlice(lua.lua_tostring(L, -1));

    // TODO: expose salt from lua side
    const result = std.crypto.pwhash.bcrypt.bcrypt(arg1, "1234abcdzxcv6789".*, .{ .rounds_log = 12 });
    lua.lua_pop(L, 1); // pop arg

    lua.lua_pushlstring(L, &result, result.len);
    return 1;
}

const module: [4]lua.LuaReg = .{
    lua.LuaReg{ .name = "json", .func = encodeLuaTableAsJson },
    lua.LuaReg{ .name = "hash", .func = defaultLuaHashFn },
    lua.LuaReg{ .name = "sqlite3_query", .func = sql.luaQueryDefaultDb },
    lua.LuaReg{ .name = null, .func = null },
};

pub fn initTable(L: ?*lua.LuaState) void {
    sql.initTables();

    lua.lua_newtable(L);
    lua.luaL_setfuncs(L, &module, 0);
    lua.lua_setglobal(L, "utils");
}
