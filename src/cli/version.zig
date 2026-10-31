const std = @import("std");
const Config = @import("config").Config;
const Colors = @import("style");
const fmt = @import("fmt.zig");

pub fn getVersion(allocator: std.mem.Allocator, io: std.Io, config: *const Config) !noreturn {
    const help = try text(allocator, config.name, config.version);

    try fmt.stdout(io, "{s}\n", .{help});

    std.process.exit(0);
}

/// Builds the version message. Kept separate from `getVersion` so it can be tested.
pub fn text(allocator: std.mem.Allocator, name: []const u8, version: []const u8) ![]const u8 {
    const upper_name = try std.ascii.allocUpperString(allocator, name);
    defer allocator.free(upper_name);

    return std.fmt.allocPrint(allocator,
        \\
        \\  {s}{s} version{s}: {s}{s}{s}
        \\
    , .{ Colors.YELLOW, upper_name, Colors.RESET, Colors.GREEN, version, Colors.RESET });
}
