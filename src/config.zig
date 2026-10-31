const std = @import("std");

const Colors = @import("style");

/// Everything about how the output looks. `main` builds the default instance and
/// the CLI mutates it before rendering.
pub const Config = struct {
    name: []const u8,
    version: []const u8,
    logo: Logo = .{},
    icons: Icons = .{},
    labels: Labels = .{},
};

pub const Logo = struct {
    enabled: bool = true,
    embed: []const u8 = @embedFile("assets/logo"),
    path: ?[]const u8 = null,
    color: []const u8 = Colors.BLUE,
    gap: u8 = 3,
};

pub const Icons = struct {
    color: []const u8 = Colors.BLUE,
};

pub const Labels = struct {
    color: []const u8 = Colors.BLUE,
};

// -- Tests --

test "the default logo is the embedded asset, enabled" {
    const logo = Logo{};

    try std.testing.expect(logo.enabled);
    try std.testing.expect(logo.embed.len > 0);
    try std.testing.expect(logo.path == null);
    try std.testing.expect(logo.gap > 0);
}

test "the default colors are ANSI sequences" {
    const config = Config{ .name = "systema", .version = "0.0.0" };

    for ([_][]const u8{ config.logo.color, config.icons.color, config.labels.color }) |color| {
        try std.testing.expect(std.mem.startsWith(u8, color, "\x1b["));
    }
}
