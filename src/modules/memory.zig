const std = @import("std");
const Colors = @import("utils").colors;

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
    const value = value_it.next() orelse return null;
    const kb = std.fmt.parseFloat(f64, std.mem.trim(u8, value, "kB \t")) catch return null;
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

pub fn getMemoryInfo(allocator: std.mem.Allocator, io: std.Io) ![]const u8 {
    const meminfo = try readMeminfo(io);

    return std.fmt.allocPrint(
        allocator,
        "{d:.2} GiB / {d:.2} GiB ({s}{d:.0}%{s})",
        .{ meminfo.used, meminfo.total, Colors.CYAN, meminfo.used_percent, Colors.RESET },
    );
}
