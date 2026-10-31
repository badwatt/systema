const std = @import("std");

const cpu_mod = @import("cpu.zig");
const desktop_mod = @import("desktop.zig");
const hostname_mod = @import("hostname.zig");
const kernel_mod = @import("kernel.zig");
const memory_mod = @import("memory.zig");
const palette_mod = @import("palette.zig");
const shell_mod = @import("shell.zig");
const storage_mod = @import("storage.zig");
const system_mod = @import("system.zig");
const uptime_mod = @import("uptime.zig");
const username_mod = @import("username.zig");

/// One line of the info column.
pub const Field = struct {
    icon: []const u8,
    label: []const u8,
    value: []const u8,
};

pub const Modules = struct {
    username: []const u8,
    hostname: []const u8,
    fields: []const Field,
};

/// Shown when a module cannot read its data. Deciding this here keeps the
/// fallback in one place instead of scattering `catch "Unknown"` around.
const unknown = "Unknown";

pub fn init(allocator: std.mem.Allocator, io: std.Io, environ_map: std.process.Environ.Map) !Modules {
    // Display order, glyph and label live in one table: adding a field is one
    // entry here plus one `value()` in this directory.
    const spec = .{
        .{ system_mod, "\u{f313}", "System" },
        .{ kernel_mod, "\u{e712}", "Kernel" },
        .{ desktop_mod, "\u{f2d2}", "Desktop" },
        .{ cpu_mod, "\u{f2db}", "CPU" },
        .{ shell_mod, "\u{e795}", "Shell" },
        .{ uptime_mod, "\u{f017}", "Uptime" },
        .{ memory_mod, "\u{f4bc}", "Memory" },
        .{ storage_mod, "\u{000f194e}", "Storage (/)" },
        .{ palette_mod, "\u{e22b}", "Colors" },
    };

    var fields: std.ArrayList(Field) = .empty;
    try fields.ensureTotalCapacity(allocator, spec.len);

    inline for (spec) |entry| {
        fields.appendAssumeCapacity(.{
            .icon = entry[1],
            .label = entry[2],
            .value = entry[0].value(allocator, io, environ_map) catch unknown,
        });
    }

    return .{
        .username = username_mod.get(environ_map) orelse unknown,
        .hostname = hostname_mod.get(allocator) catch unknown,
        .fields = try fields.toOwnedSlice(allocator),
    };
}

// -- Tests --

fn testEnv(entries: []const [2][]const u8) !std.process.Environ.Map {
    var environ_map = std.process.Environ.Map.init(std.testing.allocator);
    errdefer environ_map.deinit();

    for (entries) |entry| try environ_map.put(entry[0], entry[1]);
    return environ_map;
}

test "init produces one field per module, in display order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var environ_map = try testEnv(&.{
        .{ "USER", "alice" },
        .{ "SHELL", "/usr/bin/zsh" },
        .{ "XDG_CURRENT_DESKTOP", "GNOME" },
        .{ "XDG_SESSION_TYPE", "wayland" },
    });
    defer environ_map.deinit();

    const modules = try init(arena.allocator(), std.testing.io, environ_map);

    try std.testing.expectEqual(@as(usize, 9), modules.fields.len);
    try std.testing.expectEqualStrings("System", modules.fields[0].label);
    try std.testing.expectEqualStrings("alice", modules.username);
    try std.testing.expectEqualStrings("zsh", modules.fields[4].value);
    try std.testing.expectEqualStrings("Colors", modules.fields[modules.fields.len - 1].label);
    try std.testing.expect(modules.username.len > 0);
    try std.testing.expect(modules.hostname.len > 0);
}

test "init still yields a full set of fields when the environment is empty" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const environ_map = std.process.Environ.Map.init(arena.allocator());
    const modules = try init(arena.allocator(), std.testing.io, environ_map);

    try std.testing.expectEqual(@as(usize, 9), modules.fields.len);
    try std.testing.expectEqualStrings("Unknown", modules.username);
    for (modules.fields) |field| {
        try std.testing.expect(field.value.len > 0);
    }
}

test "every module reports every label exactly once" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var environ_map = try testEnv(&.{});
    defer environ_map.deinit();

    const modules = try init(arena.allocator(), std.testing.io, environ_map);

    for (modules.fields, 0..) |field, i| {
        for (modules.fields[i + 1 ..]) |other| {
            try std.testing.expect(!std.mem.eql(u8, field.label, other.label));
        }
    }
}
