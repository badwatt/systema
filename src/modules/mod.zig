const std = @import("std");
const Environ = @import("environ").Environ;

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

/// Display order, glyph and label live in one table: adding a field is one
/// entry here plus one `value()` in this directory.
const default_spec = .{
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

pub fn init(allocator: std.mem.Allocator, io: std.Io, environ: Environ) !Modules {
    return initWith(allocator, io, environ, hostname_mod.get, default_spec);
}

/// Same as `init` but with the hostname source and the provider list injected,
/// so that both `unknown` fallbacks can be exercised in a test. Both parameters
/// are comptime, so `init` pays nothing for them.
pub fn initWith(
    allocator: std.mem.Allocator,
    io: std.Io,
    environ: Environ,
    comptime hostname_provider: anytype,
    comptime spec: anytype,
) !Modules {
    // Resolved first so that a hostname failure degrades to `unknown` instead of
    // aborting the whole render.
    const hostname = hostname_provider(allocator) catch unknown;

    var fields: std.ArrayList(Field) = .empty;
    try fields.ensureTotalCapacity(allocator, spec.len);

    inline for (spec) |entry| {
        fields.appendAssumeCapacity(.{
            .icon = entry[1],
            .label = entry[2],
            .value = entry[0].value(allocator, io, environ) catch unknown,
        });
    }

    return .{
        .username = username_mod.get(environ) orelse unknown,
        .hostname = hostname,
        .fields = try fields.toOwnedSlice(allocator),
    };
}

// -- Tests --

test "init produces one field per module, in display order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var env = try Environ.Testing.init(std.testing.allocator, &.{
        .{ "USER", "alice" },
        .{ "SHELL", "/usr/bin/zsh" },
        .{ "XDG_CURRENT_DESKTOP", "GNOME" },
        .{ "XDG_SESSION_TYPE", "wayland" },
    });
    defer env.deinit();

    const modules = try init(arena.allocator(), std.testing.io, env.environ);

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

    const modules = try init(arena.allocator(), std.testing.io, Environ.empty);

    try std.testing.expectEqual(@as(usize, 9), modules.fields.len);
    try std.testing.expectEqualStrings("Unknown", modules.username);
    for (modules.fields) |field| {
        try std.testing.expect(field.value.len > 0);
    }
}

test "every module reports every label exactly once" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const modules = try init(arena.allocator(), std.testing.io, Environ.empty);

    for (modules.fields, 0..) |field, i| {
        for (modules.fields[i + 1 ..]) |other| {
            try std.testing.expect(!std.mem.eql(u8, field.label, other.label));
        }
    }
}

const FailingProvider = struct {
    fn value(
        allocator: std.mem.Allocator,
        io: std.Io,
        environ: Environ,
    ) ![]const u8 {
        _ = allocator;
        _ = io;
        _ = environ;
        return error.Unavailable;
    }
};

test "initWith falls back to Unknown for a provider that fails" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const modules = try initWith(arena.allocator(), std.testing.io, Environ.empty, hostname_mod.get, .{
        .{ FailingProvider, "\u{f313}", "Broken" },
    });

    try std.testing.expectEqual(@as(usize, 1), modules.fields.len);
    try std.testing.expectEqualStrings("Broken", modules.fields[0].label);
    try std.testing.expectEqualStrings("Unknown", modules.fields[0].value);
}

fn unavailableHostname(allocator: std.mem.Allocator) ![]const u8 {
    _ = allocator;
    return error.Unavailable;
}

test "initWith falls back to Unknown when the hostname cannot be read" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const modules = try initWith(arena.allocator(), std.testing.io, Environ.empty, unavailableHostname, default_spec);

    try std.testing.expectEqualStrings("Unknown", modules.hostname);
    try std.testing.expectEqual(@as(usize, 9), modules.fields.len);
}
