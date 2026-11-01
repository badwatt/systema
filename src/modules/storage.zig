const std = @import("std");
const Environ = @import("environ").Environ;
const Style = @import("style").Style;

pub const DiskInfo = struct {
    disk_size: f64,
    disk_usage: f64,
    disk_usage_percentage: u8,
};

const GB = 1024 * 1024 * 1024;

/// Linux `struct statfs` on LP64 targets.
const Statfs = extern struct {
    f_type: i64,
    f_bsize: i64,
    f_blocks: u64,
    f_bfree: u64,
    f_bavail: u64,
    f_files: u64,
    f_ffree: u64,
    f_fsid: [2]i32,
    f_namelen: i64,
    f_frsize: i64,
    f_flags: i64,
    f_spare: [4]i64,
};

comptime {
    // 32-bit targets lay statfs out differently; fail to build rather than hand
    // statfs(2) a buffer that is too small.
    if (@sizeOf(Statfs) != 120)
        @compileError("Statfs does not match the LP64 Linux statfs layout");
}

/// Usage of the filesystem mounted at `disk_path`.
///
/// Calls statfs(2) directly instead of libc's statvfs(3). Not linking libc at
/// all is worth ~0.4 ms of startup per run: no dynamic loader, no musl static
/// initialisation. The path is copied to a stack buffer so this needs no
/// allocator either.
pub fn stat(disk_path: []const u8) !DiskInfo {
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    if (disk_path.len >= path_buffer.len) return error.NameTooLong;
    @memcpy(path_buffer[0..disk_path.len], disk_path);
    path_buffer[disk_path.len] = 0;

    var fs: Statfs = undefined;
    const rc = std.os.linux.syscall2(.statfs, @intFromPtr(&path_buffer), @intFromPtr(&fs));
    if (std.os.linux.errno(rc) != .SUCCESS) return error.StatfsFailed;

    const block_size: u64 = @intCast(fs.f_bsize);
    const total_size = fs.f_blocks * block_size;
    const used_size = total_size - (fs.f_bavail * block_size);
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

pub fn value(allocator: std.mem.Allocator, io: std.Io, environ: Environ) ![]const u8 {
    _ = io;
    _ = environ;

    return format(allocator, try stat("/"), .{});
}

// -- Tests --

test "format renders usage over total and the percentage" {
    const disk = DiskInfo{ .disk_size = 906.66, .disk_usage = 599.31, .disk_usage_percentage = 66 };

    const result = try format(std.testing.allocator, disk, .plain);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualStrings("599.31 GiB / 906.66 GiB (66%)", result);
}

test "stat reports a usage percentage between 0 and 100" {
    const disk = try stat("/");

    try std.testing.expect(disk.disk_usage_percentage <= 100);
    try std.testing.expect(disk.disk_size > 0);
}

test "stat fails for a path that does not exist" {
    try std.testing.expectError(error.StatfsFailed, stat("/definitely/not/here"));
}

test "stat rejects a path that does not fit in the buffer" {
    const long_path = @as([std.fs.max_path_bytes]u8, @splat('x'));

    try std.testing.expectError(error.NameTooLong, stat(&long_path));
}
