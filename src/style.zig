const std = @import("std");

/// hex() will make use of comptimePrint if the allocator is null,
/// else allocPrint.
pub fn hex(allocator: anytype, hex_code: []const u8) ![]const u8 {
    const clean_hex = if (std.mem.startsWith(u8, hex_code, "#")) hex_code[1..] else hex_code;

    if (clean_hex.len != 6) {
        if (@TypeOf(allocator) == @TypeOf(null)) {
            @compileError("Hex color must be 6 characters long (RRGGBB)");
        }
        return error.InvalidLength;
    }

    const r = std.fmt.parseInt(u8, clean_hex[0..2], 16) catch |err| {
        if (@TypeOf(allocator) == @TypeOf(null)) @compileError("Invalid Hex Red");
        return err;
    };
    const g = std.fmt.parseInt(u8, clean_hex[2..4], 16) catch |err| {
        if (@TypeOf(allocator) == @TypeOf(null)) @compileError("Invalid Hex Green");
        return err;
    };
    const b = std.fmt.parseInt(u8, clean_hex[4..6], 16) catch |err| {
        if (@TypeOf(allocator) == @TypeOf(null)) @compileError("Invalid Hex Blue");
        return err;
    };

    if (@TypeOf(allocator) == @TypeOf(null)) {
        return std.fmt.comptimePrint("\x1b[38;2;{};{};{}m", .{ r, g, b });
    } else {
        return std.fmt.allocPrint(allocator, "\x1b[38;2;{};{};{}m", .{ r, g, b });
    }
}

pub const RED = hex(null, "#F38BA8") catch unreachable;
pub const GREEN = hex(null, "#A6E3A1") catch unreachable;
pub const YELLOW = hex(null, "#F9E2AF") catch unreachable;
pub const BLUE = hex(null, "#89B4FA") catch unreachable;
pub const MAGENTA = hex(null, "#CBA6F7") catch unreachable;
pub const CYAN = hex(null, "#00FFFF") catch unreachable;
pub const GRAY = hex(null, "#585B70") catch unreachable;
pub const BLACK = hex(null, "#1E1E2E") catch unreachable;

pub const RESET = "\x1b[0m";

// -- Tests --

test "hex: valid 6-char hex returns an ANSI foreground color" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectEqualStrings("\x1b[38;2;170;187;204m", try hex(arena.allocator(), "AABBCC"));
}

test "hex: accepts a leading #" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectEqualStrings("\x1b[38;2;170;187;204m", try hex(arena.allocator(), "#AABBCC"));
}

test "hex: rejects the wrong length" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectError(error.InvalidLength, hex(arena.allocator(), "ABC"));
}

test "hex: rejects non-hex digits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectError(error.InvalidCharacter, hex(arena.allocator(), "GGGGGG"));
}

test "comptime palette is populated" {
    for ([_][]const u8{ RED, GREEN, BLUE, CYAN, RESET }) |color| {
        try std.testing.expect(color.len > 0);
    }
}
