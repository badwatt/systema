const std = @import("std");
const Environ = @import("environ").Environ;
const readKeyValueLine = @import("keys.zig").readKeyValueLine;

/// `model name` from /proc/cpuinfo.
pub fn value(allocator: std.mem.Allocator, io: std.Io, environ: Environ) ![]const u8 {
    _ = environ;
    return readKeyValueLine(allocator, io, "/proc/cpuinfo", "model name", ':');
}
