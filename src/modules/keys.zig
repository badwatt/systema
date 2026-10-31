const std = @import("std");

const Dir = std.Io.Dir;

/// Returns the trimmed value of the first line of `file_path` that starts with
/// `starts_with` and contains `separator`, e.g. `PRETTY_NAME` in os-release.
pub fn readKeyValueLine(allocator: std.mem.Allocator, io: std.Io, file_path: []const u8, starts_with: []const u8, from_character: u8) ![]const u8 {
    const file = try Dir.openFileAbsolute(io, file_path, .{});
    defer file.close(io);

    var file_buffer: [4096]u8 = undefined;
    var reader = file.reader(io, &file_buffer);
    while (try reader.interface.takeDelimiter('\n')) |line| {
        if (std.mem.startsWith(u8, line, starts_with)) {
            var name_it = std.mem.tokenizeScalar(u8, line, from_character);
            _ = name_it.next();
            const name = name_it.next() orelse return error.LineIsNull;

            return try allocator.dupe(u8, std.mem.trim(u8, name, " \t"));
        }
    }

    return error.LineNotFound;
}

// -- Tests --

test "readKeyValueLine reads the value of a known key" {
    const tmp_path = "/tmp/systema_test_keys.txt";
    {
        const file = try std.Io.Dir.createFileAbsolute(std.testing.io, tmp_path, .{});
        defer file.close(std.testing.io);
        var writer = file.writer(std.testing.io, &.{});
        try writer.interface.writeAll("PRETTY_NAME=\"TestOS 1.0\"\n");
        try writer.interface.writeAll("ID=testos\n");
        try writer.interface.flush();
    }
    defer std.Io.Dir.deleteFileAbsolute(std.testing.io, tmp_path) catch {};

    const result = try readKeyValueLine(std.testing.allocator, std.testing.io, tmp_path, "PRETTY_NAME", '=');
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("\"TestOS 1.0\"", result);
}

test "readKeyValueLine returns an error for a missing key" {
    const tmp_path = "/tmp/systema_test_keys_missing.txt";
    {
        const file = try std.Io.Dir.createFileAbsolute(std.testing.io, tmp_path, .{});
        defer file.close(std.testing.io);
        var writer = file.writer(std.testing.io, &.{});
        try writer.interface.writeAll("SOME=thing\n");
        try writer.interface.flush();
    }
    defer std.Io.Dir.deleteFileAbsolute(std.testing.io, tmp_path) catch {};

    try std.testing.expectError(error.LineNotFound, readKeyValueLine(std.testing.allocator, std.testing.io, tmp_path, "MISSING", '='));
}

test "readKeyValueLine reports a key that has no value" {
    const tmp_path = "/tmp/systema_test_keys_novalue.txt";
    {
        const file = try std.Io.Dir.createFileAbsolute(std.testing.io, tmp_path, .{});
        defer file.close(std.testing.io);
        var writer = file.writer(std.testing.io, &.{});
        try writer.interface.writeAll("PRETTY_NAME\n");
        try writer.interface.flush();
    }
    defer std.Io.Dir.deleteFileAbsolute(std.testing.io, tmp_path) catch {};

    try std.testing.expectError(error.LineIsNull, readKeyValueLine(std.testing.allocator, std.testing.io, tmp_path, "PRETTY_NAME", '='));
}

test "readKeyValueLine propagates a failure to open the file" {
    try std.testing.expectError(
        error.FileNotFound,
        readKeyValueLine(std.testing.allocator, std.testing.io, "/nonexistent/systema", "KEY", '='),
    );
}
