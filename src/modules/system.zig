const std = @import("std");
const lineFinder = @import("utils").lineFinder.lineFinder;

pub fn getSystemInfo(allocator: std.mem.Allocator, io: std.Io) []const u8 {
    const raw = lineFinder(allocator, io, "/etc/os-release", "PRETTY_NAME", '=') catch return "Unknown";
    defer allocator.free(raw);

    return allocator.dupe(u8, std.mem.trim(u8, raw, "\"")) catch "Unknown";
}
