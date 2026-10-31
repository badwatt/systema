const std = @import("std");
const Config = @import("config").Config;
const fmt = @import("fmt.zig");

pub fn getHelp(allocator: std.mem.Allocator, io: std.Io, config: *const Config) !noreturn {
    const help = try text(allocator, config.name);

    try fmt.stdout(io, "{s}\n", .{help});

    std.process.exit(0);
}

/// Builds the help message. Kept separate from `getHelp` so it can be tested.
pub fn text(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator,
        \\
        \\Usage:
        \\  {s} [options] [path...]
        \\
        \\  -h, --help                           Print this message and exit
        \\  -v, --version                        Print the version string
        \\
        \\ --logo-path=<path>                    Path to the logo file
        \\ --logo-gap=<number>                   Gap between the logo and the info
        \\ --logo-color=<color>                  Color of the logo
        \\ --icons-color=<color>                 Color of the icons
        \\ --labels-color=<color>                Color of the labels
        \\
    , .{name});
}
