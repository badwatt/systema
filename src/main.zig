const std = @import("std");
const Colors = @import("style");
const Modules = @import("modules");
const render = @import("render");
const Config = @import("config").Config;
const log = std.log.scoped(.main);
const zon = @import("zon");
const cli = @import("cli");

pub const ExitStatus = enum(u8) {
    ok = 0,
    usage = 1,
};

/// OS entry point: opens stdout and hands everything to `run`.
///
/// This is the only function without a test: it is the process entry point, so
/// exercising it in-process would either write to fd 1 (which the `zig build
/// test` runner uses as its IPC channel) or call `std.process.exit`. Everything
/// it does beyond opening the writer lives in `run`, which is fully covered.
pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);

    const status = try run(init.gpa, init.io, init.environ_map.*, init.minimal.args, &stdout_writer.interface);
    if (status != .ok) std.process.exit(@backingInt(status));
}

/// The whole program with the output sink injected, so it can be exercised in a
/// test without touching the real stdout.
pub fn run(
    gpa: std.mem.Allocator,
    io: std.Io,
    environ_map: std.process.Environ.Map,
    args: std.process.Args,
    out: *std.Io.Writer,
) !ExitStatus {
    var config = Config{
        .name = @tagName(zon.name),
        .version = zon.version,
    };

    log.debug("{s}***** DEBUG BUILD: {s}{s}{s}: {s}{s}{s} *****{s}", .{ Colors.RED, Colors.YELLOW, config.name, Colors.RESET, Colors.GREEN, config.version, Colors.RED, Colors.RESET });

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    switch (cli.parse(allocator, &config, args)) {
        .run => {},
        .help => {
            try out.print("{s}\n", .{try cli.help.text(allocator, config.name)});
            try out.flush();
            return .ok;
        },
        .version => {
            try out.print("{s}\n", .{try cli.version.text(allocator, config.name, config.version)});
            try out.flush();
            return .ok;
        },
        .unknown => |option| {
            try out.print("Invalid opt: '{s}'\n", .{option});
            try out.flush();
            return .usage;
        },
    }

    const modules = try Modules.init(allocator, io, environ_map);
    try render.print(out, allocator, io, environ_map, &config, modules);
    try out.flush();

    return .ok;
}

// -- Tests --

fn testEnviron() !std.process.Environ.Map {
    var environ_map = std.process.Environ.Map.init(std.testing.allocator);
    errdefer environ_map.deinit();

    try environ_map.put("USER", "alice");
    try environ_map.put("SHELL", "/usr/bin/zsh");
    return environ_map;
}

fn testArgs(comptime argv: []const [:0]const u8) std.process.Args {
    const vector: [argv.len][*:0]const u8 = blk: {
        var result: [argv.len][*:0]const u8 = undefined;
        for (argv, 0..) |arg, i| result[i] = arg.ptr;
        break :blk result;
    };
    return .{ .vector = &vector };
}

test "run renders the info block and reports success" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();

    var environ_map = try testEnviron();
    defer environ_map.deinit();

    const status = try run(std.testing.allocator, std.testing.io, environ_map, testArgs(&.{"systema"}), &out.writer);

    try std.testing.expectEqual(ExitStatus.ok, status);
    try std.testing.expect(std.mem.indexOf(u8, out.writer.buffered(), "alice") != null);
}

test "run prints the help message for --help" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();

    var environ_map = try testEnviron();
    defer environ_map.deinit();

    const status = try run(std.testing.allocator, std.testing.io, environ_map, testArgs(&.{ "systema", "--help" }), &out.writer);

    try std.testing.expectEqual(ExitStatus.ok, status);
    try std.testing.expect(std.mem.indexOf(u8, out.writer.buffered(), "Usage:") != null);
}

test "run prints the version for --version" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();

    var environ_map = try testEnviron();
    defer environ_map.deinit();

    const status = try run(std.testing.allocator, std.testing.io, environ_map, testArgs(&.{ "systema", "--version" }), &out.writer);

    try std.testing.expectEqual(ExitStatus.ok, status);
    try std.testing.expect(std.mem.indexOf(u8, out.writer.buffered(), "version") != null);
}

test "run reports a usage error for an unknown option" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();

    var environ_map = try testEnviron();
    defer environ_map.deinit();

    const status = try run(std.testing.allocator, std.testing.io, environ_map, testArgs(&.{ "systema", "--nope" }), &out.writer);

    try std.testing.expectEqual(ExitStatus.usage, status);
    try std.testing.expectEqualStrings("Invalid opt: 'nope'\n", out.writer.buffered());
}

test "run with the logo disabled still renders every field" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();

    var environ_map = try testEnviron();
    defer environ_map.deinit();

    const status = try run(
        std.testing.allocator,
        std.testing.io,
        environ_map,
        testArgs(&.{ "systema", "--logo-gap=1" }),
        &out.writer,
    );

    try std.testing.expectEqual(ExitStatus.ok, status);
    try std.testing.expect(std.mem.count(u8, out.writer.buffered(), "\n") >= 11);
}
