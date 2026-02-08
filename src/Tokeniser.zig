const std = @import("std");
const Allocator = std.mem.Allocator;

buffer: []const u8,
index: usize = 0,

const Tokeniser = @This();

pub const Token = struct {
    tt: TokenType = undefined,
    span: Span = undefined,

    pub const Span = struct {
        from: usize,
        to: usize,
    };

    pub const TokenType = enum {
        plus,
        string,
        /// Unknown token type yet, could be the mode, or a command. If we
        /// have a bunch of wildcards at the end this can be collected into
        /// one `action` or just ignored.
        wildcard,
        super,
        alt,
        shift,
        ctrl,
        none,
        mod3,
        mod5,
        description,
        invalid,
        eof,
    };

    pub fn getModifier(s: []const u8) ?TokenType {
        if (std.mem.eql(u8, s, "Super")) return .super;
        if (std.mem.eql(u8, s, "Alt")) return .alt;
        if (std.mem.eql(u8, s, "Shift")) return .shift;
        if (std.mem.eql(u8, s, "Ctrl")) return .ctrl;
        if (std.mem.eql(u8, s, "None")) return .none;
        if (std.mem.eql(u8, s, "Mod3")) return .mod3;
        if (std.mem.eql(u8, s, "Mod5")) return .mod5;

        return null;
    }

    pub fn isModifier(t: Token) bool {
        return switch (t.tt) {
            .super, .ctrl, .shift, .alt, .none, .mod3, .mod5 => true,
            else => false,
        };
    }

    pub fn isPlus(t: Token) bool {
        return t.tt == .plus;
    }
};

const State = enum { start, invalid, string_open, wildcard, description };

pub fn source(self: *const Tokeniser, t: *const Token) []const u8 {
    return self.buffer[t.span.from..t.span.to];
}

/// We assume the input to be a line which began with riverctl map. This
/// start has been stripped off, as well as the terminating newline.
pub fn next(self: *Tokeniser) Token {
    var res = Token{
        .span = .{
            .from = self.index,
            .to = undefined,
        },
    };

    var state = State.start;
    while (true) {
        if (self.index >= self.buffer.len) {
            switch (state) {
                .wildcard => {
                    res.span.to = self.index - 1;
                    const text = self.buffer[res.span.from..self.index];
                    if (Token.getModifier(text)) |tt| {
                        res.tt = tt;
                    } else {
                        res.tt = .wildcard;
                    }
                    return res;
                },
                .description => {
                    if (res.span.from >= self.index) {
                        res.tt = .eof;
                        res.span.to = self.index;
                        return res;
                    }
                    res.tt = .description;
                    res.span.to = self.index - 1;
                    return res;
                },
                .string_open => {
                    res.tt = .invalid;
                    res.span.to = self.index;
                    return res;
                },
                else => {
                    res.tt = .eof;
                    res.span.from = self.index;
                    res.span.to = self.index;
                    return res;
                },
            }
        }

        const c = self.buffer[self.index];
        switch (state) {
            .start => switch (c) {
                ' ', '\t' => {
                    self.index += 1;
                    res.span.from = self.index;
                    continue;
                },
                '"', '\'' => {
                    state = .string_open;
                    self.index += 1;
                    res.span.from = self.index;
                    continue;
                },
                '+' => {
                    res.tt = .plus;
                    res.span.to = self.index;
                    self.index += 1;
                    return res;
                },
                '#' => {
                    if (self.index + 1 < self.buffer.len and self.buffer[self.index + 1] == '#') {
                        self.index += 2;
                        while (self.index < self.buffer.len and
                            (self.buffer[self.index] == ' ' or self.buffer[self.index] == '\t'))
                        {
                            self.index += 1;
                        }
                        res.span.from = self.index;
                        state = .description;
                        continue;
                    } else {
                        state = .wildcard;
                        continue;
                    }
                },
                else => {
                    state = .wildcard;
                    continue;
                },
            },
            .string_open => {
                const quote = self.buffer[res.span.from - 1];
                if (c == quote) {
                    res.tt = .string;
                    res.span.to = self.index - 1;
                    self.index += 1;
                    return res;
                }
                self.index += 1;
                continue;
            },
            .wildcard => {
                switch (c) {
                    ' ', '\t', '+', '"', '\'' => {
                        res.span.to = self.index - 1;
                        const text = self.buffer[res.span.from..self.index];
                        if (Token.getModifier(text)) |tt| {
                            res.tt = tt;
                        } else {
                            res.tt = .wildcard;
                        }
                        return res;
                    },
                    else => {
                        self.index += 1;
                        continue;
                    },
                }
            },
            .description => {
                self.index += 1;
                continue;
            },
            .invalid => {
                res.tt = .invalid;
                res.span.to = self.index;
                self.index += 1;
                return res;
            },
        }
    }
}

/// Caller should free returned slice when finished.
pub fn collectAllAlloc(self: *Tokeniser, allocator: Allocator) ![]Token {
    // We anticipate at least 4 tokens for valid inputs.
    var output = try std.ArrayList(Token).initCapacity(allocator, 4);

    while (true) {
        const tok = self.next();
        try output.append(allocator, tok);

        if (tok.tt == .eof) break;
    }

    return output.toOwnedSlice(allocator);
}

pub fn init(buffer: []const u8) Tokeniser {
    return Tokeniser{ .buffer = buffer, .index = 0 };
}

test "tokenise inputs" {
    const data = [_]struct { input: []const u8, output: []const Token }{
        .{
            .input = "normal Super+Shift spawn \"/bin/bash\"",
            .output = &.{
                .{ .tt = .wildcard, .span = .{ .from = 0, .to = 5 } },
                .{ .tt = .super, .span = .{ .from = 7, .to = 11 } },
                .{ .tt = .plus, .span = .{ .from = 12, .to = 12 } },
                .{ .tt = .shift, .span = .{ .from = 13, .to = 17 } },
                .{ .tt = .wildcard, .span = .{ .from = 19, .to = 23 } },
                .{ .tt = .string, .span = .{ .from = 26, .to = 34 } },
                .{ .tt = .eof, .span = .{ .from = 36, .to = 36 } },
            },
        },
        .{
            .input = "normal Super+Shift spawn \"/bin/bash\" ## Open a terminal",
            .output = &.{
                .{ .tt = .wildcard, .span = .{ .from = 0, .to = 5 } },
                .{ .tt = .super, .span = .{ .from = 7, .to = 11 } },
                .{ .tt = .plus, .span = .{ .from = 12, .to = 12 } },
                .{ .tt = .shift, .span = .{ .from = 13, .to = 17 } },
                .{ .tt = .wildcard, .span = .{ .from = 19, .to = 23 } },
                .{ .tt = .string, .span = .{ .from = 26, .to = 34 } },
                .{ .tt = .description, .span = .{ .from = 40, .to = 54 } },
                .{ .tt = .eof, .span = .{ .from = 55, .to = 55 } },
            },
        },
        .{
            .input = "normal None Return ## Toggle fullscreen",
            .output = &.{
                .{ .tt = .wildcard, .span = .{ .from = 0, .to = 5 } },
                .{ .tt = .none, .span = .{ .from = 7, .to = 10 } },
                .{ .tt = .wildcard, .span = .{ .from = 12, .to = 17 } },
                .{ .tt = .description, .span = .{ .from = 22, .to = 38 } },
                .{ .tt = .eof, .span = .{ .from = 39, .to = 39 } },
            },
        },
        .{
            .input = "normal None Return ##",
            .output = &.{
                .{ .tt = .wildcard, .span = .{ .from = 0, .to = 5 } },
                .{ .tt = .none, .span = .{ .from = 7, .to = 10 } },
                .{ .tt = .wildcard, .span = .{ .from = 12, .to = 17 } },
                .{ .tt = .eof, .span = .{ .from = 21, .to = 21 } },
            },
        },
    };

    for (data) |d| {
        var tokeniser = Tokeniser.init(d.input);
        for (d.output) |expected| {
            const actual = tokeniser.next();
            try std.testing.expectEqual(expected.tt, actual.tt);
            try std.testing.expectEqual(expected.span.from, actual.span.from);
            try std.testing.expectEqual(expected.span.to, actual.span.to);
        }
    }
}

test {
    std.testing.refAllDeclsRecursive(Tokeniser);
}
