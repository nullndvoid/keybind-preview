const std = @import("std");
const File = std.fs.File;
const Arena = std.heap.ArenaAllocator;

pub fn main() !void {}

pub const Collector = struct {
    file: File,
    arena: Arena,
    /// If no binds are found, perhaps we just print nothing.
    /// TODO: Implement format function.
    binds: ?[]Bind = null,

    const Self = @This();

    pub const CollectionError = error{ NotAFile, NoBinds, InvalidBind } || File.OpenError;

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

    //     Mappings are modal in river. Each mapping is associated with a mode and is only active while in that mode. There are two special modes: "normal" and "locked". The normal mode is the initial mode on startup. The locked mode is automatically entered while the session is locked (e.g. due to a screenlocker). It cannot be entered or exited manually.

    // The following modifiers are available for use in mappings:

    //     Shift
    //     Control
    //     Mod1 (Alt)
    //     Mod3
    //     Mod4 (Super)
    //     Mod5
    //     None

    // Alt and Super are aliases for Mod1 and Mod4 respectively. None allows creating a mapping without modifiers.

    // Keys are specified by their XKB keysym name. See /usr/include/xkbcommon/xkbcommon-keysyms.h for the complete list.

    const Bind = struct {
        mods: Mods,
        other: []const u8,
        description: ?[]const u8,

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

            pub fn fromString(s: []const u8) !Mods {
                var mods: Mods = .{};
                var got_mods = false;

                var split = std.mem.tokenizeScalar(u8, s, '+');
                while (split.next()) |raw_word| {
                    const word = std.mem.trim(u8, raw_word, " ");
                    if (word.len == 0) continue;

                    if (std.mem.eql(u8, word, "Super") or std.mem.eql(u8, word, "Mod4")) {
                        mods.Super = true;
                    } else if (std.mem.eql(u8, word, "Alt") or std.mem.eql(u8, word, "Mod1")) {
                        mods.Alt = true;
                    } else if (std.mem.eql(u8, word, "Shift")) {
                        mods.Shift = true;
                    } else if (std.mem.eql(u8, word, "Control") or std.mem.eql(u8, word, "Ctrl")) {
                        mods.Ctrl = true;
                    } else if (std.mem.eql(u8, word, "None")) {
                        mods.None = true;
                    } else if (std.mem.eql(u8, word, "Mod3")) {
                        mods.Mod3 = true;
                    } else if (std.mem.eql(u8, word, "Mod5")) {
                        mods.Mod5 = true;
                    } else {
                        return error.InvalidBind;
                    }
                    got_mods = true;
                }

                if (!mods.validate() or !got_mods) return error.InvalidBind;

                return mods;
            }

            test "modifier string parsing" {
                const results = [_]struct { input: []const u8, output: Mods }{
                    .{ .input = "Super", .output = Mods{ .Super = true } },
                    .{ .input = "Mod4", .output = Mods{ .Super = true } },
                    .{ .input = "Alt", .output = Mods{ .Alt = true } },
                    .{ .input = "Mod1", .output = Mods{ .Alt = true } },
                    .{ .input = "Shift", .output = Mods{ .Shift = true } },
                    .{ .input = "Control", .output = Mods{ .Ctrl = true } },
                    .{ .input = "Ctrl", .output = Mods{ .Ctrl = true } },
                    .{ .input = "None", .output = Mods{ .None = true } },
                    .{ .input = "Mod3", .output = Mods{ .Mod3 = true } },
                    .{ .input = "Mod5", .output = Mods{ .Mod5 = true } },
                    .{ .input = "Super+Shift", .output = Mods{ .Super = true, .Shift = true } },
                    .{ .input = "Super+Alt+Control", .output = Mods{ .Super = true, .Alt = true, .Ctrl = true } },
                    .{ .input = "Super + Shift", .output = Mods{ .Super = true, .Shift = true } },
                };

                for (results) |res| {
                    try std.testing.expectEqual(res.output, try Mods.fromString(res.input));
                }

                try std.testing.expectError(error.InvalidBind, Mods.fromString("Invalid"));
                try std.testing.expectError(error.InvalidBind, Mods.fromString("Super+None"));
                try std.testing.expectError(error.InvalidBind, Mods.fromString("Super Shift"));
            }
        };
    };

    /// Warnings can be emitted if a line is not documented with #/##.
    /// TODO: In the future we can specify some regex expressions to let
    /// users handle different WM configs.
    fn parseLine(line: []const u8) !?Bind {
        const starting_command = "riverctl map";
        if (!std.mem.startsWith(u8, line, starting_command)) {
            return null;
        }

        // Consume the next word for the mode, we don't currently care.
        var split = std.mem.splitAny(u8, line[starting_command.len - 1 ..], " ");
        _ = split.next();

        // const mod = split.next() catch return error.InvalidBind;
    }

    pub fn deinit(self: Collector) void {
        self.file.close();
        self.arena.deinit();
    }
};

test {
    std.testing.refAllDeclsRecursive(@This());
}
