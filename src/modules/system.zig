const std = @import("std");
const Environ = @import("environ").Environ;
const readKeyValueLine = @import("keys.zig").readKeyValueLine;

/// `PRETTY_NAME` from os-release, without the surrounding quotes.
pub fn value(allocator: std.mem.Allocator, io: std.Io, environ: Environ) ![]const u8 {
    _ = environ;

    const raw = try readKeyValueLine(allocator, io, "/etc/os-release", "PRETTY_NAME", '=');
    defer allocator.free(raw);

    return allocator.dupe(u8, std.mem.trim(u8, raw, "\""));
}
