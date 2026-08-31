const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. Root module for library
    const zserde_mod = b.addModule("zserde", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 2. Unit & Integration Tests using root_module
    const unit_tests = b.addTest(.{
        .root_module = zserde_mod,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run library unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // 3. Examples executable using root_module
    const example_mod = b.createModule(.{
        .root_source_file = b.path("examples/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    example_mod.addImport("zserde", zserde_mod);

    const example_exe = b.addExecutable(.{
        .name = "zserde-example",
        .root_module = example_mod,
    });

    const run_example = b.addRunArtifact(example_exe);
    const example_step = b.step("run-example", "Run zserde example application");
    example_step.dependOn(&run_example.step);
}
