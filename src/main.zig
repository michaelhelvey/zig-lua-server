const std = @import("std");
const lua = @import("lua.zig");

const ReceiveHeadError = std.http.Server.ReceiveHeadError;
const ResponseOptions = std.http.Server.Request.RespondOptions;

var L: ?*lua.LuaState = null;
var server: std.net.Server = undefined;

const LuaResponse = struct {
    status: std.http.Status,
    body: []const u8,
};

fn cStrToOwned(cstr: [*c]const u8, allocator: std.mem.Allocator) ![]const u8 {
    const bodyLen = std.mem.len(cstr);
    const luaBody: []const u8 = @ptrCast(cstr[0..bodyLen]);
    const ownedBody = try allocator.alloc(u8, bodyLen);
    @memcpy(ownedBody, luaBody);
    return @ptrCast(ownedBody);
}

fn invokeLuaWithRequest(request: std.http.Server.Request, body: []u8, allocator: std.mem.Allocator) !LuaResponse {
    // default = error until we overwrite them
    var response: LuaResponse = .{
        .body = @constCast("Internal server errror"),
        .status = std.http.Status.internal_server_error,
    };
    try lua.luaL_dofile(L, "./lua/index.lua");
    lua.lua_pop(L, lua.lua_gettop(L));

    // push the function to be called onto the stack
    _ = lua.lua_getglobal(L, "handle_request");

    // construct a request table
    lua.lua_newtable(L);
    lua.lua_pushstring(L, "method");
    lua.lua_pushstring(L, @tagName(request.head.method));
    lua.lua_settable(L, -3);

    lua.lua_pushstring(L, "path");
    lua.lua_pushlstring(L, request.head.target.ptr, request.head.target.len);
    lua.lua_settable(L, -3);

    lua.lua_pushstring(L, "body");
    lua.lua_pushlstring(L, body.ptr, body.len);
    lua.lua_settable(L, -3);

    try lua.lua_pcall(L, 1, 1, 0);
    if (lua.lua_istable(L, -1)) {
        // TODO: yell at the user somehow if they return the wrong type through lua_error

        // get the status code from the request
        _ = lua.lua_getfield(L, -1, "status");
        const statusCode = lua.lua_tointeger(L, -1);
        response.status = @enumFromInt(statusCode);
        lua.lua_pop(L, 1);

        // TODO: allow specifying headers (at least content type)

        _ = lua.lua_getfield(L, -1, "body");
        const responseBody = lua.lua_tostring(L, -1);
        response.body = try cStrToOwned(responseBody, allocator);

        lua.lua_pop(L, 1);

        std.log.info("lua handler: status = {d}, body = {s}\n", .{ response.status, response.body });
    }

    lua.lua_pop(L, lua.lua_gettop(L));
    return response;
}

fn connHandler(conn: std.net.Server.Connection) !void {
    var read_buffer: [1024]u8 = undefined;
    var httpServer = std.http.Server.init(conn, &read_buffer);

    while (true) {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();

        const allocator = arena.allocator();
        var request = httpServer.receiveHead() catch |err| switch (err) {
            ReceiveHeadError.HttpConnectionClosing => return,
            else => {
                std.log.err("error receiving head: {s}", .{@errorName(err)});
                return;
            },
        };

        const bodyReader = try request.reader();
        const body = try bodyReader.readAllAlloc(allocator, 4096);
        std.log.info("{s} {s}; body = {s}", .{ @tagName(request.head.method), request.head.target, body });

        const response = try invokeLuaWithRequest(request, body, allocator);
        try request.respond(response.body, .{
            .status = response.status,
        });

        if (!request.head.keep_alive) {
            conn.stream.close();
            return;
        }
    }
}

pub fn main() !void {
    // const addr = try std.net.Address.resolveIp("127.0.0.1", 8000);
    // server = try addr.listen(.{ .reuse_address = true });
    // std.log.info("server listening on http://localhost:8000", .{});

    L = lua.luaL_newstate();
    lua.luaL_openlibs(L);

    const code =
        \\ function foo()
        \\     return "blah"
        \\ end
    ;

    try lua.luaL_loadbuffer(L, code, code.len, "lua chungus");
    try lua.lua_pcall(L, 0, lua.MULTRET, 0);
    _ = lua.lua_getglobal(L, "foo");
    try lua.lua_pcall(L, 0, 1, 0);

    if (!lua.lua_isnumber(L, -1)) {
        const typ = lua.lua_type(L, -1);
        std.debug.print("typ = {any}\n", .{typ});
        const typename = lua.lua_typename(L, @intFromEnum(typ));
        _ = lua.luaL_error(L, "expected foo to return a number, but got %s", typename);
        return error.MyCodeSucks;
    }

    // while (true) {
    //     const conn = try server.accept();
    //     _ = try std.Thread.spawn(.{}, connHandler, .{conn});
    // }
}
