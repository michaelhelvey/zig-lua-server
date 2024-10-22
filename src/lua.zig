// The lua.h file is very macro heavy, and as a result, zig's C translation doesn't work on it,
// or produces garbage code with opaque types everywhere that are basically unusable.  I'm choosing
// to write out declarations for everything instead by hand.
// Reference: https://www.lua.org/manual/5.3/contents.html#index
// /opt/homebrew/include/lua/lua.h
// /opt/homebrew/include/lua/lauxlib.h
const std = @import("std");

pub const LuaState = opaque {};
const KContext = usize;
pub const KFunction = ?*const fn (?*LuaState, c_int, KContext) callconv(.C) c_int;
pub const CFunction = ?*const fn (?*LuaState) c_int;

pub const LuaReg = extern struct {
    name: [*c]const u8,
    func: CFunction,
};

const LUAI_MAXSTACK = 1000000;
const LUA_REGISTRYINDEX = (-LUAI_MAXSTACK - 1000);
const LUA_RIDX_GLOBALS = 2;

const LuaNumber = f64;
const LuaInteger = u64;

// FIXME: this is probably stupid because obviously I don't know what version of lua you are actually
// linking against
const LUA_VERSION_NUM = 504;
const LUAL_NUMSIZES = 16 * @sizeOf(LuaInteger) + @sizeOf(LuaNumber);

const Status = enum(c_int) {
    OK = 0,
    YIELD = 1,
    ERRUN = 2,
    ERRSYNTAX = 3,
    ERRMEM = 4,
    ERRERR = 5,
};

const Type = enum(c_int) {
    NONE = -1,
    NIL = 0,
    BOOLEAN = 1,
    LIGHTUSERDATA = 2,
    NUMBER = 3,
    STRING = 4,
    TABLE = 5,
    FUNCTION = 6,
    USERDATA = 7,
    THREAD = 8,
    NUMTYPES = 9,
};

pub const MULTRET = -1;

//--------------------------------------------------------------------------------------------------
// C bindings
//--------------------------------------------------------------------------------------------------

pub extern fn luaL_newstate() ?*LuaState;
pub extern fn luaL_openlibs(L: ?*LuaState) void;
pub extern fn luaL_loadbufferx(L: ?*LuaState, buf: [*c]const u8, size: usize, name: [*c]const u8, mode: [*c]const u8) Status;
pub extern fn luaL_loadfilex(L: ?*LuaState, file: [*c]const u8, mode: [*c]const u8) Status;
pub extern fn luaL_loadstring(L: ?*LuaState, str: [*c]const u8) Status;
pub extern fn lua_pcallk(
    L: ?*LuaState,
    nargs: c_int,
    nresult: c_int,
    errfunc: c_int,
    kContext: KContext,
    KFunction: KFunction,
) Status;
pub extern fn lua_settop(L: ?*LuaState, idx: c_int) void;
pub extern fn lua_gettop(L: ?*LuaState) c_int;
pub extern fn lua_type(L: ?*LuaState, idx: c_int) Type;
pub extern fn lua_typename(L: ?*LuaState, type: c_int) [*c]const u8;
pub extern fn lua_error(L: ?*LuaState) c_int;
pub extern fn luaL_error(L: ?*LuaState, fmt: [*c]const u8, ...) c_int;
pub extern fn luaL_setfuncs(L: ?*LuaState, l: [*c]const LuaReg, nup: c_int) void;
pub extern fn luaL_checkversion_(L: ?*LuaState, ver: LuaNumber, sz: usize) void;

pub extern fn lua_pushboolean(L: ?*LuaState, value: bool) void;
pub extern fn lua_pushcclosure(L: ?*LuaState, func: CFunction, n: c_int) void;
pub extern fn lua_pushnil(L: ?*LuaState) void;
pub extern fn lua_pushnumber(L: ?*LuaState, n: c_longdouble) void;
pub extern fn lua_pushlstring(L: ?*LuaState, s: [*c]const u8, len: usize) void;
pub extern fn lua_pushstring(L: ?*LuaState, s: [*c]const u8) void;
pub extern fn lua_pushfstring(L: ?*LuaState, fmt: [*c]const u8, ...) [*c]const u8;
pub extern fn lua_pushinteger(L: ?*LuaState, value: LuaInteger) void;
pub extern fn lua_pushlightuserdata(L: ?*LuaState, p: ?*anyopaque) void;
pub extern fn lua_pushthread(L: ?*LuaState) c_int; // returns 1 if thread is main thread
pub extern fn lua_pushvalue(L: ?*LuaState, idx: c_int) void;
pub extern fn lua_createtable(L: ?*LuaState, narr: c_int, nrec: c_int) void;
pub extern fn lua_settable(L: ?*LuaState, idx: c_int) void;

pub extern fn lua_tonumberx(L: ?*LuaState, idx: c_int, isnum: [*c]c_int) LuaNumber;
pub extern fn lua_tointegerx(L: ?*LuaState, idx: c_int, isnum: [*c]c_int) LuaInteger;
pub extern fn lua_toboolean(L: ?*LuaState, idx: c_int) bool;
pub extern fn lua_tocfunction(L: ?*LuaState, idx: c_int) CFunction;
pub extern fn lua_tolstring(L: ?*LuaState, idx: c_int, len: usize) [*c]const u8;
pub extern fn lua_touserdata(L: ?*LuaState, idx: c_int) ?*anyopaque;
pub extern fn lua_tothread(L: ?*LuaState, idx: c_int) ?*LuaState;
pub extern fn lua_topointer(L: ?*LuaState, idx: c_int) ?*anyopaque;

pub extern fn lua_getglobal(L: ?*LuaState, name: [*c]const u8) Type;
pub extern fn lua_gettable(L: ?*LuaState, name: [*c]const u8) Status;
pub extern fn lua_getfield(L: ?*LuaState, idx: c_int, field: [*c]const u8) Type;
pub extern fn lua_rawgeti(L: ?*LuaState, idx: c_int, n: c_int) Type;

//--------------------------------------------------------------------------------------------------
// C macro translations, in no particular order at all
//--------------------------------------------------------------------------------------------------

pub inline fn lua_pushglobaltable(L: ?*LuaState) void {
    _ = lua_rawgeti(L, LUA_REGISTRYINDEX, LUA_RIDX_GLOBALS);
}

pub inline fn lua_pushcfunction(L: ?*LuaState, func: CFunction) void {
    lua_pushcclosure(L, func, 0);
}

pub inline fn luaL_loadbuffer(L: ?*LuaState, buf: [*c]const u8, size: usize, name: [*c]const u8) !void {
    if (luaL_loadbufferx(L, buf, size, name, null) != Status.OK) {
        const err = lua_tostring(L, -1);
        std.log.err("pcall error: {s}", .{err});
        lua_pop(L, 1);
        return error.Loadbuffer;
    }
}

pub inline fn luaL_checkversion(L: ?*LuaState) void {
    luaL_checkversion_(L, LUA_VERSION_NUM, LUAL_NUMSIZES);
}

pub inline fn luaL_newlibtable(L: ?*LuaState, l: []LuaReg) void {
    lua_createtable(L, 0, l.len);
}

pub inline fn luaL_newlib(L: ?*LuaState, l: []LuaReg) void {
    luaL_checkversion(L);
    luaL_newlibtable(L, l);
    luaL_setfuncs(L, l.ptr, 0);
}

pub inline fn lua_pcall(L: ?*LuaState, nargs: c_int, nresult: c_int, errfunc: c_int) !void {
    if (lua_pcallk(L, nargs, nresult, errfunc, 0, null) != Status.OK) {
        const err = lua_tostring(L, -1);
        std.log.err("pcall error: {s}", .{err});
        lua_pop(L, 1);
        return error.Pcall;
    }
}

pub inline fn luaL_dofile(L: ?*LuaState, file: [*c]const u8) !void {
    if (luaL_loadfilex(L, file, null) != Status.OK) {
        return error.LoadFile;
    }

    try lua_pcall(L, 0, MULTRET, 0);
}

pub inline fn luaL_dostring(L: ?*LuaState, s: [*c]const u8) !void {
    if (luaL_loadstring(L, s) != Status.OK) {
        return error.LoadString;
    }

    try lua_pcall(L, 0, MULTRET, 0);
}

pub inline fn lua_pop(L: ?*LuaState, n: c_int) void {
    lua_settop(L, -(n) - 1);
}

pub inline fn lua_isfunction(L: ?*LuaState, idx: c_int) bool {
    return lua_type(L, idx) == Type.FUNCTION;
}

pub inline fn lua_isinteger(L: ?*LuaState, idx: c_int) bool {
    return lua_type(L, idx) == Type.NUMBER;
}

pub inline fn lua_istable(L: ?*LuaState, idx: c_int) bool {
    return lua_type(L, idx) == Type.TABLE;
}

pub inline fn lua_isboolean(L: ?*LuaState, idx: c_int) bool {
    return lua_type(L, idx) == Type.BOOLEAN;
}

pub inline fn lua_isnil(L: ?*LuaState, idx: c_int) bool {
    return lua_type(L, idx) == Type.NIL;
}

pub inline fn lua_isnone(L: ?*LuaState, idx: c_int) bool {
    return lua_type(L, idx) == Type.NONE;
}

pub inline fn lua_isstring(L: ?*LuaState, idx: c_int) bool {
    return lua_type(L, idx) == Type.STRING;
}

pub inline fn lua_isuserdata(L: ?*LuaState, idx: c_int) bool {
    return lua_type(L, idx) == Type.USERDATA;
}

pub inline fn lua_islightuserdata(L: ?*LuaState, idx: c_int) bool {
    return lua_type(L, idx) == Type.LIGHTUSERDATA;
}

pub inline fn lua_isnumber(L: ?*LuaState, idx: c_int) bool {
    return lua_type(L, idx) == Type.NUMBER;
}

pub inline fn lua_isnoneornil(L: ?*LuaState, idx: c_int) bool {
    return lua_type(L, idx) <= Type.NONE;
}

pub inline fn lua_tointeger(L: ?*LuaState, idx: c_int) LuaInteger {
    return @intCast(lua_tointegerx(L, idx, null));
}

pub inline fn lua_tonumber(L: ?*LuaState, idx: c_int) LuaNumber {
    return lua_tonumberx(L, idx, null);
}

pub inline fn lua_tostring(L: ?*LuaState, idx: c_int) [*c]const u8 {
    return lua_tolstring(L, idx, 0);
}

pub inline fn lua_newtable(L: ?*LuaState) void {
    return lua_createtable(L, 0, 0);
}

pub fn lua_debug_stack(L: ?*LuaState) void {
    const top = lua_gettop(L);

    std.debug.print("-- LUA STACK (top = {d}) --\n", .{top});
    var i: c_int = 0;
    while (i <= top) : (i += 1) {
        const typ = lua_type(L, i);
        std.debug.print("\t{d}: {s} (", .{ i, @tagName(typ) });
        switch (typ) {
            Type.NONE => {
                std.debug.print("none", .{});
            },
            Type.NIL => {
                std.debug.print("nil", .{});
            },
            Type.BOOLEAN => {
                const value = lua_toboolean(L, i);
                std.debug.print("{d}", .{value});
            },
            Type.LIGHTUSERDATA => {
                const value = lua_touserdata(L, i);
                std.debug.print("{p}", .{value});
            },
            Type.NUMBER => {
                const value = lua_tonumber(L, i);
                std.debug.print("{f}", .{value});
            },
            Type.STRING => {
                const value = lua_tostring(L, i);
                std.debug.print("{s}", .{value});
            },
            else => {
                // TODO: look into how to print tables & functions and stuff
                std.debug.print("unprintable type {any}", .{typ});
            },
        }

        std.debug.print(")\n", .{});
    }
}
