const std = @import("std");
const keybind = @import("keybind");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();

    const alloc = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(alloc);

    var collector = try keybind.Collector.init("/home/jacob/.config/river/init", &arena);
    defer collector.deinit();
}
