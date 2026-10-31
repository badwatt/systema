const std = @import("std");
const Colors = @import("style");

/// Builds the version message.
pub fn text(allocator: std.mem.Allocator, name: []const u8, version: []const u8) ![]const u8 {
    const upper_name = try std.ascii.allocUpperString(allocator, name);
    defer allocator.free(upper_name);

    return std.fmt.allocPrint(allocator,
        \\
        \\  {s}{s} version{s}: {s}{s}{s}
        \\
    , .{ Colors.YELLOW, upper_name, Colors.RESET, Colors.GREEN, version, Colors.RESET });
}
