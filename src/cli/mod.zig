const std = @import("std");
const Config = @import("config").Config;
const fmt = @import("fmt.zig");
const Colors = @import("style");
const help_mod = @import("help.zig");
const version_mod = @import("version.zig");

/// Parses `args` and applies the recognised options to `config`. Prints and
/// exits for `--help` and `--version`.
pub fn parse(allocator: std.mem.Allocator, io: std.Io, config: *Config, args: std.process.Args) !void {
    var args_iter = std.process.Args.iterate(args);
    _ = args_iter.next(); // skip the binary name
    while (args_iter.next()) |arg| {
        var split = std.mem.splitScalar(u8, arg[2..], '=');
        const opt = split.first();
        const val = split.rest();

        switch (optKind(arg)) {
            .short => {
                for (arg[1..]) |b| switch (b) {
                    'h' => try help_mod.getHelp(allocator, io, config),
                    'v' => try version_mod.getVersion(allocator, io, config),
                    else => {
                        try fmt.stderr(io, "Invalid opt: '{c}'\n", .{b});
                        std.process.exit(1);
                    },
                };
            },
            .long => {
                if (eql(opt, "help")) {
                    try help_mod.getHelp(allocator, io, config);
                } else if (eql(opt, "version")) {
                    try version_mod.getVersion(allocator, io, config);
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
                    try fmt.stderr(io, "Invalid opt: '{s}'\n", .{opt});
                    std.process.exit(1);
                }
            },
            .positional => {},
        }
    }
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

test "help text documents the usage line and every supported option" {
    const msg = try help_mod.text(std.testing.allocator, "systema");
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
    const msg = try version_mod.text(std.testing.allocator, "systema", "1.2.3");
    defer std.testing.allocator.free(msg);

    try std.testing.expect(std.mem.indexOf(u8, msg, "SYSTEMA") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "1.2.3") != null);
}
