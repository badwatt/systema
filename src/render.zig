const std = @import("std");
const Config = @import("config").Config;
const modules_mod = @import("modules");
const Colors = @import("style");

/// The separator between the label column and the value.
const separator = "\u{e621}";

/// Title line: `user@host ~`.
const title_format = "{s}{s}{s}@{s}{s}{s} ~";

/// Field line: icon, two spaces, a label padded to 14 columns (the longest is
/// "Storage (/)", declared in `modules/mod.zig`), the separator and the value.
const field_format = "{s}{s}  {s}{s:<14}{s}" ++ separator ++ " {s}";

pub fn print(
    allocator: std.mem.Allocator,
    io: std.Io,
    environ_map: std.process.Environ.Map,
    config: *const Config,
    modules: modules_mod.Modules,
) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const out = &stdout_writer.interface;

    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(allocator);

    try lines.append(allocator, try std.fmt.allocPrint(allocator, title_format, .{
        Colors.YELLOW, modules.username, Colors.RED, Colors.GREEN, modules.hostname, Colors.RESET,
    }));

    for (modules.fields) |field| {
        try lines.append(allocator, try std.fmt.allocPrint(allocator, field_format, .{
            config.icons.color,  field.icon,
            config.labels.color, field.label,
            Colors.RESET,        field.value,
        }));
    }

    try out.print("\n", .{});

    if (config.logo.enabled) {
        try printWithLogo(allocator, io, out, environ_map, config, lines.items);
    } else {
        for (lines.items) |line| try out.print("{s}\n", .{line});
    }

    try out.print("\n", .{});
    try out.flush();
}

/// Draws the logo column on the left and the info column on the right.
fn printWithLogo(
    allocator: std.mem.Allocator,
    io: std.Io,
    out: *std.Io.Writer,
    environ_map: std.process.Environ.Map,
    config: *const Config,
    lines: []const []const u8,
) !void {
    const logo_content = try loadLogo(allocator, io, environ_map, config);

    var logo_lines: std.ArrayList([]const u8) = .empty;
    defer logo_lines.deinit(allocator);

    var line_iter = std.mem.splitScalar(u8, logo_content, '\n');
    while (line_iter.next()) |line| try logo_lines.append(allocator, line);

    // A trailing newline in the asset would otherwise add an empty row.
    if (logo_lines.items.len > 0 and logo_lines.items[logo_lines.items.len - 1].len == 0) {
        _ = logo_lines.pop();
    }

    var logo_width: usize = 0;
    for (logo_lines.items) |line| {
        logo_width = @max(logo_width, codepointWidth(line));
    }

    const row_count = @max(logo_lines.items.len, lines.len);
    for (0..row_count) |i| {
        if (i < logo_lines.items.len) {
            const line = logo_lines.items[i];
            try out.print("{s}{s}{s}", .{ config.logo.color, line, Colors.RESET });
            try out.splatByteAll(' ', logo_width - codepointWidth(line) + config.logo.gap);
        } else {
            try out.splatByteAll(' ', logo_width + config.logo.gap);
        }

        if (i < lines.len) try out.print("{s}", .{lines[i]});
        try out.print("\n", .{});
    }
}

/// Returns the file at `config.logo.path` when it can be read, and the embedded
/// logo otherwise. `~/` is expanded from `$HOME`.
fn loadLogo(
    allocator: std.mem.Allocator,
    io: std.Io,
    environ_map: std.process.Environ.Map,
    config: *const Config,
) ![]const u8 {
    const path = config.logo.path orelse return config.logo.embed;

    const expanded: ?[]u8 = if (std.mem.startsWith(u8, path, "~/"))
        if (environ_map.get("HOME")) |home|
            try std.fs.path.join(allocator, &.{ home, path[2..] })
        else
            null
    else
        null;
    defer if (expanded) |buffer| allocator.free(buffer);

    const file = std.Io.Dir.openFileAbsolute(io, expanded orelse path, .{}) catch return config.logo.embed;
    defer file.close(io);

    var file_buffer: [4096]u8 = undefined;
    var reader = file.reader(io, &file_buffer);
    return reader.interface.allocRemaining(allocator, .limited(1024 * 1024)) catch config.logo.embed;
}

/// Display width of a logo line, falling back to the byte length when the line
/// is not valid UTF-8.
fn codepointWidth(line: []const u8) usize {
    return std.unicode.utf8CountCodepoints(line) catch line.len;
}

// -- Tests --

test "loadLogo falls back to the embedded asset for an unreadable path" {
    var environ_map = std.process.Environ.Map.init(std.testing.allocator);
    defer environ_map.deinit();

    var config = Config{ .name = "systema", .version = "0.0.0", .logo = .{ .path = "/nonexistent/logo" } };

    const logo = try loadLogo(std.testing.allocator, std.testing.io, environ_map, &config);
    try std.testing.expectEqualStrings(config.logo.embed, logo);
}

test "loadLogo uses the embedded asset when no path is set" {
    var environ_map = std.process.Environ.Map.init(std.testing.allocator);
    defer environ_map.deinit();

    var config = Config{ .name = "systema", .version = "0.0.0" };

    const logo = try loadLogo(std.testing.allocator, std.testing.io, environ_map, &config);
    try std.testing.expectEqualStrings(config.logo.embed, logo);
}

test "codepointWidth counts codepoints, not bytes" {
    try std.testing.expectEqual(@as(usize, 3), codepointWidth("abc"));
    try std.testing.expectEqual(@as(usize, 1), codepointWidth("\u{f313}"));
}
