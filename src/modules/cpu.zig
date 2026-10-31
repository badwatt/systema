const std = @import("std");
const readKeyValueLine = @import("keys.zig").readKeyValueLine;

pub fn getCpuInfo(allocator: std.mem.Allocator, io: std.Io) []const u8 {
    return readKeyValueLine(allocator, io, "/proc/cpuinfo", "model name", ':') catch "Unknown";
}
