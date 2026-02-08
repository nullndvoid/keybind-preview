const std = @import("std");
const Allocator = std.mem.Allocator;

const Bind = @import("Bind.zig");
const Tokeniser = @import("Tokeniser.zig");
const CollectionError = @import("Collector.zig").CollectionError;

const BindBuilder = @This();

mods: Bind.Mods = .{},
key: ?[]const u8 = null,
description: ?[]const u8 = null,
command: ?[]const u8 = null,

pub fn init() BindBuilder {
    return .{};
}

pub fn addModifier(self: *BindBuilder, tt: Tokeniser.Token.TokenType) void {
    switch (tt) {
        .super => self.mods.Super = true,
        .alt => self.mods.Alt = true,
        .ctrl => self.mods.Ctrl = true,
        .shift => self.mods.Shift = true,
        .none => self.mods.None = true,
        .mod3 => self.mods.Mod3 = true,
        .mod5 => self.mods.Mod5 = true,
        else => return,
    }
}

pub fn addKey(self: *BindBuilder, keysym: []const u8) void {
    self.key = keysym;
}

/// Note this is optional.
pub fn addDescription(self: *BindBuilder, desc: []const u8) void {
    self.description = desc;
}

pub fn addCommand(self: *BindBuilder, cmd: []const u8) void {
    self.command = cmd;
}

/// Free the allocated Bind with deinit.
pub fn build(self: *BindBuilder, alloc: Allocator) CollectionError!Bind {
    // Maybe I should log a warning or error but this suffices.
    if (!self.mods.validate() or self.key == null or self.mods.toInt() == 0) return error.InvalidBind;

    // Build the format string.
    const fmt = try self.buildFormat(alloc);

    return Bind{
        .mods = self.mods,
        .key = self.key.?,
        .description = self.description,
        .fmt = fmt,
        .command = self.command.?,
    };
}

fn buildFormat(self: *BindBuilder, alloc: Allocator) CollectionError![]const u8 {
    var parts = std.ArrayList([]const u8).empty;
    defer parts.deinit(alloc);

    if (self.mods.Super) try parts.append(alloc, "Super");
    if (self.mods.Ctrl) try parts.append(alloc, "Ctrl");
    if (self.mods.Alt) try parts.append(alloc, "Alt");
    if (self.mods.Shift) try parts.append(alloc, "Shift");
    if (self.mods.Mod3) try parts.append(alloc, "Mod3");
    if (self.mods.Mod5) try parts.append(alloc, "Mod5");

    try parts.append(alloc, self.key.?);

    const joined = try std.mem.join(alloc, "+", parts.items);

    if (self.description) |desc| {
        const result = try std.fmt.allocPrint(alloc, "{s} ({s})", .{ joined, desc });
        alloc.free(joined);
        return result;
    }

    return joined;
}
