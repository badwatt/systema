const std = @import("std");
const zon = @import("build.zig.zon");

pub const version = std.SemanticVersion.parse(zon.version) catch @panic("Invalid version in build.zig.zon");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const style_mod = b.createModule(.{
        .root_source_file = b.path("src/style.zig"),
        .target = target,
        .optimize = optimize,
    });

    const config_mod = b.createModule(.{
        .root_source_file = b.path("src/config.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "style", .module = style_mod },
        },
    });

    const cli_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/mod.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "style", .module = style_mod },
            .{ .name = "config", .module = config_mod },
        },
    });

    const modules_mod = b.createModule(.{
        .root_source_file = b.path("src/modules/mod.zig"),
        .target = target,
        .optimize = optimize,
        // storage.zig calls statvfs(3) through libc.
        .link_libc = target.result.os.tag == .linux,
        .imports = &.{
            .{ .name = "style", .module = style_mod },
            .{ .name = "config", .module = config_mod },
        },
    });

    const zon_mod = b.createModule(.{
        .root_source_file = b.path("build.zig.zon"),
        .target = target,
        .optimize = optimize,
    });

    const render_mod = b.createModule(.{
        .root_source_file = b.path("src/render.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "style", .module = style_mod },
            .{ .name = "config", .module = config_mod },
            .{ .name = "modules", .module = modules_mod },
        },
    });

    const app_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "cli", .module = cli_mod },
            .{ .name = "modules", .module = modules_mod },
            .{ .name = "render", .module = render_mod },
            .{ .name = "config", .module = config_mod },
            .{ .name = "style", .module = style_mod },
            .{ .name = "zon", .module = zon_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "systema",
        .version = version,
        .root_module = app_mod,
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    run_cmd.addPassthruArgs();

    const test_step = b.step("test", "Run tests");

    // One test binary per layer, so a file's tests only run when the layer it
    // belongs to is exercised.
    for ([_]*std.Build.Module{ style_mod, config_mod, cli_mod, modules_mod, render_mod, app_mod }) |test_root| {
        test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = test_root })).step);
    }
}
