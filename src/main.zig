const std = @import("std");
const File = std.fs.File;
const Arena = std.heap.ArenaAllocator;

pub const Tokeniser = @import("Tokeniser.zig");

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

    const Bind = struct {
        mods: Mods,
        other: []const u8,
        description: ?[]const u8,
        /// How the modifier keys should be displayed.
        fmt: []const u8,

        pub fn fromString() !Bind {
            // Read in MODIFIERS, KEY, OPTIONAL DESCRIPTION.
            // Have some kind of tokenisation with states.
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
    };

    /// Warnings can be emitted if a line is not documented with #/##.
    /// TODO: In the future we can specify some regex expressions to let
    /// users handle different WM configs.
    fn parseLine(line: []const u8) !?Bind {
        const starting_command = "riverctl map";
        if (!std.mem.startsWith(u8, line, starting_command)) {
            return null;
        }

        return null;
    }

    pub fn deinit(self: Collector) void {
        self.file.close();
        self.arena.deinit();
    }
};

test {
    std.testing.refAllDeclsRecursive(@This());
}
