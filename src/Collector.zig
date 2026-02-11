const std = @import("std");
const File = std.fs.File;
const Arena = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

const Collector = @This();
const Tokeniser = @import("Tokeniser.zig");
const Bind = @import("Bind.zig");
const BindBuilder = @import("BindBuilder.zig");

arena: *Arena,
/// If no binds are found, perhaps we just print nothing.
/// TODO: Implement format function.
binds: ?[]Bind = null,

const Self = @This();

pub const CollectionError = error{ NotAFile, NoBinds, InvalidBind } || File.OpenError || Allocator.Error;

pub fn init(path: []const u8, arena: *Arena) CollectionError!Self {
    const cwd = std.fs.cwd();

    const file = try cwd.openFile(path, .{ .mode = .read_only });
    defer file.close();

    const stat = try file.stat();
    if (stat.kind != .file) {
        return error.NotAFile;
    }

    // Lines aren't likely to exceed 512 bytes but this could fail (StreamTooLong),
    // perhaps use the Arena?
    var reader_buf: [512]u8 = undefined;
    var rdr = file.reader(&reader_buf);

    var binds = std.ArrayList(Bind).empty;
    defer binds.deinit(arena.allocator());

    var collector = Self{ .arena = arena, .binds = null };

    while (true) {
        const line = rdr.interface.takeDelimiterInclusive('\n') catch break;
        const bind = collector.parseLine(line) catch |e| {
            std.log.err("{any} \"{s}\"", .{ e, line });
            continue;
        } orelse continue;

        try binds.append(arena.allocator(), bind);
    }

    if (binds.items.len > 0)
        collector.binds = try binds.toOwnedSlice(arena.allocator());

    return collector;
}

/// Warnings can be emitted if a line is not documented with #/##.
fn parseLine(self: *Collector, line: []const u8) !?Bind {
    var trimmed_line = std.mem.trimStart(u8, line, " \t");

    // Support both "riverctl map" and "riverctl map-pointer"
    const prefixes = [_][]const u8{ "riverctl map-pointer", "riverctl map" };

    var found = false;
    for (prefixes) |prefix| {
        if (std.mem.startsWith(u8, trimmed_line, prefix)) {
            trimmed_line = trimmed_line[prefix.len..];
            found = true;
            break;
        }
    }

    if (!found) return null;

    trimmed_line = std.mem.trimEnd(u8, trimmed_line, " \n\r");

    var tokeniser = Tokeniser.init(trimmed_line);

    // The pattern is as follows. wildcard for mode, modifiers separated
    // by plus, wildcard (key), string (command) OR wildcards then optional
    // description.
    //
    // Log a warning for missing descriptions and error for invalid binds.
    //
    // We expect at least 4 tokens or something is not right.
    const toks = try tokeniser.collectAllAlloc(self.arena.allocator());

    std.debug.assert(toks.len >= 4);

    var bind_builder = BindBuilder.init();

    const mode = toks[0];
    if (mode.tt != .wildcard)
        return error.InvalidBind;

    var i: usize = 1;
    var need_mod = true;

    // Collect modifier tokens or plus. We want mod, plus, mod, plus, mod.
    while (i < toks.len) : ({
        i += 1;
    }) {
        const tok = toks[i];

        if (need_mod and !tok.isModifier()) {
            // Maybe log an error? We can just print invalid line after rejection.
            return error.InvalidBind;
        } else if (tok.isModifier()) {
            need_mod = false;
            bind_builder.addModifier(tok.tt);
        } else if (tok.isPlus()) {
            need_mod = true;
        } else {
            break; // Done getting modifiers. i should point to the keysym.
        }
    }

    const keysym = toks[i];
    if (keysym.tt != .wildcard)
        return error.InvalidBind;

    bind_builder.addKey(tokeniser.source(&keysym));

    // Take tokens and concat sources until we hit description or end of input.
    // Bind must be invalid, where's the command?
    if (i + 1 >= toks.len)
        return error.InvalidBind;

    const rest = toks[i + 1 ..];
    var command_part = std.ArrayList([]const u8).empty;
    defer command_part.deinit(self.arena.allocator());

    var desc_index: ?usize = null;
    for (rest, 0..) |*tok, j| {
        if (tok.tt == .string or tok.tt == .wildcard) {
            try command_part.append(self.arena.allocator(), tokeniser.source(tok));
        } else {
            desc_index = j;
            break;
        }
    }

    const command = try std.mem.join(
        self.arena.allocator(),
        " ",
        command_part.items,
    );
    bind_builder.addCommand(command);

    // This should be the final token and it should be the description.
    if (desc_index) |idx| {
        const description = rest[idx];

        if (description.tt != .description) {
            // Log no description?
            std.log.info("No description for line: \"{s}\". Using command instead!", .{tokeniser.buffer});
            bind_builder.addDescription(command);
        } else bind_builder.addDescription(tokeniser.source(&description));
    }

    return try bind_builder.build(self.arena.allocator());
}

pub fn deinit(self: Collector) void {
    self.arena.deinit();
}

test "parseLine" {
    const line = "riverctl map normal Super+Ctrl+Alt E exit ## A description.";

    var arena = Arena.init(std.testing.allocator);
    var collector = Collector{
        .arena = &arena,
    };
    defer collector.deinit();

    const l = (try collector.parseLine(line)).?;

    try std.testing.expectEqualStrings("E", l.key);
    try std.testing.expectEqualStrings("exit", l.command);
    try std.testing.expectEqualStrings("A description.", l.description.?);
    try std.testing.expectEqual(Bind.Mods{
        .Super = true,
        .Ctrl = true,
        .Alt = true,
    }, l.mods);
    try std.testing.expectEqualStrings("Super+Ctrl+Alt+E (A description.)", l.fmt);
}

test "parseLine with Control modifier" {
    const line = "riverctl map normal Super+Alt+Control H snap left ## Snap window left";

    var arena = Arena.init(std.testing.allocator);
    var collector = Collector{
        .arena = &arena,
    };
    defer collector.deinit();

    const l = (try collector.parseLine(line)).?;

    try std.testing.expectEqualStrings("H", l.key);
    try std.testing.expectEqualStrings("snap left", l.command);
    try std.testing.expectEqualStrings("Snap window left", l.description.?);
    try std.testing.expectEqual(Bind.Mods{
        .Super = true,
        .Ctrl = true,
        .Alt = true,
    }, l.mods);
}

test "parseLine with map-pointer" {
    const line = "riverctl map-pointer normal Super BTN_LEFT move-view ## Move view (pointer)";

    var arena = Arena.init(std.testing.allocator);
    var collector = Collector{
        .arena = &arena,
    };
    defer collector.deinit();

    const l = (try collector.parseLine(line)).?;

    try std.testing.expectEqualStrings("BTN_LEFT", l.key);
    try std.testing.expectEqualStrings("move-view", l.command);
    try std.testing.expectEqualStrings("Move view (pointer)", l.description.?);
    try std.testing.expectEqual(Bind.Mods{
        .Super = true,
    }, l.mods);
}

test "parseLine with indentation and bash variable" {
    const line = "    riverctl map normal Super $i set-focused-tags $i ## Focus tag $i";

    var arena = Arena.init(std.testing.allocator);
    var collector = Collector{
        .arena = &arena,
    };
    defer collector.deinit();

    const l = (try collector.parseLine(line)).?;

    try std.testing.expectEqualStrings("$i", l.key);
    try std.testing.expectEqualStrings("set-focused-tags $i", l.command);
    try std.testing.expectEqualStrings("Focus tag $i", l.description.?);
    try std.testing.expectEqual(Bind.Mods{
        .Super = true,
    }, l.mods);
}
