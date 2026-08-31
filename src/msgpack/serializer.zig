const std = @import("std");
const meta = @import("../meta.zig");

pub const MsgPackError = error{
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

fn serializeValue(value: anytype, writer: anytype) !void {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    switch (info) {
        .bool => {
            try writer.writeByte(if (value) 0xc3 else 0xc2);
        },
        .null => {
            try writer.writeByte(0xc0);
        },
        .optional => {
            if (value) |unwrapped| {
                try serializeValue(unwrapped, writer);
            } else {
                try writer.writeByte(0xc0);
            }
        },
        .int => |int_info| {
            if (int_info.signedness == .unsigned) {
                if (value <= 0x7f) {
                    try writer.writeByte(@intCast(value));
                } else if (value <= 0xff) {
                    try writer.writeByte(0xcc);
                    try writer.writeByte(@intCast(value));
                } else if (value <= 0xffff) {
                    try writer.writeByte(0xcd);
                    var buf: [2]u8 = undefined;
                    std.mem.writeInt(u16, &buf, @intCast(value), .big);
                    try writer.writeAll(&buf);
                } else if (value <= 0xffffffff) {
                    try writer.writeByte(0xce);
                    var buf: [4]u8 = undefined;
                    std.mem.writeInt(u32, &buf, @intCast(value), .big);
                    try writer.writeAll(&buf);
                } else {
                    try writer.writeByte(0xcf);
                    var buf: [8]u8 = undefined;
                    std.mem.writeInt(u64, &buf, @intCast(value), .big);
                    try writer.writeAll(&buf);
                }
            } else {
                if (value >= -32 and value <= 127) {
                    try writer.writeByte(@bitCast(@as(i8, @intCast(value))));
                } else if (value >= -128 and value <= 127) {
                    try writer.writeByte(0xd0);
                    try writer.writeByte(@bitCast(@as(i8, @intCast(value))));
                } else if (value >= -32768 and value <= 32767) {
                    try writer.writeByte(0xd1);
                    var buf: [2]u8 = undefined;
                    std.mem.writeInt(i16, &buf, @intCast(value), .big);
                    try writer.writeAll(&buf);
                } else if (value >= -2147483648 and value <= 2147483647) {
                    try writer.writeByte(0xd2);
                    var buf: [4]u8 = undefined;
                    std.mem.writeInt(i32, &buf, @intCast(value), .big);
                    try writer.writeAll(&buf);
                } else {
                    try writer.writeByte(0xd3);
                    var buf: [8]u8 = undefined;
                    std.mem.writeInt(i64, &buf, @intCast(value), .big);
                    try writer.writeAll(&buf);
                }
            }
        },
        .float => {
            try writer.writeByte(0xcb); // float 64
            var buf: [8]u8 = undefined;
            const float_val: f64 = @floatCast(value);
            std.mem.writeInt(u64, &buf, @bitCast(float_val), .big);
            try writer.writeAll(&buf);
        },
        .@"enum" => {
            const tag_str = @tagName(value);
            try serializeString(tag_str, writer);
        },
        .pointer => |ptr_info| {
            switch (ptr_info.size) {
                .slice => {
                    if (ptr_info.child == u8) {
                        try serializeString(value, writer);
                    } else {
                        try serializeArray(value, writer);
                    }
                },
                .one => {
                    try serializeValue(value.*, writer);
                },
                else => @compileError("Unsupported pointer type in MsgPack: " ++ @typeName(T)),
            }
        },
        .array => |arr_info| {
            if (arr_info.child == u8) {
                try serializeString(&value, writer);
            } else {
                try serializeArray(&value, writer);
            }
        },
        .@"struct" => {
            try serializeStruct(value, writer);
        },
        else => @compileError("Unsupported type for MsgPack: " ++ @typeName(T)),
    }
}

fn serializeString(str: []const u8, writer: anytype) !void {
    const len = str.len;
    if (len <= 31) {
        try writer.writeByte(0xa0 | @as(u8, @intCast(len)));
    } else if (len <= 0xff) {
        try writer.writeByte(0xd9);
        try writer.writeByte(@intCast(len));
    } else if (len <= 0xffff) {
        try writer.writeByte(0xda);
        var buf: [2]u8 = undefined;
        std.mem.writeInt(u16, &buf, @intCast(len), .big);
        try writer.writeAll(&buf);
    } else {
        try writer.writeByte(0xdb);
        var buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &buf, @intCast(len), .big);
        try writer.writeAll(&buf);
    }
    try writer.writeAll(str);
}

fn serializeArray(slice: anytype, writer: anytype) !void {
    const len = slice.len;
    if (len <= 15) {
        try writer.writeByte(0x90 | @as(u8, @intCast(len)));
    } else if (len <= 0xffff) {
        try writer.writeByte(0xdc);
        var buf: [2]u8 = undefined;
        std.mem.writeInt(u16, &buf, @intCast(len), .big);
        try writer.writeAll(&buf);
    } else {
        try writer.writeByte(0xdd);
        var buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &buf, @intCast(len), .big);
        try writer.writeAll(&buf);
    }
    for (slice) |item| {
        try serializeValue(item, writer);
    }
}

fn serializeStruct(s: anytype, writer: anytype) !void {
    const T = @TypeOf(s);
    const fields = std.meta.fields(T);

    // Count unskipped fields
    var count: usize = 0;
    inline for (fields) |f| {
        const opts = meta.getFieldOptions(T, f.name);
        if (!opts.skip) count += 1;
    }

    if (count <= 15) {
        try writer.writeByte(0x80 | @as(u8, @intCast(count)));
    } else if (count <= 0xffff) {
        try writer.writeByte(0xde);
        var buf: [2]u8 = undefined;
        std.mem.writeInt(u16, &buf, @intCast(count), .big);
        try writer.writeAll(&buf);
    } else {
        try writer.writeByte(0xdf);
        var buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &buf, @intCast(count), .big);
        try writer.writeAll(&buf);
    }

    inline for (fields) |f| {
        const opts = meta.getFieldOptions(T, f.name);
        if (!opts.skip) {
            const key_name = meta.getFieldName(T, f);
            try serializeString(key_name, writer);
            try serializeValue(@field(s, f.name), writer);
        }
    }
}
