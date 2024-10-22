const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimization = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zig-lua-server",
        .optimize = optimization,
        .target = target,
        .root_source_file = b.path("src/main.zig"),
    });

    exe.linkSystemLibrary("lua");
    b.installArtifact(exe);
}
