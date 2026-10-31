const std = @import("std");
const Config = @import("config").Config;
const Colors = @import("style");
pub const help = @import("help.zig");
pub const version = @import("version.zig");

/// What the caller should do after parsing the arguments.
pub const Outcome = union(enum) {
    /// Nothing special: render the system info.
    run,
    help,
    version,
    /// The option is not recognised. The payload is the offending option, and
    /// points into the argument vector.
    unknown: []const u8,
};

/// Applies the recognised options to `config`. It never writes or exits, so
/// that every option can be exercised in a test.
pub fn parse(allocator: std.mem.Allocator, config: *Config, args: std.process.Args) Outcome {
    var args_iter = std.process.Args.iterate(args);
    _ = args_iter.next(); // skip the binary name

    while (args_iter.next()) |arg| {
        var split = std.mem.splitScalar(u8, arg[2..], '=');
        const opt = split.first();
        const val = split.rest();

        switch (optKind(arg)) {
            .short => for (arg[1..], 1..) |b, i| switch (b) {
                'h' => return .help,
                'v' => return .version,
                else => return .{ .unknown = arg[i .. i + 1] },
            },
            .long => {
                if (eql(opt, "help")) {
                    return .help;
                } else if (eql(opt, "version")) {
                    return .version;
                } else if (eql(opt, "logo-path")) {
                    config.logo.path = val;
                } else if (eql(opt, "logo-color")) {
                    config.logo.color = Colors.hex(allocator, val) catch config.logo.color;
                } else if (eql(opt, "logo-gap")) {
                    config.logo.gap = std.fmt.parseInt(u8, val, 10) catch config.logo.gap;
                } else if (eql(opt, "icons-color")) {
                    config.icons.color = Colors.hex(allocator, val) catch config.icons.color;
                } else if (eql(opt, "labels-color")) {
                    config.labels.color = Colors.hex(allocator, val) catch config.labels.color;
                } else {
                    return .{ .unknown = opt };
                }
            },
            .positional => {},
        }
    }

    return .run;
}

fn optKind(a: []const u8) enum { short, long, positional } {
    if (std.mem.startsWith(u8, a, "--")) return .long;
    if (std.mem.startsWith(u8, a, "-")) return .short;
    return .positional;
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

// -- Tests --

/// Builds an `Args` from a comptime list of NUL-terminated strings.
fn testArgs(comptime argv: []const [:0]const u8) std.process.Args {
    const vector: [argv.len][*:0]const u8 = blk: {
        var result: [argv.len][*:0]const u8 = undefined;
        for (argv, 0..) |arg, i| result[i] = arg.ptr;
        break :blk result;
    };
    return .{ .vector = &vector };
}

const no_args = std.process.Args{ .vector = &.{} };

fn parseInto(config: *Config, comptime argv: []const [:0]const u8) Outcome {
    return parse(std.testing.allocator, config, testArgs(argv));
}

fn testConfig() Config {
    return .{ .name = "systema", .version = "1.0.0" };
}

test "help text documents the usage line and every supported option" {
    const msg = try help.text(std.testing.allocator, "systema");
    defer std.testing.allocator.free(msg);

    try std.testing.expect(std.mem.indexOf(u8, msg, "systema [options] [path...]") != null);

    for ([_][]const u8{
        "--help",
        "--version",
        "--logo-path",
        "--logo-gap",
        "--logo-color",
        "--icons-color",
        "--labels-color",
    }) |option| {
        try std.testing.expect(std.mem.indexOf(u8, msg, option) != null);
    }
}

test "version text upper-cases the app name and embeds the version" {
    const msg = try version.text(std.testing.allocator, "systema", "1.2.3");
    defer std.testing.allocator.free(msg);

    try std.testing.expect(std.mem.indexOf(u8, msg, "SYSTEMA") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "1.2.3") != null);
}

test "parse with no arguments asks for a normal run" {
    var config = testConfig();
    try std.testing.expectEqual(Outcome.run, parse(std.testing.allocator, &config, no_args));
}

test "parse ignores positionals" {
    var config = testConfig();
    try std.testing.expectEqual(Outcome.run, parseInto(&config, &.{ "systema", "some", "paths" }));
}

test "parse returns help for -h and --help" {
    var config = testConfig();
    try std.testing.expectEqual(Outcome.help, parseInto(&config, &.{ "systema", "-h" }));
    try std.testing.expectEqual(Outcome.help, parseInto(&config, &.{ "systema", "--help" }));
}

test "parse returns version for -v and --version" {
    var config = testConfig();
    try std.testing.expectEqual(Outcome.version, parseInto(&config, &.{ "systema", "-v" }));
    try std.testing.expectEqual(Outcome.version, parseInto(&config, &.{ "systema", "--version" }));
}

test "parse rejects an unknown long option" {
    var config = testConfig();

    const outcome = parseInto(&config, &.{ "systema", "--nope" });
    try std.testing.expectEqualStrings("nope", outcome.unknown);
}

test "parse rejects an unknown short option" {
    var config = testConfig();

    const outcome = parseInto(&config, &.{ "systema", "-z" });
    try std.testing.expectEqualStrings("z", outcome.unknown);
}

test "parse applies --logo-path" {
    var config = testConfig();
    _ = parseInto(&config, &.{ "systema", "--logo-path=/tmp/logo" });

    try std.testing.expectEqualStrings("/tmp/logo", config.logo.path.?);
}

test "parse applies --logo-gap and ignores a non-numeric value" {
    var config = testConfig();

    _ = parseInto(&config, &.{ "systema", "--logo-gap=7" });
    try std.testing.expectEqual(@as(u8, 7), config.logo.gap);

    _ = parseInto(&config, &.{ "systema", "--logo-gap=nope" });
    try std.testing.expectEqual(@as(u8, 7), config.logo.gap);
}

test "parse applies the three color options" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var config = testConfig();

    _ = parse(arena.allocator(), &config, testArgs(&.{ "systema", "--logo-color=#112233" }));
    _ = parse(arena.allocator(), &config, testArgs(&.{ "systema", "--icons-color=#00FF00" }));
    _ = parse(arena.allocator(), &config, testArgs(&.{ "systema", "--labels-color=#0000FF" }));

    try std.testing.expectEqualStrings("\x1b[38;2;17;34;51m", config.logo.color);
    try std.testing.expectEqualStrings("\x1b[38;2;0;255;0m", config.icons.color);
    try std.testing.expectEqualStrings("\x1b[38;2;0;0;255m", config.labels.color);
}

test "parse keeps the previous color when the value is not a valid hex" {
    var config = testConfig();
    const before = config.logo.color;

    _ = parseInto(&config, &.{ "systema", "--logo-color=zzz" });
    try std.testing.expectEqualStrings(before, config.logo.color);
}
