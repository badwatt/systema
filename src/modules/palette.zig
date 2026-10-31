const std = @import("std");
const Style = @import("style").Style;

/// The palette swatches. This field has no data behind it: it exists to show
/// what the terminal is asked to render, so it draws the swatches it is given.
pub fn format(allocator: std.mem.Allocator, style: Style) ![]const u8 {
    const swatches = style.swatches;

    return std.fmt.allocPrint(allocator, "{s}\u{f111}  {s}\u{f111}  {s}\u{f111}  {s}\u{f111}  {s}\u{f111}  {s}\u{f111} {s}", .{
        swatches[0],
        swatches[1],
        swatches[2],
        swatches[3],
        swatches[4],
        swatches[5],
        style.reset,
    });
}

pub fn value(allocator: std.mem.Allocator, io: std.Io, environ_map: std.process.Environ.Map) ![]const u8 {
    _ = io;
    _ = environ_map;

    return format(allocator, .{});
}

// -- Tests --

test "format draws one bullet per swatch" {
    const result = try format(std.testing.allocator, .plain);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqual(@as(usize, 6), std.mem.count(u8, result, "\u{f111}"));
    try std.testing.expect(std.mem.indexOfScalar(u8, result, 0x1b) == null);
}

test "format uses the given swatches" {
    const style = Style{ .swatches = .{ "A", "B", "C", "D", "E", "F" }, .reset = "!" };

    const result = try format(std.testing.allocator, style);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("A\u{f111}  B\u{f111}  C\u{f111}  D\u{f111}  E\u{f111}  F\u{f111} !", result);
}
