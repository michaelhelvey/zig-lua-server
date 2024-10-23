const c = @cImport({
    @cInclude("sqlite3.h");
    @cInclude("sqlite3ext.h");
});
const std = @import("std");
const lua = @import("lua.zig");

var db: *c.sqlite3 = undefined;

fn sqlite3Callback(ctx: ?*anyopaque, argc: c_int, argv: [*c][*c]u8, azColName: [*c][*c]u8) callconv(.C) c_int {
    const L: ?*lua.LuaState = @ptrCast(ctx);

    // pop off "n" from the previous callback
    const n = lua.lua_tointeger(L, -1);
    lua.lua_pop(L, 1);

    // push the row's table onto the stack
    lua.lua_pushinteger(L, n); // parent table key
    lua.lua_newtable(L); // parent table value

    var i: usize = 0;
    while (i < argc) : (i += 1) {
        const colName = azColName[i];
        var colValue = argv[i];
        if (colValue == null) {
            colValue = @constCast("NULL");
        }

        // set the key-value pair in the sub-table
        lua.lua_pushstring(L, colName);
        lua.lua_pushstring(L, colValue);
        lua.lua_settable(L, -3);
    }

    lua.lua_settable(L, -3); // set the sub-table in the parent table

    // update n for the next iteration of the callback
    lua.lua_pushinteger(L, n + 1);

    return 0;
}

pub fn initTables() void {
    // note: not closing database, hopefully that's ok lol...I don't have a good "graceful shutdown"
    // sequence yet
    if (c.sqlite3_open("./test.db", @ptrCast(&db)) != c.SQLITE_OK) {
        std.debug.print("Failed to open database\n", .{});
        return;
    }

    const createTable = "create table if not exists users (id integer primary key, name text, username text, password text);";
    if (c.sqlite3_exec(db, createTable, null, null, null) != c.SQLITE_OK) {
        std.debug.print("Failed to create table\n", .{});
        return;
    }
}

pub fn luaQueryDefaultDb(L: ?*lua.LuaState) c_int {
    if (!lua.lua_isstring(L, -1)) {
        const typ = lua.lua_type(L, -1);
        const typename = lua.lua_typename(L, @intFromEnum(typ));
        lua.show_lua_error(L, "expected query() arg to be a string, received %s", .{typename});
        return 0;
    }

    var errMsg: [*c]u8 = null;

    const arg1 = lua.lua_tostring(L, -1);
    lua.lua_newtable(L);
    lua.lua_pushinteger(L, 1); // row index start = 1

    std.log.info("executing sql query: {s}", .{arg1});
    const status = c.sqlite3_exec(db, arg1, sqlite3Callback, L, &errMsg);
    if (status != c.SQLITE_OK) {
        const msg = c.sqlite3_errmsg(db);
        lua.show_lua_error(L, "sqlite3 error: %s: %s", .{ errMsg, msg });
        return 0;
    }

    lua.lua_pop(L, 1); // pop last 'n' from the stack
    return 1;
}
