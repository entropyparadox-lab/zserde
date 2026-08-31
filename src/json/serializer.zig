const std = @import("std");
const meta = @import("../meta.zig");

pub const SerializeOptions = struct {
    pretty: bool = false,
    indent_size: usize = 2,
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

pub fn serializeToWriter(value: anytype, writer: anytype, options: SerializeOptions) !void {
    try serializeValue(value, writer, options, 0);
}

pub fn serialize(allocator: std.mem.Allocator, value: anytype, options: SerializeOptions) ![]u8 {
    var buffer: std.ArrayList(u8) = .empty;
    errdefer buffer.deinit(allocator);

    var bw = BufferWriter{
        .list = &buffer,
        .allocator = allocator,
    };
    try serializeToWriter(value, &bw, options);

    return buffer.toOwnedSlice(allocator);
}

fn writeIndent(writer: anytype, depth: usize, options: SerializeOptions) !void {
    if (!options.pretty) return;
    try writer.writeByte('\n');
    var i: usize = 0;
    while (i < depth * options.indent_size) : (i += 1) {
        try writer.writeByte(' ');
    }
}

fn serializeValue(value: anytype, writer: anytype, options: SerializeOptions, depth: usize) !void {
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
                try serializeValue(unwrapped, writer, options, depth);
            } else {
                try writer.writeAll("null");
            }
        },
        .@"enum" => {
            try writer.writeByte('"');
            try writer.writeAll(@tagName(value));
            try writer.writeByte('"');
        },
        .pointer => |ptr_info| {
            switch (ptr_info.size) {
                .slice => {
                    if (ptr_info.child == u8) {
                        // String slice
                        try serializeString(value, writer);
                    } else {
                        // Array of items
                        try serializeArray(value, writer, options, depth);
                    }
                },
                .one => {
                    try serializeValue(value.*, writer, options, depth);
                },
                else => @compileError("Unsupported pointer type in serialization: " ++ @typeName(T)),
            }
        },
        .array => |arr_info| {
            if (arr_info.child == u8) {
                try serializeString(&value, writer);
            } else {
                try serializeArray(&value, writer, options, depth);
            }
        },
        .@"struct" => {
            try serializeStruct(value, writer, options, depth);
        },
        .@"union" => |union_info| {
            if (union_info.tag_type == null) {
                @compileError("Untagged unions are not supported in serialization: " ++ @typeName(T));
            }
            switch (value) {
                inline else => |tag_val, tag| {
                    try writer.writeAll("{\"");
                    try writer.writeAll(@tagName(tag));
                    try writer.writeAll("\":");
                    try serializeValue(tag_val, writer, options, depth + 1);
                    try writer.writeByte('}');
                },
            }
        },
        else => @compileError("Unsupported type in serialization: " ++ @typeName(T)),
    }
}

fn serializeString(str: []const u8, writer: anytype) !void {
    try writer.writeByte('"');
    for (str) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            0x08 => try writer.writeAll("\\b"),
            0x0C => try writer.writeAll("\\f"),
            else => {
                if (c < 0x20) {
                    var buf: [16]u8 = undefined;
                    const hex_str = try std.fmt.bufPrint(&buf, "\\u{x:0>4}", .{c});
                    try writer.writeAll(hex_str);
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
    try writer.writeByte('"');
}

fn serializeArray(slice: anytype, writer: anytype, options: SerializeOptions, depth: usize) !void {
    try writer.writeByte('[');
    for (slice, 0..) |item, i| {
        if (i > 0) {
            try writer.writeByte(',');
        }
        try writeIndent(writer, depth + 1, options);
        try serializeValue(item, writer, options, depth + 1);
    }
    if (slice.len > 0) {
        try writeIndent(writer, depth, options);
    }
    try writer.writeByte(']');
}

fn serializeStruct(s: anytype, writer: anytype, options: SerializeOptions, depth: usize) !void {
    const T = @TypeOf(s);
    const fields = std.meta.fields(T);

    try writer.writeByte('{');
    var written_fields: usize = 0;

    inline for (fields) |f| {
        const field_opts = meta.getFieldOptions(T, f.name);
        if (!field_opts.skip) {
            const key_name = meta.getFieldName(T, f);
            const val = @field(s, f.name);

            if (written_fields > 0) {
                try writer.writeByte(',');
            }
            try writeIndent(writer, depth + 1, options);

            try serializeString(key_name, writer);
            try writer.writeByte(':');
            if (options.pretty) {
                try writer.writeByte(' ');
            }

            try serializeValue(val, writer, options, depth + 1);
            written_fields += 1;
        }
    }

    if (written_fields > 0) {
        try writeIndent(writer, depth, options);
    }
    try writer.writeByte('}');
}
