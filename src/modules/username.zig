const std = @import("std");
const Environ = @import("environ").Environ;

/// The user this process runs as, or null when `$USER` is not set.
pub fn get(environ: Environ) ?[]const u8 {
    return environ.get("USER");
}

// -- Tests --

test "get returns $USER" {
    var env = try Environ.Testing.init(std.testing.allocator, &.{.{ "USER", "alice" }});
    defer env.deinit();

    try std.testing.expectEqualStrings("alice", get(env.environ).?);
}

test "get returns null when $USER is unset" {
    var env = try Environ.Testing.init(std.testing.allocator, &.{});
    defer env.deinit();

    try std.testing.expect(get(env.environ) == null);
}
