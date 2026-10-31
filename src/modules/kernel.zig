const std = @import("std");

/// Kernel name, release and machine, e.g. "Linux 6.9.1 (x86_64)".
pub fn value(allocator: std.mem.Allocator, io: std.Io, environ_map: std.process.Environ.Map) ![]const u8 {
    _ = io;
    _ = environ_map;

    const uname = std.posix.uname();
    return std.fmt.allocPrint(allocator, "{s} {s} ({s})", .{
        std.mem.sliceTo(&uname.sysname, 0),
        std.mem.sliceTo(&uname.release, 0),
        std.mem.sliceTo(&uname.machine, 0),
    });
}
