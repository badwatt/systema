const std = @import("std");
const Colors = @import("style");
const Modules = @import("modules");
const render = @import("render");
const Config = @import("config").Config;
const Environ = @import("environ").Environ;
const log = std.log.scoped(.main);
const zon = @import("zon");
const cli = @import("cli");

pub const ExitStatus = enum(u8) {
    ok = 0,
    usage = 1,
};

/// Room for every string this program builds, with space to spare for a large
/// logo file. It lives in .bss, so it costs nothing until it is touched.
var arena_buffer: [256 * 1024]u8 = undefined;

/// OS entry point.
///
/// The parameter is `Init.Minimal` on purpose. Taking `std.process.Init` makes
/// the runtime copy every environment variable into a hash map before `main`
/// runs: with a 173-variable shell that is ~350 allocations and about a quarter
/// of the total runtime. `Environ` reads the raw block instead.
///
/// Two more shortcuts: `init_single_threaded` skips `getCpuCount()` and the
/// SIG.IO/SIG.PIPE handlers that `Threaded.init` installs, and the fixed-buffer
/// arena keeps the program from issuing any heap syscalls at all.
pub fn main(minimal: std.process.Init.Minimal) !void {
    var fba = std.heap.FixedBufferAllocator.init(&arena_buffer);
    var arena = std.heap.ArenaAllocator.init(fba.allocator());
    defer arena.deinit();

    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);

    const status = try run(
        arena.allocator(),
        io,
        .{ .process = minimal.environ },
        minimal.args,
        &stdout_writer.interface,
    );

    if (status != .ok) std.process.exit(@backingInt(status));
}

/// The whole program with the output sink injected, so it can be exercised in a
/// test without touching the real stdout.
pub fn run(
    allocator: std.mem.Allocator,
    io: std.Io,
    environ: Environ,
    args: std.process.Args,
    out: *std.Io.Writer,
) !ExitStatus {
    var config = Config{
        .name = @tagName(zon.name),
        .version = zon.version,
    };

    log.debug("{s}***** DEBUG BUILD: {s}{s}{s}: {s}{s}{s} *****{s}", .{ Colors.RED, Colors.YELLOW, config.name, Colors.RESET, Colors.GREEN, config.version, Colors.RED, Colors.RESET });

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    switch (cli.parse(arena_allocator, &config, args)) {
        .run => {},
        .help => {
            try out.print("{s}\n", .{try cli.help.text(arena_allocator, config.name)});
            try out.flush();
            return .ok;
        },
        .version => {
            try out.print("{s}\n", .{try cli.version.text(arena_allocator, config.name, config.version)});
            try out.flush();
            return .ok;
        },
        .unknown => |option| {
            try out.print("Invalid opt: '{s}'\n", .{option});
            try out.flush();
            return .usage;
        },
    }

    const modules = try Modules.init(arena_allocator, io, environ);
    try render.print(out, arena_allocator, io, environ, &config, modules);
    try out.flush();

    return .ok;
}

// -- Tests --

fn testArgs(comptime argv: []const [:0]const u8) std.process.Args {
    const vector: [argv.len][*:0]const u8 = blk: {
        var result: [argv.len][*:0]const u8 = undefined;
        for (argv, 0..) |arg, i| result[i] = arg.ptr;
        break :blk result;
    };
    return .{ .vector = &vector };
}

fn testEnviron() !Environ.Testing {
    return Environ.Testing.init(std.testing.allocator, &.{
        .{ "USER", "alice" },
        .{ "SHELL", "/usr/bin/zsh" },
    });
}

test "run renders the info block and reports success" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();

    var env = try testEnviron();
    defer env.deinit();

    const status = try run(std.testing.allocator, std.testing.io, env.environ, testArgs(&.{"systema"}), &out.writer);

    try std.testing.expectEqual(ExitStatus.ok, status);
    try std.testing.expect(std.mem.indexOf(u8, out.writer.buffered(), "alice") != null);
}

test "run prints the help message for --help" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();

    var env = try testEnviron();
    defer env.deinit();

    const status = try run(std.testing.allocator, std.testing.io, env.environ, testArgs(&.{ "systema", "--help" }), &out.writer);

    try std.testing.expectEqual(ExitStatus.ok, status);
    try std.testing.expect(std.mem.indexOf(u8, out.writer.buffered(), "Usage:") != null);
}

test "run prints the version for --version" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();

    var env = try testEnviron();
    defer env.deinit();

    const status = try run(std.testing.allocator, std.testing.io, env.environ, testArgs(&.{ "systema", "--version" }), &out.writer);

    try std.testing.expectEqual(ExitStatus.ok, status);
    try std.testing.expect(std.mem.indexOf(u8, out.writer.buffered(), "version") != null);
}

test "run reports a usage error for an unknown option" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();

    var env = try testEnviron();
    defer env.deinit();

    const status = try run(std.testing.allocator, std.testing.io, env.environ, testArgs(&.{ "systema", "--nope" }), &out.writer);

    try std.testing.expectEqual(ExitStatus.usage, status);
    try std.testing.expectEqualStrings("Invalid opt: 'nope'\n", out.writer.buffered());
}

// Exercises exactly the setup `main` uses, including the fixed arena, so that a
// buffer that is too small or an io mode that breaks rendering fails here
// instead of in the shipped binary.
test "run works with the fixed arena and the single-threaded io main uses" {
    var fba = std.heap.FixedBufferAllocator.init(&arena_buffer);
    var arena = std.heap.ArenaAllocator.init(fba.allocator());
    defer arena.deinit();

    var threaded: std.Io.Threaded = .init_single_threaded;

    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();

    const status = try run(arena.allocator(), threaded.io(), Environ.empty, testArgs(&.{"systema"}), &out.writer);

    try std.testing.expectEqual(ExitStatus.ok, status);
    try std.testing.expect(std.mem.indexOf(u8, out.writer.buffered(), "System") != null);
}
