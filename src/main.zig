const std = @import("std");
const lua = @import("lua.zig");
const utilsLib = @import("utils.zig");

const ReceiveHeadError = std.http.Server.ReceiveHeadError;
const ResponseOptions = std.http.Server.Request.RespondOptions;

var L: ?*lua.LuaState = null;
var server: std.net.Server = undefined;

const MAX_REQUEST_SIZE = 1048576;

const LuaResponse = struct {
    status: std.http.Status = std.http.Status.internal_server_error,
    // TODO: allow multiple values?
    headers: std.ArrayListUnmanaged(std.http.Header) = .{},
    body: []const u8 = "Internal server error",
};

const QueryParam = struct {
    key: []const u8,
    value: []const u8,
};

// I'm sure the std lib has this code but I can't find it and I'm tired
const BufReader = struct {
    buf: []const u8,
    cursor: usize,

    const Error = error{NoError};
    const Self = @This();
    const Reader = std.io.Reader(*Self, Error, read);

    fn init(buf: []const u8) Self {
        return .{
            .buf = buf,
            .cursor = 0,
        };
    }

    fn read(self: *Self, dest: []u8) Error!usize {
        var i: usize = 0;
        while (i < dest.len) : (i += 1) {
            if (self.cursor > self.buf.len - 1) {
                return 0;
            }
            dest[i] = self.buf[self.cursor];
            self.cursor += 1;
        }

        return i;
    }

    fn reader(self: *Self) Reader {
        return .{ .context = self };
    }
};

const Url = struct {
    path: []const u8,
    query_params: []QueryParam,

    fn parse(alloc: std.mem.Allocator, raw: []const u8) !Url {
        _ = alloc;
        _ = raw;
        // TODO: add testing target and actually write a query parameter parser
        return .{
            .path = "/api/signup.lua",
            .query_params = &.{},
        };
    }
};

fn invokeLua(alloc: std.mem.Allocator, request: *std.http.Server.Request, bodyReader: std.io.AnyReader, luaSrc: []const u8, url: Url) !LuaResponse {
    var response: LuaResponse = .{};
    try lua.luaL_dofile(L, @ptrCast(luaSrc));
    lua.lua_pop(L, lua.lua_gettop(L));

    // push the function to be called onto the stack
    _ = lua.lua_getglobal(L, "handle_request");

    // construct a request table
    lua.lua_newtable(L);
    lua.lua_pushstring(L, "method");
    lua.lua_pushstring(L, @tagName(request.head.method));
    lua.lua_settable(L, -3);

    // table for url
    lua.lua_pushstring(L, "url");

    lua.lua_newtable(L);
    lua.lua_pushstring(L, "path");
    lua.lua_pushlstring(L, url.path.ptr, url.path.len);
    lua.lua_settable(L, -3);

    lua.lua_pushstring(L, "params");
    lua.lua_newtable(L); // table for params
    for (url.query_params) |param| {
        lua.lua_pushlstring(L, param.key.ptr, param.key.len);
        lua.lua_pushlstring(L, param.value.ptr, param.value.len);
        lua.lua_settable(L, -3);
    }
    // push params onto url
    lua.lua_settable(L, -3);

    // push url onto parent
    lua.lua_settable(L, -3);

    lua.lua_pushstring(L, "headers");
    lua.lua_newtable(L); // table at -1

    var it = request.iterateHeaders();
    while (it.next()) |header| {
        lua.lua_pushlstring(L, header.name.ptr, header.name.len); // table at -2
        lua.lua_pushlstring(L, header.value.ptr, header.value.len); // table at -3
        lua.lua_settable(L, -3);
    }

    // once we get to the bottom the headers table will be at the the top of the stack, so we
    // settable again to set it on the parent
    lua.lua_settable(L, -3);

    const body = try bodyReader.readAllAlloc(alloc, MAX_REQUEST_SIZE);
    lua.lua_pushstring(L, "body");
    lua.lua_pushlstring(L, body.ptr, body.len);
    lua.lua_settable(L, -3);

    try lua.lua_pcall(L, 1, 1, 0);
    if (!lua.lua_istable(L, -1)) {
        const typename = lua.get_top_typename(L);
        const err = try std.fmt.allocPrint(alloc, "expected handle_request to return response table, received {s}", .{typename});
        std.log.err("error in handler: {s}", .{err});
        response.body = err;
        return response;
    }

    // status code:
    _ = lua.lua_getfield(L, -1, "status");
    if (!lua.lua_isinteger(L, -1)) {
        const typename = lua.get_top_typename(L);
        const err = try std.fmt.allocPrint(alloc, "expected response.status to be an integer, received {s}", .{typename});
        std.log.err("error in handler: {s}", .{err});
        response.body = err;
        return response;
    }
    const statusCode = lua.lua_tointeger(L, -1);
    response.status = @enumFromInt(statusCode);
    lua.lua_pop(L, 1);

    // headers:
    _ = lua.lua_getfield(L, -1, "headers");
    if (!lua.lua_istable(L, -1)) {
        const typename = lua.get_top_typename(L);
        const err = try std.fmt.allocPrint(alloc, "expected response.headers to be a table, received {s}", .{typename});
        std.log.err("error in handler: {s}", .{err});
        response.body = err;
        return response;
    }

    // headers table is now at the top of the stack (-1)
    lua.lua_pushnil(L); // give lua_next something to pop
    while (lua.lua_next(L, -2) != 0) {
        const key = try lua.cStrToOwnedSlice(lua.lua_tostring(L, -2), alloc);
        const value = try lua.cStrToOwnedSlice(lua.lua_tostring(L, -1), alloc);
        const header = std.http.Header{
            .name = key,
            .value = value,
        };
        try response.headers.append(alloc, header);

        // pop value, leaving key for next lua_next() call
        lua.lua_pop(L, 1);
    }

    // pop headers table
    lua.lua_pop(L, 1);

    _ = lua.lua_getfield(L, -1, "body");
    if (!lua.lua_isstring(L, -1)) {
        const typename = lua.get_top_typename(L);
        const err = try std.fmt.allocPrint(alloc, "expected response.body to be a string, received {s}", .{typename});
        std.log.err("error in handler: {s}", .{err});
        response.body = err;
        return response;
    }
    const responseBody = lua.lua_tostring(L, -1);
    response.body = try lua.cStrToOwnedSlice(responseBody, alloc);

    // pop body
    lua.lua_pop(L, 1);

    std.log.info("lua handler: status = {d}, body = {s}", .{ response.status, response.body });
    lua.lua_pop(L, lua.lua_gettop(L));

    return response;
}

fn contentTypeForExtension(extension: []const u8) []const u8 {
    if (std.mem.eql(u8, extension, ".html")) {
        return "text/html";
    } else if (std.mem.eql(u8, extension, ".css")) {
        return "text/css";
    } else if (std.mem.eql(u8, extension, ".js")) {
        return "text/javascript";
    } else {
        return "text/plain";
    }
}

fn handleConn(conn: std.net.Server.Connection, absoluteRootPath: []const u8) !void {
    var read_buffer: [1024]u8 = undefined;
    var httpServer = std.http.Server.init(conn, &read_buffer);
    const cwd = std.fs.cwd();

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

        const url = try Url.parse(allocator, request.head.target);

        // If it does not exist or we cannot access it, return 404 before trying to read it
        const resolvedPath = try std.fs.path.join(allocator, &[_][]const u8{ absoluteRootPath, url.path });
        std.debug.print("resolved {s} to {s}\n", .{ url.path, resolvedPath });
        const stat = cwd.statFile(resolvedPath) catch {
            try request.respond("Not found", .{
                .status = std.http.Status.not_found,
            });
            conn.stream.close();
            return;
        };

        if (stat.kind != std.fs.File.Kind.file) {
            try request.respond("Not found", .{
                .status = std.http.Status.not_found,
            });
            conn.stream.close();
            return;
        }

        const extension = std.fs.path.extension(resolvedPath);
        if (std.mem.eql(u8, extension, ".lua")) {
            const bodyReader = try request.reader();
            // return generic 500 on lua error
            const response = invokeLua(allocator, &request, bodyReader, resolvedPath, url) catch LuaResponse{};

            try request.respond(response.body, .{
                .status = response.status,
                .extra_headers = response.headers.items,
            });
        } else {
            const file = try cwd.openFile(resolvedPath, .{ .mode = .read_only });
            // FIXME: we should be streaming files, this is stupid, but I don't want to figure out
            // what the respondStreaming() API wants right now
            const body = try file.reader().readAllAlloc(allocator, MAX_REQUEST_SIZE);
            const contentType = contentTypeForExtension(extension);
            try request.respond(body, .{
                .extra_headers = &[_]std.http.Header{std.http.Header{ .name = "content-type", .value = contentType }},
            });
        }

        if (!request.head.keep_alive) {
            conn.stream.close();
            return;
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var it = std.process.args();
    var i: usize = 0;
    var rootPath: ?[]const u8 = null;

    while (it.next()) |arg| {
        if (i == 1) {
            rootPath = arg;
        }
        i += 1;
    }

    if (rootPath == null) {
        return error.NoRootPath;
    }

    if (!std.fs.path.isAbsolute(rootPath.?)) {
        rootPath = try std.fs.cwd().realpathAlloc(alloc, rootPath.?);
    }

    const addr = try std.net.Address.resolveIp("127.0.0.1", 8000);
    server = try addr.listen(.{ .reuse_address = true });
    std.log.info("server listening on http://localhost:8000", .{});

    std.log.info("serving root path: {s}", .{rootPath.?});

    L = lua.luaL_newstate();
    _ = lua.luaL_openlibs(L);

    utilsLib.initTable(L);

    while (true) {
        const conn = try server.accept();
        _ = try std.Thread.spawn(.{}, handleConn, .{ conn, rootPath.? });
    }
}
