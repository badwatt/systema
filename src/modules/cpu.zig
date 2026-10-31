const std = @import("std");
const readKeyValueLine = @import("keys.zig").readKeyValueLine;

/// `model name` from /proc/cpuinfo.
pub fn value(allocator: std.mem.Allocator, io: std.Io, environ_map: std.process.Environ.Map) ![]const u8 {
    _ = environ_map;
    return readKeyValueLine(allocator, io, "/proc/cpuinfo", "model name", ':');
}
