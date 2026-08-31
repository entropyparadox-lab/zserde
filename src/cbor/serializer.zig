const std = @import("std");
const meta = @import("../meta.zig");

pub const CborError = error{
    UnexpectedEndOfInput,
    InvalidTypeMarker,
    TypeMismatch,
    MissingRequiredField,
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
    try serializeValue(value, &bw);

    return buffer.toOwnedSlice(allocator);
}

fn writeTypeAndLength(major: u8, len: u64, writer: anytype) !void {
    const major_shifted: u8 = major << 5;
    if (len < 24) {
        try writer.writeByte(major_shifted | @as(u8, @intCast(len)));
    } else if (len <= 0xff) {
        try writer.writeByte(major_shifted | 24);
        try writer.writeByte(@intCast(len));
    } else if (len <= 0xffff) {
        try writer.writeByte(major_shifted | 25);
        var buf: [2]u8 = undefined;
        std.mem.writeInt(u16, &buf, @intCast(len), .big);
        try writer.writeAll(&buf);
    } else if (len <= 0xffffffff) {
        try writer.writeByte(major_shifted | 26);
        var buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &buf, @intCast(len), .big);
        try writer.writeAll(&buf);
    } else {
        try writer.writeByte(major_shifted | 27);
        var buf: [8]u8 = undefined;
        std.mem.writeInt(u64, &buf, len, .big);
        try writer.writeAll(&buf);
    }
}

fn serializeValue(value: anytype, writer: anytype) !void {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    switch (info) {
        .bool => {
            try writer.writeByte(if (value) 0xf5 else 0xf4);
        },
        .null => {
            try writer.writeByte(0xf6);
        },
        .optional => {
            if (value) |unwrapped| {
                try serializeValue(unwrapped, writer);
            } else {
                try writer.writeByte(0xf6);
            }
        },
        .int => |int_info| {
            if (int_info.signedness == .unsigned) {
                try writeTypeAndLength(0, @intCast(value), writer);
            } else {
                if (value >= 0) {
                    try writeTypeAndLength(0, @intCast(value), writer);
                } else {
                    const abs_val: u64 = @intCast(-1 - value);
                    try writeTypeAndLength(1, abs_val, writer);
                }
            }
        },
        .float => {
            try writer.writeByte(0xfb); // Double-precision float (64-bit)
            var buf: [8]u8 = undefined;
            const float_val: f64 = @floatCast(value);
            std.mem.writeInt(u64, &buf, @bitCast(float_val), .big);
            try writer.writeAll(&buf);
        },
        .@"enum" => {
            const tag_str = @tagName(value);
            try writeTypeAndLength(3, tag_str.len, writer);
            try writer.writeAll(tag_str);
        },
        .pointer => |ptr_info| {
            switch (ptr_info.size) {
                .slice => {
                    if (ptr_info.child == u8) {
                        try writeTypeAndLength(3, value.len, writer);
                        try writer.writeAll(value);
                    } else {
                        try writeTypeAndLength(4, value.len, writer);
                        for (value) |item| {
                            try serializeValue(item, writer);
                        }
                    }
                },
                .one => {
                    try serializeValue(value.*, writer);
                },
                else => @compileError("Unsupported pointer type in CBOR: " ++ @typeName(T)),
            }
        },
        .array => |arr_info| {
            if (arr_info.child == u8) {
                try writeTypeAndLength(3, value.len, writer);
                try writer.writeAll(&value);
            } else {
                try writeTypeAndLength(4, value.len, writer);
                for (value) |item| {
                    try serializeValue(item, writer);
                }
            }
        },
        .@"struct" => {
            try serializeStruct(value, writer);
        },
        else => @compileError("Unsupported type for CBOR: " ++ @typeName(T)),
    }
}

fn serializeStruct(s: anytype, writer: anytype) !void {
    const T = @TypeOf(s);
    const fields = std.meta.fields(T);

    var count: usize = 0;
    inline for (fields) |f| {
        const opts = meta.getFieldOptions(T, f.name);
        if (!opts.skip) count += 1;
    }

    try writeTypeAndLength(5, count, writer);

    inline for (fields) |f| {
        const opts = meta.getFieldOptions(T, f.name);
        if (!opts.skip) {
            const key_name = if (opts.rename) |r| r else f.name;
            try writeTypeAndLength(3, key_name.len, writer);
            try writer.writeAll(key_name);
            try serializeValue(@field(s, f.name), writer);
        }
    }
}
