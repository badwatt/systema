const std = @import("std");

/// The user this process runs as, or null when `$USER` is not set.
pub fn get(environ_map: std.process.Environ.Map) ?[]const u8 {
    return environ_map.get("USER");
}

// -- Tests --

fn testEnv(user: ?[]const u8) !std.process.Environ.Map {
    var environ_map = std.process.Environ.Map.init(std.testing.allocator);
    errdefer environ_map.deinit();

    if (user) |value| try environ_map.put("USER", value);
    return environ_map;
}

test "get returns $USER" {
    var environ_map = try testEnv("alice");
    defer environ_map.deinit();

    try std.testing.expectEqualStrings("alice", get(environ_map).?);
}

test "get returns null when $USER is unset" {
    var environ_map = try testEnv(null);
    defer environ_map.deinit();

    try std.testing.expect(get(environ_map) == null);
}
