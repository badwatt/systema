const std = @import("std");
const Environ = @import("environ").Environ;

/// Desktop and session type, e.g. "GNOME (wayland)". A missing variable is not
/// an error: it is reported as unknown for that half only.
pub fn value(allocator: std.mem.Allocator, io: std.Io, environ: Environ) ![]const u8 {
    _ = io;

    const desktop = environ.get("XDG_CURRENT_DESKTOP") orelse "Unknown";
    const session = environ.get("XDG_SESSION_TYPE") orelse "Unknown";

    return std.fmt.allocPrint(allocator, "{s} ({s})", .{ desktop, session });
}

// -- Tests --

test "value combines the XDG variables" {
    var env = try Environ.Testing.init(std.testing.allocator, &.{
        .{ "XDG_CURRENT_DESKTOP", "GNOME" },
        .{ "XDG_SESSION_TYPE", "wayland" },
    });
    defer env.deinit();

    const desktop = try value(std.testing.allocator, std.testing.io, env.environ);
    defer std.testing.allocator.free(desktop);

    try std.testing.expectEqualStrings("GNOME (wayland)", desktop);
}

test "value reports each missing variable separately" {
    var env = try Environ.Testing.init(std.testing.allocator, &.{.{ "XDG_SESSION_TYPE", "wayland" }});
    defer env.deinit();

    const desktop = try value(std.testing.allocator, std.testing.io, env.environ);
    defer std.testing.allocator.free(desktop);

    try std.testing.expectEqualStrings("Unknown (wayland)", desktop);
}
