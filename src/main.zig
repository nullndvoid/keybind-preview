const std = @import("std");
const keybind = @import("keybind");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();

    const alloc = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(alloc);

    var collector = try keybind.Collector.init("/home/jacob/.config/river/init", &arena);
    defer collector.deinit();

    const stdout = std.fs.File.stdout();
    var line_buf: [256]u8 = undefined;
    var writer = stdout.writer(&line_buf);

    if (collector.binds) |binds| {
        for (binds) |b| {
            try writer.interface.print("{f}\n", .{b});
        }

        try writer.interface.flush();
    } else {
        std.log.warn("No binds found in input.", .{});
    }
}
