const std = @import("std");
const Colors = @import("style");

pub const Memory = struct {
    total: f64 = 0,
    available: f64 = 0,
    used: f64 = 0,
    used_percent: f64 = 0,
};

/// Parses a single `/proc/meminfo` line such as "MemTotal:       16384000 kB".
fn parseLine(memory: *Memory, line: []const u8) void {
    if (std.mem.startsWith(u8, line, "MemTotal:")) {
        memory.total = parseMeminfoValue(line) orelse return;
    } else if (std.mem.startsWith(u8, line, "MemAvailable:")) {
        memory.available = parseMeminfoValue(line) orelse return;
    }
}

/// Returns the value of a `/proc/meminfo` line converted from kB to GiB.
fn parseMeminfoValue(line: []const u8) ?f64 {
    var value_it = std.mem.tokenizeScalar(u8, line, ':');
    _ = value_it.next();
    const raw = value_it.next() orelse return null;
    const kb = std.fmt.parseFloat(f64, std.mem.trim(u8, raw, "kB \t")) catch return null;
    return kb / 1024.0 / 1024.0;
}

fn finalize(memory: *Memory) void {
    memory.used = memory.total - memory.available;
    memory.used_percent = if (memory.total > 0) (memory.used / memory.total) * 100 else 0;
}

/// Pure parser used by tests and by `readMeminfo`.
pub fn parseMeminfoData(data: []const u8) Memory {
    var memory = Memory{};
    var line_iter = std.mem.splitScalar(u8, data, '\n');
    while (line_iter.next()) |line| parseLine(&memory, line);
    finalize(&memory);
    return memory;
}

fn readMeminfo(io: std.Io) !Memory {
    const file = try std.Io.Dir.openFileAbsolute(io, "/proc/meminfo", .{});
    defer file.close(io);

    var file_buffer: [4096]u8 = undefined;
    var reader = file.reader(io, &file_buffer);

    var memory = Memory{};
    while (try reader.interface.takeDelimiter('\n')) |line| parseLine(&memory, line);
    finalize(&memory);
    return memory;
}

pub fn value(allocator: std.mem.Allocator, io: std.Io, environ_map: std.process.Environ.Map) ![]const u8 {
    _ = environ_map;
    return format(allocator, try readMeminfo(io));
}

pub fn format(allocator: std.mem.Allocator, meminfo: Memory) ![]const u8 {
    return std.fmt.allocPrint(
        allocator,
        "{d:.2} GiB / {d:.2} GiB ({s}{d:.0}%{s})",
        .{ meminfo.used, meminfo.total, Colors.CYAN, meminfo.used_percent, Colors.RESET },
    );
}

// -- Tests --

test "parseMeminfoData: valid /proc/meminfo" {
    const data =
        \\MemTotal:       16384000 kB
        \\MemFree:         8192000 kB
        \\MemAvailable:   12288000 kB
        \\Buffers:         1024000 kB
    ;
    const meminfo = parseMeminfoData(data);

    try std.testing.expectApproxEqAbs(@as(f64, 16384000.0 / 1024.0 / 1024.0), meminfo.total, 0.01);
    try std.testing.expectApproxEqAbs(@as(f64, 12288000.0 / 1024.0 / 1024.0), meminfo.available, 0.01);
    try std.testing.expectApproxEqAbs(meminfo.total - meminfo.available, meminfo.used, 0.01);
    try std.testing.expect(meminfo.used_percent > 0);
}

test "parseMeminfoData: empty input yields zeroes instead of NaN" {
    const meminfo = parseMeminfoData("");

    try std.testing.expectEqual(@as(f64, 0), meminfo.total);
    try std.testing.expectEqual(@as(f64, 0), meminfo.used_percent);
}

test "format renders used, total and percentage" {
    const meminfo = Memory{ .total = 16, .available = 4, .used = 12, .used_percent = 75 };

    const result = try format(std.testing.allocator, meminfo);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("12.00 GiB / 16.00 GiB (\x1b[38;2;0;255;255m75%\x1b[0m)", result);
}
