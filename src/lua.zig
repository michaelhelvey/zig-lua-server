// The lua.h file is very macro heavy, and as a result, zig's C translation doesn't work on it,
// or produces garbage code with opaque types everywhere that are basically unusable.  I'm choosing
// to write out declarations for everything instead by hand.
// Reference: https://www.lua.org/manual/5.3/contents.html#index
// /opt/homebrew/include/lua/lua.h
// /opt/homebrew/include/lua/lauxlib.h
const std = @import("std");
const c = @cImport({
    @cInclude("strings.h");
});
const expect = std.testing.expect;

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

pub const Status = enum(c_int) {
    OK = 0,
    YIELD = 1,
    ERRUN = 2,
    ERRSYNTAX = 3,
    ERRMEM = 4,
    ERRERR = 5,
};

pub const Type = enum(c_int) {
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
    // "pseudo-types" that don't really exist on the lua stack, but I find convenient for casting
    INTEGER = 90,
    FLOAT = 91,
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
pub extern fn lua_seti(L: ?*LuaState, idx: c_int, n: LuaInteger) void;
pub extern fn lua_rawseti(L: ?*LuaState, idx: c_int, n: LuaInteger) void;
pub extern fn luaL_checkversion_(L: ?*LuaState, ver: LuaNumber, sz: usize) void;
pub extern fn lua_next(L: ?*LuaState, idx: c_int) c_int;
pub extern fn lua_setglobal(L: ?*LuaState, name: [*c]const u8) void;

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

pub inline fn lua_register(L: ?*LuaState, n: [*c]const u8, f: CFunction) void {
    lua_pushcfunction(L, f);
    lua_setglobal(L, n);
}

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

//--------------------------------------------------------------------------------------------------
// Public "zig-friendly" API
//
// Note that I have 0 intention of fully replicating the entire lua library (either here or in the
// above bindings), I just tack things on when I use them and make up APIs as I go along :D
//--------------------------------------------------------------------------------------------------

pub const Lua = struct {
    state: ?*LuaState,

    const Self = @This();

    pub fn init() Self {
        const L = luaL_newstate();
        luaL_openlibs(L);

        return Self{ .state = L };
    }

    pub fn execBuffer(self: *Lua, buffer: []const u8, name: [*c]const u8) !void {
        if (luaL_loadbufferx(self.state, @ptrCast(buffer.ptr), buffer.len, name, null) != Status.OK) {
            const err = lua_tostring(self.state, -1);
            std.log.err("loadBuffer error: {s}", .{err});
            lua_pop(self.state, 1);
            return error.Loadbuffer;
        }

        try lua_pcall(self.state, 0, MULTRET, 0);
        self.clearStack();
    }

    pub fn clearStack(self: *Lua) void {
        lua_pop(self.state, lua_gettop(self.state));
    }

    pub fn execFile(self: *Lua, file: [:0]const u8) !void {
        try luaL_dofile(self.state, file);
    }

    pub fn openTable(self: *Lua) void {
        lua_newtable(self.state);
    }

    pub fn pushTablePair(self: *Lua, key: anytype, value: anytype) !void {
        const T = @TypeOf(key);
        switch (@typeInfo(T)) {
            .Int, .ComptimeInt => {
                lua_pushinteger(self.state, key);
            },
            .Pointer => try self.pushPointer(key),
            else => {
                std.log.err("invalid lua key type: {s}", .{@typeName(T)});
                return error.InvalidLuaKey;
            },
        }

        try self.pushValue(value);
        lua_settable(self.state, -3);
    }

    pub fn pushTable(self: *Lua) void {
        lua_settable(self.state, -3);
    }

    pub fn pushValue(self: *Lua, value: anytype) !void {
        // Uses zig comptime to determine what lua function to call to push the zig value.  Pattern
        // taken from https://github.com/ziglang/zig/blob/56996a2809421a7dfbb74f7533d40faf6c1482e3/lib/std/json/stringify.zig#L493
        const T = @TypeOf(value);
        switch (@typeInfo(T)) {
            .Int, .ComptimeInt => {
                lua_pushinteger(self.state, value);
            },
            .Float, .ComptimeFloat => {
                lua_pushnumber(self.state, value);
            },
            .Pointer => try self.pushPointer(value),
            else => {
                std.log.err("TODO(pushValue): handle zig type {s}", .{@typeName(T)});
                return error.UnhandledZigValue;
            },
        }
    }

    fn pushPointer(self: *Lua, value: anytype) !void {
        const T = @TypeOf(value);
        switch (@typeInfo(T)) {
            .Pointer => |ptr_info| switch (ptr_info.size) {
                .One => switch (@typeInfo(ptr_info.child)) {
                    .Array => {
                        // Coerce `*[N]T` to `[]const T`.
                        const Slice = []const std.meta.Elem(ptr_info.child);
                        return self.pushValue(@as(Slice, value));
                    },
                    else => return self.pushValue(value.*),
                },
                .Many, .Slice => {
                    if (ptr_info.child == u8) {
                        // This is a []const u8, or some similar Zig string.
                        lua_pushlstring(self.state, value.ptr, value.len);
                    } else {
                        std.log.err("TODO(pushValue): handle zig type Pointer of {s}", .{@typeName(ptr_info.child)});
                        return error.UnhandledZigValue;
                    }
                },
                else => {
                    std.log.err("TODO(pushValue): handle zig type Pointer of {s}", .{@typeName(ptr_info.child)});
                    return error.UnhandledZigValue;
                },
            },
            else => {
                std.log.err("pushPointer called with non-pointer type {s}", .{@typeName(T)});
                return error.InvalidPointerType;
            },
        }
    }

    pub fn pushGlobal(self: *Lua, name: []const u8) void {
        _ = lua_getglobal(self.state, @ptrCast(name));
    }

    pub fn callFunction(self: *Lua, nargs: c_int, nreturn: c_int) !void {
        return lua_pcall(self.state, nargs, nreturn, 0);
    }

    pub fn expectType(self: *Lua, expected: Type) !void {
        return self.expectTypeAtIndex(expected, -1);
    }

    pub fn expectTypeAtIndex(self: *Lua, expected: Type, idx: c_int) !void {
        // translate from my silly pseudo-types to real lua types
        const realExpected = switch (expected) {
            .INTEGER => Type.NUMBER,
            .FLOAT => Type.NUMBER,
            else => expected,
        };
        const actual = lua_type(self.state, idx);
        const actualStr = lua_typename(self.state, @intFromEnum(actual));
        const expectedStr = lua_typename(self.state, @intFromEnum(realExpected));
        if (actual != realExpected) {
            std.log.err("expectTypeAtIndex({d}): expected {s}, received {s}", .{ idx, expectedStr, actualStr });
            self.throw_lua_error("expectTypeAtIndex(%d): expected %s, received %s", .{ idx, expectedStr, actualStr });
            return error.UnexpectedType;
        }
    }

    pub fn getField(self: *Lua, field: [:0]const u8) void {
        _ = lua_getfield(self.state, -1, field);
    }

    pub fn pushNil(self: *Lua) void {
        lua_pushnil(self.state);
    }

    pub fn pop(self: *Lua, n: c_int) void {
        lua_pop(self.state, n);
    }

    pub fn next(self: *Lua, n: c_int) bool {
        return lua_next(self.state, n) != 0;
    }

    fn castToType(comptime t: Type) type {
        return switch (t) {
            .BOOLEAN => bool,
            .STRING => []const u8,
            .INTEGER => LuaInteger,
            .FLOAT => LuaNumber,
            else => @compileError("unable to cast lua value of type " ++ @tagName(t)),
        };
    }

    pub fn readIndex(self: *Lua, comptime t: Type, idx: c_int) !castToType(t) {
        try self.expectTypeAtIndex(t, idx);
        return switch (t) {
            .BOOLEAN => lua_toboolean(self.state, idx),
            .STRING => std.mem.span(lua_tostring(self.state, idx)),
            .INTEGER => lua_tointeger(self.state, idx),
            .FLOAT => lua_tonumber(self.state, idx),
            else => unreachable,
        };
    }

    pub fn readTop(self: *Lua, comptime t: Type) !castToType(t) {
        return self.readIndex(t, -1);
    }

    pub fn debugStack(self: *Lua) void {
        const top = lua_gettop(self.state);

        std.debug.print("-- LUA STACK (top = {d}) --\n", .{top});
        var i: c_int = 0;
        while (i <= top) : (i += 1) {
            const typ = lua_type(self.state, i);
            std.debug.print("\t{d}: {s} (", .{ i, @tagName(typ) });
            switch (typ) {
                Type.NONE => {
                    std.debug.print("none", .{});
                },
                Type.NIL => {
                    std.debug.print("nil", .{});
                },
                Type.BOOLEAN => {
                    const value = lua_toboolean(self.state, i);
                    std.debug.print("{?}", .{value});
                },
                Type.LIGHTUSERDATA => {
                    const value = lua_touserdata(self.state, i);
                    std.debug.print("{*}", .{value});
                },
                Type.NUMBER => {
                    const value = lua_tonumber(self.state, i);
                    std.debug.print("{?}", .{value});
                },
                Type.STRING => {
                    const value = lua_tostring(self.state, i);
                    std.debug.print("{s}", .{value});
                },
                Type.USERDATA => {
                    const value = lua_topointer(self.state, i);
                    std.debug.print("{*}", .{value});
                },
                else => {
                    // TODO: look into how to print tables & functions and stuff
                    std.debug.print("unprintable type", .{});
                },
            }

            std.debug.print(")\n", .{});
        }
    }

    pub fn getTopTypename(self: *Self) []const u8 {
        const typ = lua_type(self.state, -1);
        const typename = lua_typename(self.state, @intFromEnum(typ));

        return std.mem.span(typename);
    }

    pub fn throw_lua_error(self: *Self, fmt: [*c]const u8, args: anytype) void {
        _ = @call(std.builtin.CallModifier.auto, luaL_error, .{ self.state, fmt } ++ args);
    }
};

test "using the struct based API" {
    var state = Lua.init();

    // note: we have to write to stderr because writing to stdout in tests makes the zig test runner
    // hang forever...see https://github.com/ziglang/zig/issues/15091
    const code =
        \\ function eprintln(...)
        \\   for _, v in ipairs({...}) do
        \\     io.output(io.stderr):write(tostring(v))
        \\   end
        \\
        \\   io.output(io.stderr):write('\n')
        \\ end
        \\
        \\ function foo(integer, float, str, table, list)
        \\   eprintln("int arg: ", integer)
        \\   eprintln("float arg: ", float)
        \\   eprintln("string arg: ", str)
        \\
        \\   for k, v in pairs(table) do
        \\     eprintln("[table]: key = " .. k .. " val = " .. v)
        \\   end
        \\
        \\   for k, v in ipairs(list) do
        \\     eprintln("[list]: key = " .. k .. " val = " .. v)
        \\   end
        \\
        \\  return {
        \\      status = 69,
        \\      headers = { some_key = "the value" }
        \\  }
        \\ end
    ;

    try state.execBuffer(code, "chunk");

    // get the function
    state.pushGlobal("foo");

    // push the function arguments
    try state.pushValue(2);
    try state.pushValue(2.2);
    try state.pushValue("string");

    state.openTable();
    try state.pushTablePair("key", "value");
    try state.pushTablePair("number", 123);

    state.openTable();
    try state.pushTablePair(1, "first");
    try state.pushTablePair(2, 69);

    // call the function
    try state.callFunction(5, 1);

    // return type parsing
    try state.expectType(Type.TABLE);
    state.getField("status");
    const status = try state.readTop(Type.INTEGER);
    try expect(status == 69);
    // pop status:
    state.pop(1);

    state.getField("headers");
    try state.expectType(Type.TABLE);

    state.pushNil();
    while (state.next(-2)) {
        const key = try state.readIndex(Type.STRING, -2);
        const value = try state.readIndex(Type.STRING, -1);
        try std.testing.expectEqualStrings(key, "some_key");
        try std.testing.expectEqualStrings(value, "the value");
        state.pop(1);
    }

    // pop table
    state.pop(1);
    // we're totally done, so clear the stack
    state.clearStack();
}
