run:
    zig build -freference-trace=100
    ./zig-out/bin/zua ./lua

clean:
    rm -rf ./zig-out
    rm -rf ./.zig-cache
