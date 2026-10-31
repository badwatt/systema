const std = @import("std");

/// Desktop and session type, e.g. "GNOME (wayland)". A missing variable is not
/// an error: it is reported as unknown for that half only.
pub fn value(allocator: std.mem.Allocator, io: std.Io, environ_map: std.process.Environ.Map) ![]const u8 {
    _ = io;

    const desktop = environ_map.get("XDG_CURRENT_DESKTOP") orelse "Unknown";
    const session = environ_map.get("XDG_SESSION_TYPE") orelse "Unknown";

    return std.fmt.allocPrint(allocator, "{s} ({s})", .{ desktop, session });
}

// -- Tests --

fn testEnv(entries: []const [2][]const u8) !std.process.Environ.Map {
    var environ_map = std.process.Environ.Map.init(std.testing.allocator);
    errdefer environ_map.deinit();

    for (entries) |entry| try environ_map.put(entry[0], entry[1]);
    return environ_map;
}

test "value combines the XDG variables" {
    var environ_map = try testEnv(&.{
        .{ "XDG_CURRENT_DESKTOP", "GNOME" },
        .{ "XDG_SESSION_TYPE", "wayland" },
    });
    defer environ_map.deinit();

    const desktop = try value(std.testing.allocator, std.testing.io, environ_map);
    defer std.testing.allocator.free(desktop);

    try std.testing.expectEqualStrings("GNOME (wayland)", desktop);
}

test "value reports each missing variable separately" {
    var environ_map = try testEnv(&.{.{ "XDG_SESSION_TYPE", "wayland" }});
    defer environ_map.deinit();

    const desktop = try value(std.testing.allocator, std.testing.io, environ_map);
    defer std.testing.allocator.free(desktop);

    try std.testing.expectEqualStrings("Unknown (wayland)", desktop);
}
