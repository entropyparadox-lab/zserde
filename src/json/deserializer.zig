const std = @import("std");
const meta = @import("../meta.zig");

pub const DeserializeError = error{
    UnexpectedCharacter,
    UnexpectedEndOfInput,
    InvalidNumber,
    InvalidEscape,
    MissingRequiredField,
    UnknownField,
    TypeMismatch,
    OutOfMemory,
};

pub const Deserializer = struct {
    input: []const u8,
    pos: usize = 0,

    pub fn init(input: []const u8) Deserializer {
        return .{ .input = input, .pos = 0 };
    }

    fn peek(self: *Deserializer) ?u8 {
        self.skipWhitespace();
        if (self.pos >= self.input.len) return null;
        return self.input[self.pos];
    }

    pub fn skipWhitespace(self: *Deserializer) void {
        // 1. SIMD accelerated path for 16-byte chunks
        const Vec16 = @Vector(16, u8);
        const space_v: Vec16 = @splat(' ');
        const tab_v: Vec16 = @splat('\t');
        const nl_v: Vec16 = @splat('\n');
        const cr_v: Vec16 = @splat('\r');

        while (self.pos + 16 <= self.input.len) {
            const chunk: Vec16 = self.input[self.pos..][0..16].*;
            const is_space = chunk == space_v;
            const is_tab = chunk == tab_v;
            const is_nl = chunk == nl_v;
            const is_cr = chunk == cr_v;
            const is_ws = is_space | is_tab | is_nl | is_cr;

            if (@reduce(.And, is_ws)) {
                self.pos += 16;
            } else {
                var i: usize = 0;
                while (i < 16) : (i += 1) {
                    switch (self.input[self.pos + i]) {
                        ' ', '\t', '\n', '\r' => {},
                        else => {
                            self.pos += i;
                            return;
                        },
                    }
                }
                self.pos += 16;
                return;
            }
        }

        // 2. Scalar fallback for tail bytes
        while (self.pos < self.input.len) {
            switch (self.input[self.pos]) {
                ' ', '\t', '\n', '\r' => self.pos += 1,
                else => break,
            }
        }
    }

    fn nextChar(self: *Deserializer) ?u8 {
        self.skipWhitespace();
        if (self.pos >= self.input.len) return null;
        const c = self.input[self.pos];
        self.pos += 1;
        return c;
    }

    fn expectChar(self: *Deserializer, expected: u8) !void {
        const c = self.nextChar() orelse return DeserializeError.UnexpectedEndOfInput;
        if (c != expected) return DeserializeError.UnexpectedCharacter;
    }

    pub fn parseStringBorrowed(self: *Deserializer) ![]const u8 {
        try self.expectChar('"');
        const start = self.pos;

        // SIMD accelerated search for quotes and escapes
        const Vec16 = @Vector(16, u8);
        const quote_v: Vec16 = @splat('"');
        const esc_v: Vec16 = @splat('\\');

        while (self.pos + 16 <= self.input.len) {
            const chunk: Vec16 = self.input[self.pos..][0..16].*;
            const is_quote = chunk == quote_v;
            const is_esc = chunk == esc_v;
            const has_special = is_quote | is_esc;

            if (@reduce(.Or, has_special)) {
                break;
            }
            self.pos += 16;
        }

        while (self.pos < self.input.len) {
            const c = self.input[self.pos];
            if (c == '\\') {
                self.pos += 2; // skip escape
            } else if (c == '"') {
                const slice = self.input[start..self.pos];
                self.pos += 1;
                return slice;
            } else {
                self.pos += 1;
            }
        }
        return DeserializeError.UnexpectedEndOfInput;
    }

    pub fn parseBool(self: *Deserializer) !bool {
        self.skipWhitespace();
        if (std.mem.startsWith(u8, self.input[self.pos..], "true")) {
            self.pos += 4;
            return true;
        } else if (std.mem.startsWith(u8, self.input[self.pos..], "false")) {
            self.pos += 5;
            return false;
        }
        return DeserializeError.TypeMismatch;
    }

    pub fn parseNumber(self: *Deserializer, comptime T: type) !T {
        self.skipWhitespace();
        const start = self.pos;
        if (self.pos < self.input.len and self.input[self.pos] == '-') {
            self.pos += 1;
        }
        while (self.pos < self.input.len) {
            const c = self.input[self.pos];
            if ((c >= '0' and c <= '9') or c == '.' or c == 'e' or c == 'E' or c == '+' or c == '-') {
                self.pos += 1;
            } else {
                break;
            }
        }
        const num_str = self.input[start..self.pos];
        if (num_str.len == 0) return DeserializeError.InvalidNumber;

        const info = @typeInfo(T);
        switch (info) {
            .int => {
                return std.fmt.parseInt(T, num_str, 10) catch return DeserializeError.InvalidNumber;
            },
            .float => {
                return std.fmt.parseFloat(T, num_str) catch return DeserializeError.InvalidNumber;
            },
            else => @compileError("parseNumber only accepts int or float"),
        }
    }

    pub fn parseValue(self: *Deserializer, comptime T: type, allocator: ?std.mem.Allocator) !T {
        self.skipWhitespace();
        const info = @typeInfo(T);

        switch (info) {
            .bool => return self.parseBool(),
            .int => return self.parseNumber(T),
            .float => return self.parseNumber(T),
            .optional => |opt| {
                if (std.mem.startsWith(u8, self.input[self.pos..], "null")) {
                    self.pos += 4;
                    return null;
                }
                return try self.parseValue(opt.child, allocator);
            },
            .@"enum" => {
                const name = try self.parseStringBorrowed();
                return std.meta.stringToEnum(T, name) orelse DeserializeError.TypeMismatch;
            },
            .pointer => |ptr_info| {
                switch (ptr_info.size) {
                    .slice => {
                        if (ptr_info.child == u8) {
                            const borrowed = try self.parseStringBorrowed();
                            if (allocator) |alloc| {
                                return try alloc.dupe(u8, borrowed);
                            }
                            return borrowed;
                        } else {
                            // Array of elements
                            const alloc = allocator orelse return DeserializeError.OutOfMemory;
                            try self.expectChar('[');
                            var list: std.ArrayList(ptr_info.child) = .empty;
                            errdefer list.deinit(alloc);

                            self.skipWhitespace();
                            if (self.peek() == ']') {
                                self.pos += 1;
                                return list.toOwnedSlice(alloc);
                            }

                            while (true) {
                                const item = try self.parseValue(ptr_info.child, alloc);
                                try list.append(alloc, item);

                                self.skipWhitespace();
                                const c = self.nextChar() orelse return DeserializeError.UnexpectedEndOfInput;
                                if (c == ']') break;
                                if (c != ',') return DeserializeError.UnexpectedCharacter;
                            }
                            return list.toOwnedSlice(alloc);
                        }
                    },
                    else => @compileError("Unsupported pointer type in deserialization: " ++ @typeName(T)),
                }
            },
            .array => |arr_info| {
                try self.expectChar('[');
                var arr: [arr_info.len]arr_info.child = undefined;
                var idx: usize = 0;

                while (idx < arr_info.len) : (idx += 1) {
                    arr[idx] = try self.parseValue(arr_info.child, allocator);
                    self.skipWhitespace();
                    if (idx + 1 < arr_info.len) {
                        try self.expectChar(',');
                    }
                }
                try self.expectChar(']');
                return arr;
            },
            .@"struct" => {
                return self.parseStruct(T, allocator);
            },
            else => @compileError("Unsupported type for deserialization: " ++ @typeName(T)),
        }
    }

    fn parseStruct(self: *Deserializer, comptime T: type, allocator: ?std.mem.Allocator) !T {
        try self.expectChar('{');
        var result: T = undefined;
        var field_set = std.StaticBitSet(std.meta.fields(T).len).initEmpty();

        const fields = std.meta.fields(T);

        self.skipWhitespace();
        if (self.peek() == '}') {
            self.pos += 1;
            // Check required fields
            inline for (fields, 0..) |f, i| {
                const field_opts = meta.getFieldOptions(T, f.name);
                if (field_opts.skip) {
                    if (f.default_value_ptr) |def| {
                        const typed_def: *const f.type = @ptrCast(@alignCast(def));
                        @field(result, f.name) = typed_def.*;
                    } else if (@typeInfo(f.type) == .optional) {
                        @field(result, f.name) = null;
                    } else {
                        @field(result, f.name) = std.mem.zeroes(f.type);
                    }
                } else if (@typeInfo(f.type) == .optional) {
                    @field(result, f.name) = null;
                } else if (f.default_value_ptr) |def| {
                    const typed_def: *const f.type = @ptrCast(@alignCast(def));
                    @field(result, f.name) = typed_def.*;
                } else {
                    return DeserializeError.MissingRequiredField;
                }
                _ = i;
            }
            return result;
        }

        while (true) {
            const key = try self.parseStringBorrowed();
            try self.expectChar(':');

            var matched = false;
            inline for (fields, 0..) |f, i| {
                const target_name = meta.getFieldName(T, f);
                const field_opts = meta.getFieldOptions(T, f.name);
                if (!field_opts.skip and std.mem.eql(u8, key, target_name)) {
                    @field(result, f.name) = try self.parseValue(f.type, allocator);
                    field_set.set(i);
                    matched = true;
                    break;
                }
            }

            if (!matched) {
                try self.skipArbitraryValue();
            }

            self.skipWhitespace();
            const next = self.nextChar() orelse return DeserializeError.UnexpectedEndOfInput;
            if (next == '}') break;
            if (next != ',') return DeserializeError.UnexpectedCharacter;
        }

        // Fill missing fields (optionals, defaults, or skipped)
        inline for (fields, 0..) |f, i| {
            if (!field_set.isSet(i)) {
                const field_opts = meta.getFieldOptions(T, f.name);
                if (field_opts.skip) {
                    if (f.default_value_ptr) |def| {
                        const typed_def: *const f.type = @ptrCast(@alignCast(def));
                        @field(result, f.name) = typed_def.*;
                    } else if (@typeInfo(f.type) == .optional) {
                        @field(result, f.name) = null;
                    } else {
                        @field(result, f.name) = std.mem.zeroes(f.type);
                    }
                } else if (@typeInfo(f.type) == .optional) {
                    @field(result, f.name) = null;
                } else if (f.default_value_ptr) |def| {
                    const typed_def: *const f.type = @ptrCast(@alignCast(def));
                    @field(result, f.name) = typed_def.*;
                } else {
                    return DeserializeError.MissingRequiredField;
                }
            }
        }

        return result;
    }

    fn skipArbitraryValue(self: *Deserializer) !void {
        self.skipWhitespace();
        const c = self.peek() orelse return DeserializeError.UnexpectedEndOfInput;
        if (c == '"') {
            _ = try self.parseStringBorrowed();
        } else if (c == '{') {
            self.pos += 1;
            var depth: usize = 1;
            while (depth > 0 and self.pos < self.input.len) {
                const ch = self.input[self.pos];
                if (ch == '{') depth += 1;
                if (ch == '}') depth -= 1;
                if (ch == '"') {
                    _ = try self.parseStringBorrowed();
                    continue;
                }
                self.pos += 1;
            }
        } else if (c == '[') {
            self.pos += 1;
            var depth: usize = 1;
            while (depth > 0 and self.pos < self.input.len) {
                const ch = self.input[self.pos];
                if (ch == '[') depth += 1;
                if (ch == ']') depth -= 1;
                if (ch == '"') {
                    _ = try self.parseStringBorrowed();
                    continue;
                }
                self.pos += 1;
            }
        } else {
            // Primitive value (number, bool, null)
            while (self.pos < self.input.len) {
                const ch = self.input[self.pos];
                if (ch == ',' or ch == '}' or ch == ']' or ch == ' ' or ch == '\n' or ch == '\r') {
                    break;
                }
                self.pos += 1;
            }
        }
    }
};

pub fn unescapeInPlace(buf: []u8) ![]u8 {
    var read_idx: usize = 0;
    var write_idx: usize = 0;

    while (read_idx < buf.len) {
        if (buf[read_idx] == '\\') {
            read_idx += 1;
            if (read_idx >= buf.len) return DeserializeError.InvalidEscape;
            switch (buf[read_idx]) {
                '"' => buf[write_idx] = '"',
                '\\' => buf[write_idx] = '\\',
                '/' => buf[write_idx] = '/',
                'n' => buf[write_idx] = '\n',
                'r' => buf[write_idx] = '\r',
                't' => buf[write_idx] = '\t',
                'b' => buf[write_idx] = 0x08,
                'f' => buf[write_idx] = 0x0C,
                else => return DeserializeError.InvalidEscape,
            }
            write_idx += 1;
            read_idx += 1;
        } else {
            buf[write_idx] = buf[read_idx];
            write_idx += 1;
            read_idx += 1;
        }
    }
    return buf[0..write_idx];
}

pub fn deserialize(comptime T: type, allocator: std.mem.Allocator, input: []const u8) !T {
    var de = Deserializer.init(input);
    return de.parseValue(T, allocator);
}

pub fn deserializeBorrowed(comptime T: type, input: []const u8) !T {
    var de = Deserializer.init(input);
    return de.parseValue(T, null);
}
