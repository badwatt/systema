const std = @import("std");
const Colors = @import("style");

/// The palette swatches. This field has no data behind it: it exists to show
/// what the terminal is asked to render, so unlike the other modules it builds
/// its own colors.
pub fn value(allocator: std.mem.Allocator, io: std.Io, environ_map: std.process.Environ.Map) ![]const u8 {
    _ = io;
    _ = environ_map;

    return std.fmt.allocPrint(allocator, "{s}\u{f111}  {s}\u{f111}  {s}\u{f111}  {s}\u{f111}  {s}\u{f111}  {s}\u{f111} {s}", .{
        Colors.BLUE,
        Colors.CYAN,
        Colors.GREEN,
        Colors.YELLOW,
        Colors.RED,
        Colors.MAGENTA,
        Colors.RESET,
    });
}
