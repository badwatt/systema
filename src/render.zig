const std = @import("std");
const Config = @import("config").Config;
const Environ = @import("environ").Environ;
const modules_mod = @import("modules");
const Colors = @import("style");

/// The separator between the label column and the value.
const separator = "\u{e621}";

/// Title line: `user@host ~`.
const title_format = "{s}{s}{s}@{s}{s}{s} ~";

/// Field line: icon, two spaces, a label padded to 14 columns (the longest is
/// "Storage (/)", declared in `modules/mod.zig`), the separator and the value.
const field_format = "{s}{s}  {s}{s:<14}{s}" ++ separator ++ " {s}";

/// Renders the title, the field column and, when enabled, the logo column.
///
/// `out` is injected so the layout can be asserted without touching stdout.
/// Flushing is the caller's responsibility.
pub fn print(
    out: *std.Io.Writer,
    allocator: std.mem.Allocator,
    io: std.Io,
    environ: Environ,
    config: *const Config,
    modules: modules_mod.Modules,
) !void {
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
        try printWithLogo(out, allocator, io, environ, config, lines.items);
    } else {
        for (lines.items) |line| try out.print("{s}\n", .{line});
    }

    try out.print("\n", .{});
}

/// Draws the logo column on the left and the info column on the right.
fn printWithLogo(
    out: *std.Io.Writer,
    allocator: std.mem.Allocator,
    io: std.Io,
    environ: Environ,
    config: *const Config,
    lines: []const []const u8,
) !void {
    const logo_content = try loadLogo(allocator, io, environ, config);

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
    environ: Environ,
    config: *const Config,
) ![]const u8 {
    const path = config.logo.path orelse return config.logo.embed;

    const expanded: ?[]u8 = if (std.mem.startsWith(u8, path, "~/"))
        if (environ.get("HOME")) |home|
            try std.fs.path.join(allocator, &.{ home, path[2..] })
        else
            null
    else
        null;
    defer if (expanded) |buffer| allocator.free(buffer);

    // An unexpanded "~/" path is relative, and openFileAbsolute asserts on that.
    const resolved = expanded orelse path;
    if (!std.fs.path.isAbsolute(resolved)) return config.logo.embed;

    const file = std.Io.Dir.openFileAbsolute(io, resolved, .{}) catch return config.logo.embed;
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

const logo_path = "/tmp/systema_test_logo.txt";

fn writeLogoFile(content: []const u8) !void {
    const file = try std.Io.Dir.createFileAbsolute(std.testing.io, logo_path, .{});
    defer file.close(std.testing.io);

    var writer = file.writer(std.testing.io, &.{});
    try writer.interface.writeAll(content);
    try writer.interface.flush();
}

fn testEnviron() !Environ.Testing {
    return Environ.Testing.init(std.testing.allocator, &.{
        .{ "USER", "alice" },
        .{ "SHELL", "/usr/bin/zsh" },
    });
}

fn render(
    out: *std.Io.Writer,
    allocator: std.mem.Allocator,
    environ: Environ,
    config: *const Config,
) !void {
    const modules = try modules_mod.init(allocator, std.testing.io, environ);
    try print(out, allocator, std.testing.io, environ, config, modules);
}

/// Column of `needle` in `line`, counted in codepoints and ignoring ANSI
/// escape sequences, so that the visible alignment can be asserted.
fn visibleIndexOf(line: []const u8, needle: []const u8) ?usize {
    const index = std.mem.indexOf(u8, line, needle) orelse return null;

    var column: usize = 0;
    var i: usize = 0;
    while (i < index) {
        if (line[i] == 0x1b) {
            i += 1;
            if (i < index and line[i] == '[') {
                i += 1;
                while (i < index and !(line[i] >= 0x40 and line[i] <= 0x7e)) i += 1;
                i += 1;
            }
            continue;
        }
        const length = std.unicode.utf8ByteSequenceLength(line[i]) catch 1;
        i += @min(length, index - i);
        column += 1;
    }
    return column;
}

test "print draws the title and one line per field when the logo is off" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var env = try testEnviron();
    defer env.deinit();

    const config = Config{ .name = "systema", .version = "1.0.0", .logo = .{ .enabled = false } };
    try render(&out.writer, arena.allocator(), env.environ, &config);

    const output = out.writer.buffered();

    // Leading blank line, title, nine fields, trailing blank line.
    try std.testing.expectEqual(@as(usize, 12), std.mem.count(u8, output, "\n"));
    try std.testing.expect(std.mem.indexOf(u8, output, "alice") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, " ~\n") != null);
}

test "every field line puts the separator in the same column" {
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var env = try testEnviron();
    defer env.deinit();

    const config = Config{ .name = "systema", .version = "1.0.0", .logo = .{ .enabled = false } };
    try render(&out.writer, arena.allocator(), env.environ, &config);

    // This is the regression test for the labels being hand-aligned: "Storage
    // (/)" used to sit one column further right than the rest.
    var expected: ?usize = null;
    var seen: usize = 0;

    var line_iter = std.mem.splitScalar(u8, out.writer.buffered(), '\n');
    while (line_iter.next()) |line| {
        const column = visibleIndexOf(line, separator) orelse continue;
        if (expected) |value| {
            try std.testing.expectEqual(value, column);
        } else {
            expected = column;
        }
        seen += 1;
    }

    try std.testing.expectEqual(@as(usize, 9), seen);
}

test "print interleaves the logo and the info column" {
    defer std.Io.Dir.deleteFileAbsolute(std.testing.io, logo_path) catch {};
    try writeLogoFile("AA\nBB\n");

    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var env = try testEnviron();
    defer env.deinit();

    const config = Config{
        .name = "systema",
        .version = "1.0.0",
        .logo = .{ .path = logo_path, .gap = 2 },
    };
    try render(&out.writer, arena.allocator(), env.environ, &config);

    var line_iter = std.mem.splitScalar(u8, out.writer.buffered(), '\n');
    _ = line_iter.next(); // leading blank line

    const first = line_iter.next().?;
    const first_logo = std.mem.indexOf(u8, first, "AA") orelse return error.MissingLogoLine;
    const first_title = std.mem.indexOf(u8, first, "alice") orelse return error.MissingTitle;
    try std.testing.expect(first_logo < first_title);

    const second = line_iter.next().?;
    try std.testing.expect(std.mem.indexOf(u8, second, "BB") != null);
    try std.testing.expect(std.mem.indexOf(u8, second, "System") != null);

    // Once the logo runs out, the info column keeps going with a blank gutter.
    const third = line_iter.next().?;
    try std.testing.expect(std.mem.startsWith(u8, third, "    "));
    try std.testing.expect(std.mem.indexOf(u8, third, "Kernel") != null);
}

test "loadLogo reads the file at the given path" {
    defer std.Io.Dir.deleteFileAbsolute(std.testing.io, logo_path) catch {};
    try writeLogoFile("X\nY\n");

    var env = try testEnviron();
    defer env.deinit();

    var config = Config{ .name = "systema", .version = "1.0.0", .logo = .{ .path = logo_path } };

    const logo = try loadLogo(std.testing.allocator, std.testing.io, env.environ, &config);
    defer std.testing.allocator.free(logo);

    try std.testing.expectEqualStrings("X\nY\n", logo);
}

test "loadLogo expands a leading ~/ from $HOME" {
    defer std.Io.Dir.deleteFileAbsolute(std.testing.io, logo_path) catch {};
    try writeLogoFile("Z\n");

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var env = try Environ.Testing.init(std.testing.allocator, &.{
        .{ "USER", "alice" },
        .{ "HOME", std.fs.path.dirname(logo_path).? },
    });
    defer env.deinit();

    var config = Config{
        .name = "systema",
        .version = "1.0.0",
        .logo = .{ .path = try std.fmt.allocPrint(allocator, "~/{s}", .{std.fs.path.basename(logo_path)}) },
    };

    const logo = try loadLogo(allocator, std.testing.io, env.environ, &config);
    try std.testing.expectEqualStrings("Z\n", logo);
}

test "loadLogo falls back to the embedded asset for an oversized file" {
    defer std.Io.Dir.deleteFileAbsolute(std.testing.io, logo_path) catch {};

    const file = try std.Io.Dir.createFileAbsolute(std.testing.io, logo_path, .{});
    {
        defer file.close(std.testing.io);
        var writer = file.writer(std.testing.io, &.{});
        const chunk = @as([1024 * 1024]u8, @splat('x'));
        try writer.interface.writeAll(&chunk);
        try writer.interface.writeAll("overflow");
        try writer.interface.flush();
    }

    var env = try testEnviron();
    defer env.deinit();

    var config = Config{ .name = "systema", .version = "1.0.0", .logo = .{ .path = logo_path } };

    const logo = try loadLogo(std.testing.allocator, std.testing.io, env.environ, &config);
    try std.testing.expectEqualStrings(config.logo.embed, logo);
}

test "loadLogo falls back to the embedded asset for an unreadable path" {
    var env = try testEnviron();
    defer env.deinit();

    var config = Config{ .name = "systema", .version = "1.0.0", .logo = .{ .path = "/nonexistent/logo" } };

    const logo = try loadLogo(std.testing.allocator, std.testing.io, env.environ, &config);
    try std.testing.expectEqualStrings(config.logo.embed, logo);
}

test "loadLogo falls back when $HOME is unset for a ~/ path" {
    var config = Config{ .name = "systema", .version = "1.0.0", .logo = .{ .path = "~/logo" } };

    const logo = try loadLogo(std.testing.allocator, std.testing.io, Environ.empty, &config);
    try std.testing.expectEqualStrings(config.logo.embed, logo);
}

test "loadLogo uses the embedded asset when no path is set" {
    var env = try testEnviron();
    defer env.deinit();

    var config = Config{ .name = "systema", .version = "1.0.0" };

    const logo = try loadLogo(std.testing.allocator, std.testing.io, env.environ, &config);
    try std.testing.expectEqualStrings(config.logo.embed, logo);
}

test "codepointWidth counts codepoints, not bytes" {
    try std.testing.expectEqual(@as(usize, 3), codepointWidth("abc"));
    try std.testing.expectEqual(@as(usize, 1), codepointWidth("\u{f313}"));
}

test "codepointWidth falls back to the byte length for invalid UTF-8" {
    try std.testing.expectEqual(@as(usize, 2), codepointWidth("\xff\xfe"));
}
