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

    // FIXME: we should make the user do this with CPATH, LD_LIBRARY_PATH etc, it's not my job
    // to find sqlite
    exe.addIncludePath(LazyPath{ .cwd_relative = "/opt/homebrew/opt/sqlite3/include" });
    exe.addLibraryPath(LazyPath{ .cwd_relative = "/opt/homebrew/opt/sqlite3/lib" });

    exe.linkSystemLibrary("lua");
    exe.linkSystemLibrary("sqlite3");

    b.installArtifact(exe);

    const exe_tests = b.addTest(.{
        .optimize = optimization,
        .target = target,
        .root_source_file = b.path("src/main.zig"),
    });

    exe_tests.linkSystemLibrary("lua");
    exe_tests.linkSystemLibrary("sqlite3");

    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_tests.step);
}
