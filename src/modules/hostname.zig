const std = @import("std");

/// The machine hostname. Allocated so that the caller owns it.
pub fn get(allocator: std.mem.Allocator) ![]const u8 {
    var buffer: [std.posix.HOST_NAME_MAX]u8 = undefined;
    return allocator.dupe(u8, try std.posix.gethostname(&buffer));
}

// -- Tests --

test "get returns a non-empty, owned hostname" {
    const hostname = try get(std.testing.allocator);
    defer std.testing.allocator.free(hostname);

    try std.testing.expect(hostname.len > 0);
}
