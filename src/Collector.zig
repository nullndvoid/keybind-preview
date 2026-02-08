const std = @import("std");
const File = std.fs.File;
const Arena = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

const Collector = @This();
const Tokeniser = @import("Tokeniser.zig");

file: File,
arena: Arena,
/// If no binds are found, perhaps we just print nothing.
/// TODO: Implement format function.
binds: ?[]Bind = null,

const Self = @This();

pub const CollectionError = error{ NotAFile, NoBinds, InvalidBind } || File.OpenError || Allocator.Error;

pub fn init(path: []const u8, arena: Arena) CollectionError!Self {
    const cwd = std.fs.cwd();

    const file = try cwd.openFile(path, .{ .mode = .read_only });
    const stat = try file.stat();

    if (stat.kind != .file) {
        return error.NotAFile;
    }

    // TODO: Parse everything on init and let caller clean everything up later.
    //       Single function that can fail might be cleaner.

    return Self{
        .file = file,
        .arena = arena,
    };
}

const BindBuilder = struct {
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
        if (!self.mods.validate() or self.key == null or self.mods.int() == 0) return error.InvalidBind;

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
        if (self.mods.None) try parts.append(alloc, "None");
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
};

/// Initialise with `BindBuilder`. Remember to call `deinit` when done.
const Bind = struct {
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

        const none = (Mods{ .None = true }).int();

        fn int(self: Mods) u8 {
            return @bitCast(self);
        }

        pub fn validate(mods: Mods) bool {
            if (mods.None)
                return (mods.int() | none) == none;

            return true;
        }
    };

    pub inline fn format(self: *Bind, writer: *Writer) Writer.Error!void {
        try writer.print("{s}", .{self.fmt});
    }
};

/// Warnings can be emitted if a line is not documented with #/##.
fn parseLine(self: *Collector, line: []const u8) !?Bind {
    const starting_command = "riverctl map";
    if (!std.mem.startsWith(u8, line, starting_command)) {
        return null;
    }

    var trimmed_line = std.mem.trim(u8, line, starting_command);
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
    var command_part = std.ArrayList(u8).empty;
    defer command_part.deinit(self.arena.allocator());

    var desc_index: ?usize = null;
    for (rest, 0..) |*tok, j| {
        if (tok.tt == .string or tok.tt == .wildcard) {
            try command_part.appendSlice(self.arena.allocator(), tokeniser.source(tok));
        } else {
            desc_index = j;
            break;
        }
    }

    // This should be the final token and it should be the description.
    if (desc_index) |idx| {
        const description = rest[idx];

        if (description.tt != .description)
            unreachable;

        bind_builder.addDescription(tokeniser.source(&description));
    }

    const command = try command_part.toOwnedSlice(self.arena.allocator());
    bind_builder.addCommand(command);

    return try bind_builder.build(self.arena.allocator());
}

pub fn deinit(self: Collector) void {
    if (!@import("builtin").is_test)
        self.file.close();
    self.arena.deinit();
}

test "parseLine" {
    const line = "riverctl map normal Super+Ctrl+Alt E exit ## A description.";

    const arena = Arena.init(std.testing.allocator);

    var collector = Collector{
        .arena = arena,
        .file = undefined,
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
