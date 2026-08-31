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

pub const BufferWriter = struct {
    list: *std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn writeByte(self: *BufferWriter, byte: u8) !void {
        try self.list.append(self.allocator, byte);
    }

    pub fn writeAll(self: *BufferWriter, bytes: []const u8) !void {
        try self.list.appendSlice(self.allocator, bytes);
    }
};

pub fn serialize(allocator: std.mem.Allocator, value: anytype) ![]u8 {
    var buffer: std.ArrayList(u8) = .empty;
    errdefer buffer.deinit(allocator);

    var bw = BufferWriter{
        .list = &buffer,
        .allocator = allocator,
    };
    try serializeStruct(value, &bw, 0);

    return buffer.toOwnedSlice(allocator);
}

fn writeIndent(writer: anytype, depth: usize) !void {
    var i: usize = 0;
    while (i < depth * 2) : (i += 1) {
        try writer.writeByte(' ');
    }
}

fn serializeStruct(s: anytype, writer: anytype, depth: usize) !void {
    const T = @TypeOf(s);
    const fields = std.meta.fields(T);

    inline for (fields) |f| {
        const opts = meta.getFieldOptions(T, f.name);
        if (!opts.skip) {
            const key_name = if (opts.rename) |r| r else f.name;
            const val = @field(s, f.name);
            const field_info = @typeInfo(f.type);

            if (field_info == .@"struct") {
                try writeIndent(writer, depth);
                try writer.writeAll(key_name);
                try writer.writeAll(":\n");
                try serializeStruct(val, writer, depth + 1);
            } else if (field_info == .optional and @typeInfo(field_info.optional.child) == .@"struct") {
                if (val) |unwrapped| {
                    try writeIndent(writer, depth);
                    try writer.writeAll(key_name);
                    try writer.writeAll(":\n");
                    try serializeStruct(unwrapped, writer, depth + 1);
                }
            } else {
                try writeIndent(writer, depth);
                try writer.writeAll(key_name);
                try writer.writeAll(": ");
                try serializeValue(val, writer, depth);
                try writer.writeByte('\n');
            }
        }
    }
}

fn serializeValue(value: anytype, writer: anytype, depth: usize) !void {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    switch (info) {
        .bool => {
            try writer.writeAll(if (value) "true" else "false");
        },
        .int => {
            var buf: [64]u8 = undefined;
            const str = try std.fmt.bufPrint(&buf, "{d}", .{value});
            try writer.writeAll(str);
        },
        .float => {
            var buf: [64]u8 = undefined;
            const str = try std.fmt.bufPrint(&buf, "{d}", .{value});
            try writer.writeAll(str);
        },
        .null => {
            try writer.writeAll("null");
        },
        .optional => {
            if (value) |unwrapped| {
                try serializeValue(unwrapped, writer, depth);
            } else {
                try writer.writeAll("null");
            }
        },
        .@"enum" => {
            try writer.writeAll(@tagName(value));
        },
        .pointer => |ptr_info| {
            if (ptr_info.size == .slice and ptr_info.child == u8) {
                try writer.writeAll(value);
            } else if (ptr_info.size == .slice) {
                try writer.writeByte('\n');
                for (value) |item| {
                    try writeIndent(writer, depth + 1);
                    try writer.writeAll("- ");
                    try serializeValue(item, writer, depth + 1);
                    try writer.writeByte('\n');
                }
            }
        },
        else => @compileError("Unsupported YAML value type: " ++ @typeName(T)),
    }
}
