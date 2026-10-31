const std = @import("std");
const root = @import("root");
const Colors = @import("utils").colors;
const username_mod = @import("username.zig");
const hostname_mod = @import("hostname.zig");
const system_mod = @import("system.zig");
const kernel_mod = @import("kernel.zig");
const cpu_mod = @import("cpu.zig");
const shell_mod = @import("shell.zig");
const memory_mod = @import("memory.zig");
const desktop_mod = @import("desktop.zig");
const uptime_mod = @import("uptime.zig");
const storage_mod = @import("storage.zig");
const colors_mod = @import("colors.zig");

pub const Self = @This();

var hostname_buf: [std.posix.HOST_NAME_MAX]u8 = undefined;

allocator: std.mem.Allocator,
io: std.Io,
username: []const u8,
hostname: []const u8,
system: []const u8,
kernel: []const u8,
cpu: []const u8,
shell: []const u8,
memory: []const u8,
desktop: []const u8,
uptime: []const u8,
storage: []const u8,
colors: []const u8,

pub fn init(self: *Self, allocator: std.mem.Allocator, io: std.Io, environ_map: std.process.Environ.Map) !void {
    self.* = .{
        .allocator = allocator,
        .io = io,
        .username = username_mod.getUsername(environ_map),
        .hostname = hostname_mod.getHostname(&hostname_buf),
        .system = system_mod.getSystemInfo(allocator, io),
        .kernel = kernel_mod.getKernelInfo(allocator),
        .cpu = cpu_mod.getCpuInfo(allocator, io),
        .shell = try shell_mod.getShell(allocator, environ_map),
        .memory = try memory_mod.getMemoryInfo(allocator, io),
        .desktop = try desktop_mod.getDesktop(allocator, environ_map),
        .uptime = try uptime_mod.getUptimeInfo(allocator, io),
        .storage = try storage_mod.getStorage(allocator, "/"),
        .colors = try colors_mod.getColors(allocator),
    };
}

pub fn print(io: std.Io, environ_map: std.process.Environ.Map, config: *const root.Config, modules: Self) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const out = &stdout_writer.interface;

    var info_lines: std.ArrayList([]const u8) = .empty;
    defer info_lines.deinit(modules.allocator);

    try info_lines.append(modules.allocator, try std.fmt.allocPrint(modules.allocator, "{s}{s}{s}@{s}{s}{s} ~", .{
        Colors.YELLOW, modules.username, Colors.RED, Colors.GREEN, modules.hostname, Colors.RESET,
    }));

    try info_lines.append(modules.allocator, try std.fmt.allocPrint(modules.allocator, "{s}  {s}{s:<14}{s} {s}", .{ config.icons.color, config.labels.color, "System", Colors.RESET, modules.system }));
    try info_lines.append(modules.allocator, try std.fmt.allocPrint(modules.allocator, "{s}  {s}{s:<14}{s} {s}", .{ config.icons.color, config.labels.color, "Kernel", Colors.RESET, modules.kernel }));
    try info_lines.append(modules.allocator, try std.fmt.allocPrint(modules.allocator, "{s}  {s}{s:<14}{s} {s}", .{ config.icons.color, config.labels.color, "Desktop", Colors.RESET, modules.desktop }));
    try info_lines.append(modules.allocator, try std.fmt.allocPrint(modules.allocator, "{s}  {s}{s:<14}{s} {s}", .{ config.icons.color, config.labels.color, "CPU", Colors.RESET, modules.cpu }));
    try info_lines.append(modules.allocator, try std.fmt.allocPrint(modules.allocator, "{s}  {s}{s:<14}{s} {s}", .{ config.icons.color, config.labels.color, "Shell", Colors.RESET, modules.shell }));
    try info_lines.append(modules.allocator, try std.fmt.allocPrint(modules.allocator, "{s}  {s}{s:<14}{s} {s}", .{ config.icons.color, config.labels.color, "Uptime", Colors.RESET, modules.uptime }));
    try info_lines.append(modules.allocator, try std.fmt.allocPrint(modules.allocator, "{s}  {s}{s:<14}{s} {s}", .{ config.icons.color, config.labels.color, "Memory", Colors.RESET, modules.memory }));
    try info_lines.append(modules.allocator, try std.fmt.allocPrint(modules.allocator, "{s}󱥎  {s}{s:<14}{s} {s}", .{ config.icons.color, config.labels.color, "Storage (/)", Colors.RESET, modules.storage }));
    try info_lines.append(modules.allocator, try std.fmt.allocPrint(modules.allocator, "{s}  {s}{s:<14}{s} {s}", .{ config.icons.color, config.labels.color, "Colors", Colors.RESET, modules.colors }));

    try out.print("\n", .{});

    if (config.logo.enabled) {
        var logo_list: std.ArrayList([]const u8) = .empty;
        defer logo_list.deinit(modules.allocator);

        var logo_content = config.logo.embed;
        if (config.logo.path) |p| {
            var path = p;
            var path_alloc: ?[]u8 = null;
            defer if (path_alloc) |ptr| modules.allocator.free(ptr);

            if (std.mem.startsWith(u8, p, "~/")) {
                if (environ_map.get("HOME")) |home| {
                    if (std.fs.path.join(modules.allocator, &[_][]const u8{ home, p[2..] })) |joined| {
                        path_alloc = joined;
                        path = joined;
                    } else |_| {}
                } else {}
            }

            if (std.Io.Dir.openFileAbsolute(io, path, .{})) |file| {
                defer file.close(io);
                var file_buffer: [4096]u8 = undefined;
                var reader = file.reader(io, &file_buffer);
                if (reader.interface.allocRemaining(modules.allocator, .limited(std.math.maxInt(usize)))) |content| {
                    logo_content = content;
                } else |_| {}
            } else |_| {}
        }

        var line_iter = std.mem.splitScalar(u8, logo_content, '\n');
        while (line_iter.next()) |line| {
            try logo_list.append(modules.allocator, line);
        }
        if (logo_list.items.len > 0 and logo_list.items[logo_list.items.len - 1].len == 0) {
            _ = logo_list.pop();
        }

        const logo = logo_list.items;
        var logo_width: usize = 0;
        for (logo) |line| {
            const width = std.unicode.utf8CountCodepoints(line) catch line.len;
            if (width > logo_width) logo_width = width;
        }
        const gap = config.logo.gap;

        const max_lines = @max(logo.len, info_lines.items.len);
        for (0..max_lines) |i| {
            if (i < logo.len) {
                try out.print("{s}{s}{s}", .{ config.logo.color, logo[i], Colors.RESET });
                const width = std.unicode.utf8CountCodepoints(logo[i]) catch logo[i].len;
                const padding = logo_width - width + gap;
                try out.splatByteAll(' ', padding);
            } else {
                const padding = logo_width + gap;
                try out.splatByteAll(' ', padding);
            }

            if (i < info_lines.items.len) {
                try out.print("{s}", .{info_lines.items[i]});
            }
            try out.print("\n", .{});
        }
    } else {
        for (info_lines.items) |line| {
            try out.print("{s}\n", .{line});
        }
    }

    try out.print("\n", .{});
    try out.flush();
}

// -- Tests --

fn testEnv(entries: []const [2][]const u8) !std.process.Environ.Map {
    var environ_map = std.process.Environ.Map.init(std.testing.allocator);
    errdefer environ_map.deinit();

    for (entries) |entry| try environ_map.put(entry[0], entry[1]);
    return environ_map;
}

test "parseMeminfoData: valid /proc/meminfo" {
    const data =
        \\MemTotal:       16384000 kB
        \\MemFree:         8192000 kB
        \\MemAvailable:   12288000 kB
        \\Buffers:         1024000 kB
    ;
    const meminfo = memory_mod.parseMeminfoData(data);
    try std.testing.expectApproxEqAbs(@as(f64, 16384000.0 / 1024.0 / 1024.0), meminfo.total, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 12288000.0 / 1024.0 / 1024.0), meminfo.available, 0.01);
    try std.testing.expectApproxEqAbs(meminfo.total - meminfo.available, meminfo.used, 0.01);
    try std.testing.expect(meminfo.used_percent > 0);
}

test "parseMeminfoData: empty input yields zeroes instead of NaN" {
    const meminfo = memory_mod.parseMeminfoData("");
    try std.testing.expectEqual(@as(f64, 0), meminfo.total);
    try std.testing.expectEqual(@as(f64, 0), meminfo.used_percent);
}

test "getMemoryInfo reports used and total in GiB" {
    const result = try memory_mod.getMemoryInfo(std.testing.allocator, std.testing.io);
    defer std.testing.allocator.free(result);

    try std.testing.expect(std.mem.indexOf(u8, result, " GiB / ") != null);
    try std.testing.expect(std.mem.indexOf(u8, result, " GiB (") != null);
}

test "getHostname returns valid slice" {
    var buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const host = hostname_mod.getHostname(&buf);
    try std.testing.expect(host.len > 0);
}

test "getKernelInfo returns non-empty string" {
    const result = kernel_mod.getKernelInfo(std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "getColors produces non-empty string" {
    const result = try colors_mod.getColors(std.testing.allocator);
    defer std.testing.allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "getShell strips the directory from $SHELL" {
    var environ_map = try testEnv(&.{
        .{ "SHELL", "/usr/bin/zsh" },
        .{ "USER", "alice" },
    });
    defer environ_map.deinit();

    const shell = try shell_mod.getShell(std.testing.allocator, environ_map);
    defer std.testing.allocator.free(shell);

    try std.testing.expectEqualStrings("zsh", shell);
}

test "getShell falls back when $SHELL is unset" {
    var environ_map = try testEnv(&.{});
    defer environ_map.deinit();

    try std.testing.expectEqualStrings("Unknown", try shell_mod.getShell(std.testing.allocator, environ_map));
}

test "getUsername reads $USER and falls back when unset" {
    var environ_map = try testEnv(&.{.{ "USER", "alice" }});
    defer environ_map.deinit();
    try std.testing.expectEqualStrings("alice", username_mod.getUsername(environ_map));

    var empty = try testEnv(&.{});
    defer empty.deinit();
    try std.testing.expectEqualStrings("NO_USER_NAME_FOUND", username_mod.getUsername(empty));
}

test "getDesktop combines the XDG environment variables" {
    var environ_map = try testEnv(&.{
        .{ "XDG_CURRENT_DESKTOP", "GNOME" },
        .{ "XDG_SESSION_TYPE", "wayland" },
    });
    defer environ_map.deinit();

    const desktop = try desktop_mod.getDesktop(std.testing.allocator, environ_map);
    defer std.testing.allocator.free(desktop);

    try std.testing.expectEqualStrings("GNOME (wayland)", desktop);
}

test "getDesktop falls back when the XDG variables are unset" {
    var environ_map = try testEnv(&.{});
    defer environ_map.deinit();

    const desktop = try desktop_mod.getDesktop(std.testing.allocator, environ_map);
    defer std.testing.allocator.free(desktop);

    try std.testing.expectEqualStrings("Unknown (Unknown)", desktop);
}

test "getSystemInfo returns an unquoted PRETTY_NAME" {
    const result = system_mod.getSystemInfo(std.testing.allocator, std.testing.io);
    if (std.mem.eql(u8, result, "Unknown")) return; // /etc/os-release is not guaranteed
    defer std.testing.allocator.free(result);

    try std.testing.expect(result.len > 0);
    try std.testing.expect(std.mem.indexOfScalar(u8, result, '"') == null);
}

test "getCpuInfo is non-empty" {
    const result = cpu_mod.getCpuInfo(std.testing.allocator, std.testing.io);
    if (std.mem.eql(u8, result, "Unknown")) return; // /proc/cpuinfo is not guaranteed
    defer std.testing.allocator.free(result);

    try std.testing.expect(result.len > 0);
}

// NOTE: this test also keeps `uptime.zig` reachable from the test root. Zig only
// collects test blocks from files that get analyzed, so dropping it silently drops
// every test declared in uptime.zig from the test binary.
test "getUptimeInfo returns a formatted duration" {
    const result = try uptime_mod.getUptimeInfo(std.testing.allocator, std.testing.io);
    defer std.testing.allocator.free(result);

    try std.testing.expect(result.len > 0);
}
