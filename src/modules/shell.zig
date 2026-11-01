const std = @import("std");
const Environ = @import("environ").Environ;

/// Basename of `$SHELL`, e.g. "zsh".
pub fn value(allocator: std.mem.Allocator, io: std.Io, environ: Environ) ![]const u8 {
    _ = io;

    const shell_path = environ.get("SHELL") orelse return error.ShellNotSet;
    return allocator.dupe(u8, std.fs.path.basename(shell_path));
}

// -- Tests --

test "value strips the directory from $SHELL" {
    var env = try Environ.Testing.init(std.testing.allocator, &.{.{ "SHELL", "/usr/bin/zsh" }});
    defer env.deinit();

    const shell = try value(std.testing.allocator, std.testing.io, env.environ);
    defer std.testing.allocator.free(shell);

    try std.testing.expectEqualStrings("zsh", shell);
}

test "value fails when $SHELL is unset" {
    try std.testing.expectError(error.ShellNotSet, value(std.testing.allocator, std.testing.io, Environ.empty));
}
