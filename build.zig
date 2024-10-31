const std = @import("std");

const LazyPath = std.Build.LazyPath;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimization = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zua",
        .optimize = optimization,
        .target = target,
        .root_source_file = b.path("src/main.zig"),
    });

    exe.linkSystemLibrary("lua");

    b.installArtifact(exe);

    const exe_tests = b.addTest(.{
        .optimize = optimization,
        .target = target,
        .root_source_file = b.path("src/main.zig"),
    });

    exe_tests.linkSystemLibrary("lua");

    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_tests.step);
}
