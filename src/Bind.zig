/// Initialise with `BindBuilder`. Remember to call `deinit` when done.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

const Bind = @This();

mods: Mods,
key: []const u8,
description: ?[]const u8,
/// How the bind should be displayed for debugging purposes etc.
fmt: []const u8,
command: []const u8,

pub fn deinit(self: Bind, alloc: Allocator) void {
    alloc.free(self.fmt);
}

pub const Mods = packed struct(u8) {
    Super: bool = false,
    Alt: bool = false,
    Shift: bool = false,
    Ctrl: bool = false,
    None: bool = false,
    Mod3: bool = false,
    Mod5: bool = false,
    _: bool = false,

    const none = (Mods{ .None = true }).toInt();

    pub fn toInt(self: Mods) u8 {
        return @bitCast(self);
    }

    pub fn validate(mods: Mods) bool {
        if (mods.None)
            return (mods.toInt() | none) == none;

        return true;
    }
};

pub inline fn format(self: *const Bind, writer: *Writer) Writer.Error!void {
    try writer.print("{s}", .{self.fmt});
}
