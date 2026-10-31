const std = @import("std");
const Cli = @import("mod.zig");
const Colors = @import("utils").colors;
const fmt = @import("utils").fmt;

pub fn getVersion(self: *Cli) !void {
    const help = try text(self.allocator, self.config.name, self.config.version);

    try fmt.stdout(self.io, "{s}\n", .{help});

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
