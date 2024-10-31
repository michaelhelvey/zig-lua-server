const std = @import("std");
const lua = @import("lua.zig");

const Lua = lua.Lua;
const ReceiveHeadError = std.http.Server.ReceiveHeadError;
const ResponseOptions = std.http.Server.Request.RespondOptions;
const Request = std.http.Server.Request;

const ServerConfig = struct {
    // absolute path to directory where we should serve from
    rootPath: []const u8,
    // PORT or defaults to 8000
    port: u16,
};

fn usage() !void {
    const stream = std.io.getStdOut();
    try stream.writeAll(
        \\ zua 0.0.1
        \\ A simple (and rather silly) zig + lua http server
        \\
        \\ USAGE:
        \\  zua <root_path>
        \\
        \\ ARGS:
        \\  <root_path>: the path to the directory that zua should serve from
    );
}

fn parseServerConfig(alloc: std.mem.Allocator) !ServerConfig {
    const args = try std.process.argsAlloc(alloc);
    if (args.len != 2) {
        try usage();
        std.process.exit(1);
    }

    const portStr = std.process.getEnvVarOwned(alloc, "PORT") catch "8000";
    const port = try std.fmt.parseInt(u16, portStr, 10);

    const maybeAbsolutePath = args[1];
    if (std.fs.path.isAbsolute(maybeAbsolutePath)) {
        return .{
            .rootPath = maybeAbsolutePath,
            .port = port,
        };
    }

    const absolutePath = try std.fs.cwd().realpathAlloc(alloc, maybeAbsolutePath);
    return .{
        .rootPath = absolutePath,
        .port = port,
    };
}

const MAX_HEADER_SIZE = 4096;
const MAX_REQUEST_SIZE = 1024 * 16;

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

fn invokeLuaFunction(
    vm: *Lua,
    file: [:0]const u8,
    func: []const u8,
    request: *Request,
    url: Url,
    body: []const u8,
) !void {
    // execute the file and get our handler function:
    try vm.execFile(file);
    vm.clearStack();
    vm.pushGlobal(func);

    // encode the request object:
    // request.method
    vm.openTable();
    try vm.pushTablePair("method", @tagName(request.head.method));

    // request.url
    try vm.pushValue("url");
    vm.openTable();
    try vm.pushTablePair("path", url.path);

    // request.url.params
    try vm.pushValue("params");
    vm.openTable();
    for (url.query_params.items) |param| {
        try vm.pushTablePair(param.name, param.value);
    }
    vm.pushTable(); // push params onto url
    vm.pushTable(); // push url onto request

    // request.headers
    try vm.pushValue("headers");
    vm.openTable();
    var it = request.iterateHeaders();
    while (it.next()) |header| {
        try vm.pushTablePair(header.name, header.value);
    }
    vm.pushTable(); // push headers onto request

    // request.body
    try vm.pushTablePair("body", body);
    try vm.callFunction(1, 1);
}

const LuaResponse = struct {
    status: std.http.Status,
    headers: []std.http.Header,
    body: []const u8,

    const Self = @This();

    fn readFromState(alloc: std.mem.Allocator, vm: *Lua) !Self {
        var headers = std.ArrayList(std.http.Header).init(alloc);

        const Type = lua.Type;

        // expect that we got back a table
        try vm.expectType(Type.TABLE);
        vm.getField("status");
        const status = try vm.readTop(Type.INTEGER);
        vm.pop(1);

        // headers:
        vm.getField("headers");
        try vm.expectType(Type.TABLE);
        vm.pushNil();

        while (vm.next(-2)) {
            const key = try vm.readIndex(Type.STRING, -2);
            const value = try vm.readIndex(Type.STRING, -1);
            try headers.append(.{ .name = key, .value = value });
            vm.pop(1);
        }

        vm.pop(1);

        // body:
        vm.getField("body");
        const body = try vm.readTop(Type.STRING);

        return .{
            .status = @enumFromInt(status),
            .headers = headers.items,
            .body = body,
        };
    }
};

const QueryParam = struct { name: []const u8, value: []const u8 };

const Url = struct {
    path: []const u8,
    query_params: std.ArrayList(QueryParam),

    const Self = @This();

    const ParserState = enum {
        Key,
        Value,
    };

    fn deinit(self: Self) void {
        self.query_params.deinit();
    }

    // Parses the target into a structured path and query params. `target` must be a slice of memory
    // that will outlive the returned url.
    fn parse(alloc: std.mem.Allocator, target: []const u8) !Self {
        var start: usize = 0;
        var current: usize = 0;
        var foundParams = false;
        var params = std.ArrayList(QueryParam).init(alloc);

        // 1) parse path
        for (target) |char| {
            if (char == '?') {
                foundParams = true;
                break;
            }

            current += 1;
        }

        const path = target[start..current];
        start = current + 1;
        current += 1;

        if (!foundParams) {
            return .{
                .path = path,
                .query_params = params,
            };
        }

        var state = ParserState.Key;
        var currentParam: QueryParam = undefined;

        for (target[start..]) |char| {
            if (char == '=') {
                if (state == ParserState.Key) {
                    currentParam.name = target[start..current];
                    state = ParserState.Value;
                    start = current + 1;
                }
            }

            if (char == '&') {
                if (state == ParserState.Value) {
                    currentParam.value = target[start..current];
                    state = ParserState.Key;
                    start = current + 1;
                    try params.append(currentParam);
                }
            }

            current += 1;
        }

        // if we've advanced current past start & we're in parsing value state, then we have more
        // value to append
        if (start != current) {
            if (state == ParserState.Value) {
                currentParam.value = target[start..current];
                try params.append(currentParam);
            }
        }

        return .{
            .path = path,
            .query_params = params,
        };
    }

    test "target only" {
        const target = "/foo/bar/baz";
        const url = try Url.parse(std.testing.allocator, target);
        defer url.deinit();
        try std.testing.expectEqualStrings(url.path, target);
    }

    test "with one param" {
        const target = "/foo/bar/baz?foo=bar";
        const url = try Url.parse(std.testing.allocator, target);
        defer url.deinit();

        try std.testing.expectEqualStrings(url.path, "/foo/bar/baz");

        try std.testing.expect(url.query_params.items.len == 1);
        const param = url.query_params.items[0];
        try std.testing.expectEqualStrings("foo", param.name);
        try std.testing.expectEqualStrings("bar", param.value);
    }

    test "with one param ending in &" {
        const target = "/foo/bar/baz?foo=bar&";
        const url = try Url.parse(std.testing.allocator, target);
        defer url.deinit();

        try std.testing.expectEqualStrings(url.path, "/foo/bar/baz");

        try std.testing.expect(url.query_params.items.len == 1);
        const param = url.query_params.items[0];
        try std.testing.expectEqualStrings("foo", param.name);
        try std.testing.expectEqualStrings("bar", param.value);
    }

    test "with multiple params" {
        const target = "/foo/bar/baz?foo=bar&baz=quux";
        const url = try Url.parse(std.testing.allocator, target);
        defer url.deinit();

        try std.testing.expectEqualStrings(url.path, "/foo/bar/baz");

        try std.testing.expect(url.query_params.items.len == 2);
        var param = url.query_params.items[0];
        try std.testing.expectEqualStrings("foo", param.name);
        try std.testing.expectEqualStrings("bar", param.value);

        param = url.query_params.items[1];
        try std.testing.expectEqualStrings("baz", param.name);
        try std.testing.expectEqualStrings("quux", param.value);
    }

    test "with malformed" {
        const target = "/foo/bar/baz?foo=bar&baz";
        const url = try Url.parse(std.testing.allocator, target);
        defer url.deinit();

        try std.testing.expectEqualStrings(url.path, "/foo/bar/baz");

        try std.testing.expect(url.query_params.items.len == 1);
        const param = url.query_params.items[0];
        try std.testing.expectEqualStrings("foo", param.name);
        try std.testing.expectEqualStrings("bar", param.value);
    }
};

fn handleConn(conn: std.net.Server.Connection, config: *const ServerConfig, vm: *Lua) !void {
    var headers_buffer: [MAX_HEADER_SIZE]u8 = undefined;
    var httpServer = std.http.Server.init(conn, &headers_buffer);

    while (true) {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        var request = httpServer.receiveHead() catch |err| switch (err) {
            ReceiveHeadError.HttpConnectionClosing => return,
            else => {
                std.log.err("error receiving head: {s}", .{@errorName(err)});
                return;
            },
        };

        var bodyReader = try request.reader();
        const body = try bodyReader.readAllAlloc(alloc, MAX_REQUEST_SIZE);
        const url = try Url.parse(alloc, request.head.target);

        const filePath = try std.fs.path.resolve(
            alloc,
            // url.path will start with "/" so we modify it for resolve()
            &[_][]const u8{ config.rootPath, url.path[1..] },
        );
        std.log.debug("resolved filePath = {s}", .{filePath});

        // TODO: we should probably check permissions or something too, or catch read errors below...
        const stat = std.fs.cwd().statFile(filePath) catch {
            try request.respond("Not found", .{
                .status = std.http.Status.not_found,
            });
            break;
        };

        if (stat.kind != std.fs.File.Kind.file) {
            try request.respond("Not found", .{
                .status = std.http.Status.not_found,
            });
            break;
        }

        const extension = std.fs.path.extension(filePath);
        if (std.mem.eql(u8, extension, ".lua")) {
            const cPath = try alloc.dupeZ(u8, filePath);
            try invokeLuaFunction(vm, cPath, "handle_request", &request, url, body);
            const response = try LuaResponse.readFromState(alloc, vm);
            try request.respond(response.body, .{
                .extra_headers = response.headers,
                .status = response.status,
            });
        } else {
            var send_buffer: [4096]u8 = undefined;
            var response = request.respondStreaming(.{
                .send_buffer = &send_buffer,
                .respond_options = .{
                    .transfer_encoding = .chunked,
                    .extra_headers = &.{
                        .{ .name = "content-type", .value = contentTypeForExtension(extension) },
                    },
                },
            });

            const file = try std.fs.cwd().openFile(filePath, .{});
            defer file.close();

            var fifo = std.fifo.LinearFifo(u8, .Dynamic).init(alloc);
            try fifo.ensureTotalCapacity(1); // 1k of read/write buffer

            try fifo.pump(file.reader(), response.writer());
            try response.endChunked(.{});
        }

        if (!request.head.keep_alive) {
            break;
        }
    }

    conn.stream.close();
}

pub fn main() !void {
    // note: intentionally not defer de-initing here because I don't care if I leak my global
    // scratch allocator...we can use a page for scratch and just keep it around until we exit
    var scratch = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const alloc = scratch.allocator();

    var vm = Lua.init();

    const config = try parseServerConfig(alloc);
    const addr = try std.net.Address.resolveIp("127.0.0.1", config.port);
    var server = try addr.listen(.{ .reuse_address = true });

    std.log.info("serving {s} at http://127.0.0.1:{d}", .{ config.rootPath, config.port });

    while (true) {
        const conn = try server.accept();
        _ = try std.Thread.spawn(.{}, handleConn, .{ conn, &config, &vm });
    }
}

test {
    _ = lua;
    _ = Url;
}
