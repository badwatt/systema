const std = @import("std");
const Colors = @import("style");
const Modules = @import("modules");
const render = @import("render");
const Config = @import("config").Config;
const log = std.log.scoped(.main);
const zon = @import("zon");
const cli = @import("cli");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var config = Config{
        .name = @tagName(zon.name),
        .version = zon.version,
    };

    log.debug("{s}***** DEBUG BUILD: {s}{s}{s}: {s}{s}{s} *****{s}", .{ Colors.RED, Colors.YELLOW, config.name, Colors.RESET, Colors.GREEN, config.version, Colors.RED, Colors.RESET });

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    const allocator = arena.allocator();

    try cli.parse(allocator, io, &config, init.minimal.args);

    const modules = try Modules.init(allocator, io, init.environ_map.*);
    try render.print(allocator, io, init.environ_map.*, &config, modules);
}
