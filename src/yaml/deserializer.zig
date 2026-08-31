const std = @import("std");
const meta = @import("../meta.zig");

pub const YamlError = error{
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

    pub fn parseStruct(self: *Deserializer, comptime T: type, allocator: ?std.mem.Allocator) YamlError!T {
        var result: T = undefined;
        const fields = std.meta.fields(T);
        var field_set = std.StaticBitSet(fields.len).initEmpty();

        var current_parent: ?[]const u8 = null;

        while (self.pos < self.input.len) {
            if (self.pos >= self.input.len) break;

            const line_start = self.pos;
            while (self.pos < self.input.len and self.input[self.pos] != '\n') {
                self.pos += 1;
            }
            const raw_line = self.input[line_start..self.pos];
            if (self.pos < self.input.len and self.input[self.pos] == '\n') {
                self.pos += 1;
            }

            const trimmed_line = std.mem.trim(u8, raw_line, " \t\r");
            if (trimmed_line.len == 0 or trimmed_line[0] == '#') continue;

            const colon_pos = std.mem.indexOfScalar(u8, raw_line, ':') orelse continue;
            const key_raw = raw_line[0..colon_pos];
            const val_raw = std.mem.trim(u8, raw_line[colon_pos + 1 ..], " \t\r");

            // Count leading spaces
            var indent: usize = 0;
            while (indent < key_raw.len and key_raw[indent] == ' ') : (indent += 1) {}
            const key = std.mem.trim(u8, key_raw, " \t\r");

            if (val_raw.len == 0) {
                // Section parent header (e.g. "service:")
                current_parent = key;
                continue;
            }

            if (indent >= 2 and current_parent != null) {
                // Child field of current_parent
                const parent_key = current_parent.?;
                inline for (fields, 0..) |f, i| {
                    const target_parent = meta.getFieldName(T, f);
                    const field_info = @typeInfo(f.type);
                    const is_direct_struct = (field_info == .@"struct");
                    const is_optional_struct = (field_info == .optional and @typeInfo(field_info.optional.child) == .@"struct");

                    if ((is_direct_struct or is_optional_struct) and std.mem.eql(u8, parent_key, target_parent)) {
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
                                    @field(@field(result, f.name), cf.name) = try parsePrimitiveValue(cf.type, val_raw, allocator);
                                } else {
                                    var curr = @field(result, f.name) orelse std.mem.zeroes(ChildType);
                                    @field(curr, cf.name) = try parsePrimitiveValue(cf.type, val_raw, allocator);
                                    @field(result, f.name) = curr;
                                }
                            }
                        }
                    }
                }
            } else {
                current_parent = null;
                // Top-level scalar field
                inline for (fields, 0..) |f, i| {
                    const target_name = meta.getFieldName(T, f);
                    const field_info = @typeInfo(f.type);
                    const is_struct = (field_info == .@"struct" or (field_info == .optional and @typeInfo(field_info.optional.child) == .@"struct"));

                    if (!is_struct and std.mem.eql(u8, key, target_name)) {
                        @field(result, f.name) = try parsePrimitiveValue(f.type, val_raw, allocator);
                        field_set.set(i);
                    }
                }
            }
        }

        // Fill missing fields (default values, optionals, or skipped)
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
                    return YamlError.MissingRequiredField;
                }
            }
        }

        return result;
    }

    fn parsePrimitiveValue(comptime T: type, val_str: []const u8, allocator: ?std.mem.Allocator) YamlError!T {
        const info = @typeInfo(T);
        switch (info) {
            .bool => {
                if (std.mem.eql(u8, val_str, "true") or std.mem.eql(u8, val_str, "yes")) return true;
                if (std.mem.eql(u8, val_str, "false") or std.mem.eql(u8, val_str, "no")) return false;
                return YamlError.TypeMismatch;
            },
            .int => {
                return std.fmt.parseInt(T, val_str, 10) catch return YamlError.InvalidNumber;
            },
            .float => {
                return std.fmt.parseFloat(T, val_str) catch return YamlError.InvalidNumber;
            },
            .optional => |opt| {
                if (std.mem.eql(u8, val_str, "null") or val_str.len == 0) return null;
                return try parsePrimitiveValue(opt.child, val_str, allocator);
            },
            .pointer => |ptr_info| {
                if (ptr_info.size == .slice and ptr_info.child == u8) {
                    const unquoted = std.mem.trim(u8, val_str, "\"\'");
                    if (allocator) |alloc| {
                        return try alloc.dupe(u8, unquoted);
                    }
                    return unquoted;
                }
                return YamlError.TypeMismatch;
            },
            .@"enum" => {
                return std.meta.stringToEnum(T, val_str) orelse YamlError.TypeMismatch;
            },
            else => @compileError("Unsupported type for YAML primitive: " ++ @typeName(T)),
        }
    }
};

pub fn deserialize(comptime T: type, allocator: std.mem.Allocator, input: []const u8) YamlError!T {
    var de = Deserializer.init(input);
    return de.parseStruct(T, allocator);
}

pub fn deserializeBorrowed(comptime T: type, input: []const u8) YamlError!T {
    var de = Deserializer.init(input);
    return de.parseStruct(T, null);
}
