const std = @import("std");
const Style = @import("style").Style;

pub const DiskInfo = struct {
    disk_size: f64,
    disk_usage: f64,
    disk_usage_percentage: u8,
};

const GB = 1024 * 1024 * 1024;

const struct_statvfs = extern struct {
    f_bsize: c_ulong,
    f_frsize: c_ulong,
    f_blocks: c_ulong,
    f_bfree: c_ulong,
    f_bavail: c_ulong,
    f_files: c_ulong,
    f_ffree: c_ulong,
    f_favail: c_ulong,
    f_fsid: c_ulong,
    f_flag: c_ulong,
    f_namemax: c_ulong,
    __reserved: [6]c_int,
};

extern "c" fn statvfs(path: [*:0]const u8, buf: *struct_statvfs) c_int;

comptime {
    // Mirrors the LP64 glibc/musl `struct statvfs`. On any other ABI the layout is
    // different, and passing this (too small) struct to statvfs(3) would corrupt the
    // stack, so refuse to compile instead.
    if (@sizeOf(struct_statvfs) != 112)
        @compileError("struct_statvfs does not match the LP64 statvfs ABI; 32-bit targets need their own layout");
}

/// Usage of the filesystem mounted at `disk_path`.
pub fn stat(allocator: std.mem.Allocator, disk_path: []const u8) !DiskInfo {
    var vfs: struct_statvfs = undefined;

    const path_z = try allocator.dupeSentinel(u8, disk_path, 0);
    defer allocator.free(path_z);

    if (statvfs(path_z, &vfs) != 0) return error.StatvfsFailed;

    const block_size = vfs.f_bsize;
    const total_size = vfs.f_blocks * block_size;
    const used_size = total_size - (vfs.f_bavail * block_size);
    const used_size_percentage = if (total_size > 0) (used_size * 100) / total_size else 0;

    return .{
        .disk_size = @as(f64, @floatFromInt(total_size)) / GB,
        .disk_usage = @as(f64, @floatFromInt(used_size)) / GB,
        .disk_usage_percentage = @as(u8, @intCast(used_size_percentage)),
    };
}

pub fn format(allocator: std.mem.Allocator, disk: DiskInfo, style: Style) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{d:.2} GiB / {d:.2} GiB ({s}{d}%{s})", .{
        disk.disk_usage,
        disk.disk_size,
        style.accent,
        disk.disk_usage_percentage,
        style.reset,
    });
}

pub fn value(allocator: std.mem.Allocator, io: std.Io, environ_map: std.process.Environ.Map) ![]const u8 {
    _ = io;
    _ = environ_map;

    return format(allocator, try stat(allocator, "/"), .{});
}

// -- Tests --

test "format renders usage over total and the percentage" {
    const disk = DiskInfo{ .disk_size = 906.66, .disk_usage = 599.31, .disk_usage_percentage = 66 };

    const result = try format(std.testing.allocator, disk, .plain);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("599.31 GiB / 906.66 GiB (66%)", result);
}

test "stat reports a usage percentage between 0 and 100" {
    const disk = try stat(std.testing.allocator, "/");
    try std.testing.expect(disk.disk_usage_percentage <= 100);
    try std.testing.expect(disk.disk_size > 0);
}

test "stat fails for a path that does not exist" {
    try std.testing.expectError(error.StatvfsFailed, stat(std.testing.allocator, "/definitely/not/here"));
}
