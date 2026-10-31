const std = @import("std");

/// Basename of `$SHELL`, e.g. "zsh".
pub fn value(allocator: std.mem.Allocator, io: std.Io, environ_map: std.process.Environ.Map) ![]const u8 {
    _ = io;

    const shell_path = environ_map.get("SHELL") orelse return error.ShellNotSet;
    return allocator.dupe(u8, std.fs.path.basename(shell_path));
}

// -- Tests --

fn testEnv(shell: []const u8) !std.process.Environ.Map {
    var environ_map = std.process.Environ.Map.init(std.testing.allocator);
    errdefer environ_map.deinit();
    try environ_map.put("SHELL", shell);
    return environ_map;
}

test "value strips the directory from $SHELL" {
    var environ_map = try testEnv("/usr/bin/zsh");
    defer environ_map.deinit();

    const shell = try value(std.testing.allocator, std.testing.io, environ_map);
    defer std.testing.allocator.free(shell);

    try std.testing.expectEqualStrings("zsh", shell);
}

test "value fails when $SHELL is unset" {
    var environ_map = std.process.Environ.Map.init(std.testing.allocator);
    defer environ_map.deinit();

    try std.testing.expectError(error.ShellNotSet, value(std.testing.allocator, std.testing.io, environ_map));
}
