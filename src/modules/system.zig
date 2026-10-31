const std = @import("std");
const readKeyValueLine = @import("keys.zig").readKeyValueLine;

pub fn getSystemInfo(allocator: std.mem.Allocator, io: std.Io) []const u8 {
    const raw = readKeyValueLine(allocator, io, "/etc/os-release", "PRETTY_NAME", '=') catch return "Unknown";
    defer allocator.free(raw);

    return allocator.dupe(u8, std.mem.trim(u8, raw, "\"")) catch "Unknown";
}
