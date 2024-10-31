# zua

A silly little http server written in zig that supports writing request handlers in lua. Just
written to learn more about zig and embedding lua, although you could certainly install some
packages with luarocks and make the handlers do something useful.

## Getting Started

Assumes that you have a working [zig](https://ziglang.org) compiler.

```shell
zig build # compile
./zig-out/bin/zua ./lua # start server, serving the `./lua` directory
```

At this point, zua will be running on port 8000, serving the example `lua` directory in this
project.

### Example requests

```shell
# invoke a lua function:
curl -v http://localhost:8000/index.lua?param1=foo&param2=bar

# serve a static file
curl -v http://localhost:8000/assets/staticfile
```
