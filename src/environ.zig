const std = @import("std");

/// A read-only view over the environment block the kernel already put on our
/// stack.
///
/// `std.process.Environ.Map` copies every variable into a hash map *before*
/// `main` is called: with a 173-variable shell that is ~350 allocations and
/// roughly 0.2 ms of startup, which is more than everything else this program
/// does put together. It only ever asks for five keys, so scanning the raw
/// `KEY=VALUE` entries is both simpler and effectively free.
pub const Environ = struct {
    process: std.process.Environ = .empty,

    pub const empty: Environ = .{};

    /// Returns the value of `key`, or null when it is not set.
    pub fn get(self: Environ, key: []const u8) ?[]const u8 {
        for (self.process.block.view().slice) |entry| {
            const pair = std.mem.span(entry);
            if (pair.len > key.len and pair[key.len] == '=' and std.mem.eql(u8, pair[0..key.len], key)) {
                return pair[key.len + 1 ..];
            }
        }
        return null;
    }

    /// Test helper: builds a real environment block from key/value pairs, so that
    /// `Environ.get` is exercised against the same representation the kernel gives
    /// us instead of a fake.
    pub const Testing = struct {
        arena: std.heap.ArenaAllocator,
        environ: Environ,

        pub fn init(backing: std.mem.Allocator, pairs: []const [2][]const u8) !Testing {
            var arena = std.heap.ArenaAllocator.init(backing);
            errdefer arena.deinit();
            const allocator = arena.allocator();

            const block = try allocator.allocSentinel(?[*:0]const u8, pairs.len, null);
            for (pairs, 0..) |pair, i| {
                const entry = try std.fmt.allocPrintSentinel(allocator, "{s}={s}", .{ pair[0], pair[1] }, 0);
                block[i] = entry.ptr;
            }

            return .{
                .arena = arena,
                .environ = .{ .process = .{ .block = .{ .slice = block } } },
            };
        }

        pub fn deinit(self: *Testing) void {
            self.arena.deinit();
        }
    };
};

// -- Tests --

test "get finds a set key" {
    var testing_env = try Environ.Testing.init(std.testing.allocator, &.{
        .{ "PATH", "/usr/bin" },
        .{ "HOME", "/home/alice" },
    });
    defer testing_env.deinit();

    try std.testing.expectEqualStrings("/home/alice", testing_env.environ.get("HOME").?);
    try std.testing.expectEqualStrings("/usr/bin", testing_env.environ.get("PATH").?);
}

test "get returns null for a missing key" {
    var testing_env = try Environ.Testing.init(std.testing.allocator, &.{.{ "PATH", "/usr/bin" }});
    defer testing_env.deinit();

    try std.testing.expect(testing_env.environ.get("HOME") == null);
}

test "get returns null for the empty environment" {
    try std.testing.expect(Environ.empty.get("HOME") == null);
}

test "get does not match a key that is a prefix of another" {
    var testing_env = try Environ.Testing.init(std.testing.allocator, &.{
        .{ "HOMEDIR", "/nope" },
        .{ "HOME", "/home/alice" },
    });
    defer testing_env.deinit();

    try std.testing.expectEqualStrings("/home/alice", testing_env.environ.get("HOME").?);
}

test "get handles an empty value" {
    var testing_env = try Environ.Testing.init(std.testing.allocator, &.{.{ "TERM", "" }});
    defer testing_env.deinit();

    try std.testing.expectEqualStrings("", testing_env.environ.get("TERM").?);
}
