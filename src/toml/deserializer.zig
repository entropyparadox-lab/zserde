const std = @import("std");
const meta = @import("../meta.zig");

pub const TomlError = error{
    UnexpectedEndOfInput,
    UnexpectedCharacter,
    InvalidNumber,
    MissingRequiredField,
    TypeMismatch,
    OutOfMemory,
};

pub const Deserializer = struct {
    input: []const u8,
    pos: usize = 0,

    pub fn init(input: []const u8) Deserializer {
        return .{ .input = input, .pos = 0 };
    }

    fn skipWhitespaceAndComments(self: *Deserializer) void {
        while (self.pos < self.input.len) {
            const c = self.input[self.pos];
            if (c == ' ' or c == '\t' or c == '\r' or c == '\n') {
                self.pos += 1;
            } else if (c == '#') {
                // skip to end of line
                while (self.pos < self.input.len and self.input[self.pos] != '\n') {
                    self.pos += 1;
                }
            } else {
                break;
            }
        }
    }

    pub fn parseStruct(self: *Deserializer, comptime T: type, allocator: ?std.mem.Allocator) TomlError!T {
        var result: T = undefined;
        const fields = std.meta.fields(T);
        var field_set = std.StaticBitSet(fields.len).initEmpty();

        var current_section: ?[]const u8 = null;

        while (self.pos < self.input.len) {
            self.skipWhitespaceAndComments();
            if (self.pos >= self.input.len) break;

            if (self.input[self.pos] == '[') {
                // Section header [section_name]
                self.pos += 1;
                const start = self.pos;
                while (self.pos < self.input.len and self.input[self.pos] != ']') {
                    self.pos += 1;
                }
                current_section = std.mem.trim(u8, self.input[start..self.pos], " \t");
                if (self.pos < self.input.len and self.input[self.pos] == ']') {
                    self.pos += 1;
                }
                continue;
            }

            // Key = Value
            const key_start = self.pos;
            while (self.pos < self.input.len and self.input[self.pos] != '=' and self.input[self.pos] != '\n') {
                self.pos += 1;
            }
            if (self.pos >= self.input.len or self.input[self.pos] != '=') {
                continue;
            }
            const key = std.mem.trim(u8, self.input[key_start..self.pos], " \t");
            self.pos += 1; // skip '='

            self.skipWhitespaceAndComments();

            if (current_section) |sec| {
                // Match nested struct field (direct or optional)
                inline for (fields, 0..) |f, i| {
                    const target_sec = meta.getFieldName(T, f);
                    const field_info = @typeInfo(f.type);
                    const is_direct_struct = (field_info == .@"struct");
                    const is_optional_struct = (field_info == .optional and @typeInfo(field_info.optional.child) == .@"struct");

                    if ((is_direct_struct or is_optional_struct) and std.mem.eql(u8, sec, target_sec)) {
                        const ChildType = if (is_direct_struct) f.type else field_info.optional.child;
                        if (!field_set.isSet(i)) {
                            @field(result, f.name) = std.mem.zeroes(ChildType);
                            field_set.set(i);
                        }
                        const child_fields = std.meta.fields(ChildType);
                        inline for (child_fields) |cf| {
                            const c_name = meta.getFieldName(ChildType, cf);
                            if (std.mem.eql(u8, key, c_name)) {
                                if (is_direct_struct) {
                                    @field(@field(result, f.name), cf.name) = try self.parseValue(cf.type, allocator);
                                } else {
                                    var curr = @field(result, f.name) orelse std.mem.zeroes(ChildType);
                                    @field(curr, cf.name) = try self.parseValue(cf.type, allocator);
                                    @field(result, f.name) = curr;
                                }
                            }
                        }
                    }
                }
            } else {
                // Top-level key
                inline for (fields, 0..) |f, i| {
                    const target_name = meta.getFieldName(T, f);
                    const field_info = @typeInfo(f.type);
                    const is_struct = (field_info == .@"struct" or (field_info == .optional and @typeInfo(field_info.optional.child) == .@"struct"));

                    if (!is_struct and std.mem.eql(u8, key, target_name)) {
                        @field(result, f.name) = try self.parseValue(f.type, allocator);
                        field_set.set(i);
                    }
                }
            }
        }

        // Fill missing fields (default values or optionals or skipped)
        inline for (fields, 0..) |f, i| {
            if (!field_set.isSet(i)) {
                const opts = meta.getFieldOptions(T, f.name);
                if (opts.skip) {
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
                    return TomlError.MissingRequiredField;
                }
            }
        }

        return result;
    }

    pub fn parseValue(self: *Deserializer, comptime T: type, allocator: ?std.mem.Allocator) TomlError!T {
        self.skipWhitespaceAndComments();
        const info = @typeInfo(T);

        switch (info) {
            .bool => {
                if (std.mem.startsWith(u8, self.input[self.pos..], "true")) {
                    self.pos += 4;
                    return true;
                } else if (std.mem.startsWith(u8, self.input[self.pos..], "false")) {
                    self.pos += 5;
                    return false;
                }
                return TomlError.TypeMismatch;
            },
            .int => {
                const start = self.pos;
                if (self.pos < self.input.len and self.input[self.pos] == '-') self.pos += 1;
                while (self.pos < self.input.len and self.input[self.pos] >= '0' and self.input[self.pos] <= '9') {
                    self.pos += 1;
                }
                const num_str = self.input[start..self.pos];
                return std.fmt.parseInt(T, num_str, 10) catch return TomlError.InvalidNumber;
            },
            .float => {
                const start = self.pos;
                while (self.pos < self.input.len and ((self.input[self.pos] >= '0' and self.input[self.pos] <= '9') or self.input[self.pos] == '.' or self.input[self.pos] == '-')) {
                    self.pos += 1;
                }
                const num_str = self.input[start..self.pos];
                return std.fmt.parseFloat(T, num_str) catch return TomlError.InvalidNumber;
            },
            .optional => |opt| {
                return try self.parseValue(opt.child, allocator);
            },
            .pointer => |ptr_info| {
                if (ptr_info.size == .slice and ptr_info.child == u8) {
                    // String literal "..."
                    if (self.pos < self.input.len and self.input[self.pos] == '"') {
                        self.pos += 1;
                        const start = self.pos;
                        while (self.pos < self.input.len and self.input[self.pos] != '"') {
                            self.pos += 1;
                        }
                        const slice = self.input[start..self.pos];
                        if (self.pos < self.input.len and self.input[self.pos] == '"') {
                            self.pos += 1;
                        }
                        if (allocator) |alloc| {
                            return try alloc.dupe(u8, slice);
                        }
                        return slice;
                    }
                    return TomlError.TypeMismatch;
                }
                return TomlError.TypeMismatch;
            },
            else => @compileError("Unsupported type for TOML value: " ++ @typeName(T)),
        }
    }
};

pub fn deserialize(comptime T: type, allocator: std.mem.Allocator, input: []const u8) TomlError!T {
    var de = Deserializer.init(input);
    return de.parseStruct(T, allocator);
}

pub fn deserializeBorrowed(comptime T: type, input: []const u8) TomlError!T {
    var de = Deserializer.init(input);
    return de.parseStruct(T, null);
}
