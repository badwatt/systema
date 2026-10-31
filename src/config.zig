const Colors = @import("utils").colors;

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
