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
    try serializeStruct(value, &bw);

    return buffer.toOwnedSlice(allocator);
}

fn serializeStruct(s: anytype, writer: anytype) !void {
    const T = @TypeOf(s);
    const fields = std.meta.fields(T);

    // 1. First pass: write simple scalar fields
    inline for (fields) |f| {
        const opts = meta.getFieldOptions(T, f.name);
        if (!opts.skip and @typeInfo(f.type) != .@"struct") {
            const key_name = meta.getFieldName(T, f);
            const val = @field(s, f.name);

            try writer.writeAll(key_name);
            try writer.writeAll(" = ");
            try serializeValue(val, writer);
            try writer.writeByte('\n');
        }
    }

    // 2. Second pass: write nested sections [section]
    inline for (fields) |f| {
        const opts = meta.getFieldOptions(T, f.name);
        if (!opts.skip and @typeInfo(f.type) == .@"struct") {
            const section_name = meta.getFieldName(T, f);
            const val = @field(s, f.name);

            try writer.writeByte('\n');
            try writer.writeByte('[');
            try writer.writeAll(section_name);
            try writer.writeAll("]\n");

            const child_fields = std.meta.fields(f.type);
            inline for (child_fields) |cf| {
                const copts = meta.getFieldOptions(f.type, cf.name);
                if (!copts.skip) {
                    const ckey = meta.getFieldName(f.type, cf);
                    const cval = @field(val, cf.name);
                    try writer.writeAll(ckey);
                    try writer.writeAll(" = ");
                    try serializeValue(cval, writer);
                    try writer.writeByte('\n');
                }
            }
        }
    }
}

fn serializeValue(value: anytype, writer: anytype) !void {
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
        .optional => {
            if (value) |unwrapped| {
                try serializeValue(unwrapped, writer);
            } else {
                try writer.writeAll("\"\"");
            }
        },
        .@"enum" => {
            try writer.writeByte('"');
            try writer.writeAll(@tagName(value));
            try writer.writeByte('"');
        },
        .pointer => |ptr_info| {
            if (ptr_info.size == .slice and ptr_info.child == u8) {
                try writer.writeByte('"');
                try writer.writeAll(value);
                try writer.writeByte('"');
            } else if (ptr_info.size == .slice) {
                try writer.writeByte('[');
                for (value, 0..) |item, i| {
                    if (i > 0) try writer.writeAll(", ");
                    try serializeValue(item, writer);
                }
                try writer.writeByte(']');
            }
        },
        else => @compileError("Unsupported TOML value type: " ++ @typeName(T)),
    }
}
