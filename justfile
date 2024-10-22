default:
    zig build -freference-trace=100
    ./zig-out/bin/zig-lua-server

play:
    lua ./lua/playground.lua
