const std = @import("std");

buffer: []const u8,
index: usize = 0,

const Tokeniser = @This();

const Token = struct {
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
};

const State = enum { start, invalid, string_open, wildcard };

/// We assume the input to be a line which began with riverctl map. This
/// start has been stripped off, as well as the terminating newline.
pub fn next(self: *Tokeniser) Token {
    var res = Token{
        .span = .{
            .from = self.index,
            .to = undefined,
        },
    };

    state: switch (State.start) {
        .start => switch (self.buffer[self.index]) {
            0 => {
                if (self.index == self.buffer.len) {
                    return .{
                        .tt = .eof,
                        .span = .{
                            .from = self.index,
                            .to = self.index,
                        },
                    };
                } else {
                    continue :state .invalid;
                }
            },
            else => {
                res.tt = .wildcard;
                continue :state .wildcard;
            },
            ' ', '\t' => {
                self.index += 1;
                res.span.from = self.index;

                continue :state .start;
            },
            '"', '\'' => {
                continue :state .string_open;
            },
            '+' => {
                self.index += 1;
                res.tt = .plus;
            },
        },
        .invalid => {
            self.index += 1;
            switch (self.buffer[self.index]) {
                0 => if (self.index == self.buffer.len) {
                    res.tt = .invalid;
                } else {
                    continue :state .invalid;
                },
                else => continue :state .invalid,
            }
        },
        .string_open => {
            // Scan forward until we hit terminating quote.
            // Delimiter will be stored in res.span.from.
            self.index += 1;

            if (self.buffer[self.index] == self.buffer[res.span.from]) {
                res.tt = .string;
                self.index += 1;
            } else if (self.buffer[self.index] == 0) {
                res.tt = .invalid;
                continue :state .invalid;
            }

            continue :state .string_open;
        },
        .wildcard => {
            self.index += 1;

            switch (self.buffer[self.index]) {
                ' ', '+' => {
                    self.index += 1;
                },
                else => {
                    continue :state .wildcard;
                },
            }

            const text = self.buffer[res.span.from..self.index];

            if (Token.getModifier(text)) |tt| {
                res.tt = tt;
            }
        },
    }

    res.span.to = self.index;

    return res;
}

pub fn init(buffer: []const u8) Tokeniser {
    return Tokeniser{ .buffer = buffer, .index = 0 };
}

test "tokenise inputs" {
    const data = [_]struct { input: []const u8, output: []Token }{
        .{
            .input = "normal Super+Shift spawn \"/bin/bash\"",
            .output = &.{
                .{ .tt = .wildcard, .span = .{ .from = 0, .to = 5 } },
                .{ .tt = .super, .span = .{ .from = 7, .to = 11 } },
                .{ .tt = .plus, .span = .{ .from = 12, .to = 12 } },
            },
        },
    };
    const tokeniser = Tokeniser.init(undefined);

    for (data) |d| {
        tokeniser.buffer = d.input;
        tokeniser.index = 0;
    }
}
