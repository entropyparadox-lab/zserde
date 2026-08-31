const std = @import("std");
const meta = @import("../meta.zig");

pub const MsgPackError = error{
    UnexpectedEndOfInput,
    InvalidTypeMarker,
    TypeMismatch,
    MissingRequiredField,
    OutOfMemory,
};

pub const Deserializer = struct {
    input: []const u8,
    pos: usize = 0,

    pub fn init(input: []const u8) Deserializer {
        return .{ .input = input, .pos = 0 };
    }

    fn readByte(self: *Deserializer) MsgPackError!u8 {
        if (self.pos >= self.input.len) return MsgPackError.UnexpectedEndOfInput;
        const b = self.input[self.pos];
        self.pos += 1;
        return b;
    }

    fn readBytes(self: *Deserializer, len: usize) MsgPackError![]const u8 {
        if (self.pos + len > self.input.len) return MsgPackError.UnexpectedEndOfInput;
        const slice = self.input[self.pos .. self.pos + len];
        self.pos += len;
        return slice;
    }

    pub fn parseStringBorrowed(self: *Deserializer) MsgPackError![]const u8 {
        const marker = try self.readByte();
        var len: usize = 0;
        if (marker >= 0xa0 and marker <= 0xbf) {
            len = marker & 0x1f;
        } else if (marker == 0xd9) {
            len = try self.readByte();
        } else if (marker == 0xda) {
            const raw = try self.readBytes(2);
            len = std.mem.readInt(u16, raw[0..2], .big);
        } else if (marker == 0xdb) {
            const raw = try self.readBytes(4);
            len = std.mem.readInt(u32, raw[0..4], .big);
        } else {
            return MsgPackError.TypeMismatch;
        }
        return try self.readBytes(len);
    }

    pub fn parseValue(self: *Deserializer, comptime T: type, allocator: ?std.mem.Allocator) MsgPackError!T {
        const info = @typeInfo(T);

        switch (info) {
            .bool => {
                const marker = try self.readByte();
                if (marker == 0xc3) return true;
                if (marker == 0xc2) return false;
                return MsgPackError.TypeMismatch;
            },
            .optional => |opt| {
                if (self.pos < self.input.len and self.input[self.pos] == 0xc0) {
                    self.pos += 1;
                    return null;
                }
                return try self.parseValue(opt.child, allocator);
            },
            .int => |int_info| {
                const marker = try self.readByte();
                if (marker <= 0x7f) {
                    // positive fixint
                    return @intCast(marker);
                } else if (marker >= 0xe0) {
                    // negative fixint
                    const signed_byte: i8 = @bitCast(marker);
                    return @intCast(signed_byte);
                } else if (marker == 0xcc) {
                    // uint 8
                    return @intCast(try self.readByte());
                } else if (marker == 0xcd) {
                    // uint 16
                    const raw = try self.readBytes(2);
                    return @intCast(std.mem.readInt(u16, raw[0..2], .big));
                } else if (marker == 0xce) {
                    // uint 32
                    const raw = try self.readBytes(4);
                    return @intCast(std.mem.readInt(u32, raw[0..4], .big));
                } else if (marker == 0xcf) {
                    // uint 64
                    const raw = try self.readBytes(8);
                    const val = std.mem.readInt(u64, raw[0..8], .big);
                    return @intCast(val);
                } else if (marker == 0xd0) {
                    // int 8
                    const b = try self.readByte();
                    const signed_b: i8 = @bitCast(b);
                    return @intCast(signed_b);
                } else if (marker == 0xd1) {
                    // int 16
                    const raw = try self.readBytes(2);
                    return @intCast(std.mem.readInt(i16, raw[0..2], .big));
                } else if (marker == 0xd2) {
                    // int 32
                    const raw = try self.readBytes(4);
                    return @intCast(std.mem.readInt(i32, raw[0..4], .big));
                } else if (marker == 0xd3) {
                    // int 64
                    const raw = try self.readBytes(8);
                    const val = std.mem.readInt(i64, raw[0..8], .big);
                    return @intCast(val);
                } else {
                    _ = int_info;
                    return MsgPackError.TypeMismatch;
                }
            },
            .float => {
                const marker = try self.readByte();
                if (marker == 0xca) {
                    const raw = try self.readBytes(4);
                    const bits = std.mem.readInt(u32, raw[0..4], .big);
                    const f: f32 = @bitCast(bits);
                    return @floatCast(f);
                } else if (marker == 0xcb) {
                    const raw = try self.readBytes(8);
                    const bits = std.mem.readInt(u64, raw[0..8], .big);
                    const f: f64 = @bitCast(bits);
                    return @floatCast(f);
                }
                return MsgPackError.TypeMismatch;
            },
            .@"enum" => {
                const name = try self.parseStringBorrowed();
                return std.meta.stringToEnum(T, name) orelse MsgPackError.TypeMismatch;
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
                            const alloc = allocator orelse return MsgPackError.OutOfMemory;
                            const marker = try self.readByte();
                            var len: usize = 0;
                            if (marker >= 0x90 and marker <= 0x9f) {
                                len = marker & 0x0f;
                            } else if (marker == 0xdc) {
                                const raw = try self.readBytes(2);
                                len = std.mem.readInt(u16, raw[0..2], .big);
                            } else if (marker == 0xdd) {
                                const raw = try self.readBytes(4);
                                len = std.mem.readInt(u32, raw[0..4], .big);
                            } else {
                                return MsgPackError.TypeMismatch;
                            }

                            var list: std.ArrayList(ptr_info.child) = .empty;
                            errdefer list.deinit(alloc);

                            var i: usize = 0;
                            while (i < len) : (i += 1) {
                                const item = try self.parseValue(ptr_info.child, alloc);
                                try list.append(alloc, item);
                            }
                            return list.toOwnedSlice(alloc);
                        }
                    },
                    else => @compileError("Unsupported pointer type in MsgPack: " ++ @typeName(T)),
                }
            },
            .@"struct" => {
                return self.parseStruct(T, allocator);
            },
            else => @compileError("Unsupported type for MsgPack: " ++ @typeName(T)),
        }
    }

    fn parseStruct(self: *Deserializer, comptime T: type, allocator: ?std.mem.Allocator) MsgPackError!T {
        const marker = try self.readByte();
        var map_len: usize = 0;
        if (marker >= 0x80 and marker <= 0x8f) {
            map_len = marker & 0x0f;
        } else if (marker == 0xde) {
            const raw = try self.readBytes(2);
            map_len = std.mem.readInt(u16, raw[0..2], .big);
        } else if (marker == 0xdf) {
            const raw = try self.readBytes(4);
            map_len = std.mem.readInt(u32, raw[0..4], .big);
        } else {
            return MsgPackError.TypeMismatch;
        }

        var result: T = undefined;
        const fields = std.meta.fields(T);
        var field_set = std.StaticBitSet(fields.len).initEmpty();

        var idx: usize = 0;
        while (idx < map_len) : (idx += 1) {
            const key = try self.parseStringBorrowed();
            var matched = false;

            inline for (fields, 0..) |f, i| {
                const target_name = meta.getFieldName(T, f);
                const opts = meta.getFieldOptions(T, f.name);
                if (!opts.skip and std.mem.eql(u8, key, target_name)) {
                    @field(result, f.name) = try self.parseValue(f.type, allocator);
                    field_set.set(i);
                    matched = true;
                    break;
                }
            }

            if (!matched) {
                // Skip unrecognised value
                try self.skipValue();
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
                    return MsgPackError.MissingRequiredField;
                }
            }
        }

        return result;
    }

    fn skipValue(self: *Deserializer) MsgPackError!void {
        const marker = try self.readByte();
        if (marker <= 0x7f or marker >= 0xe0 or marker == 0xc0 or marker == 0xc2 or marker == 0xc3) {
            return;
        } else if (marker == 0xcc or marker == 0xd0) {
            _ = try self.readByte();
        } else if (marker == 0xcd or marker == 0xd1) {
            _ = try self.readBytes(2);
        } else if (marker == 0xce or marker == 0xd2 or marker == 0xca) {
            _ = try self.readBytes(4);
        } else if (marker == 0xcf or marker == 0xd3 or marker == 0xcb) {
            _ = try self.readBytes(8);
        } else if (marker >= 0xa0 and marker <= 0xbf) {
            _ = try self.readBytes(marker & 0x1f);
        } else if (marker == 0xd9) {
            const len = try self.readByte();
            _ = try self.readBytes(len);
        } else if (marker == 0xda) {
            const raw = try self.readBytes(2);
            const len = std.mem.readInt(u16, raw[0..2], .big);
            _ = try self.readBytes(len);
        } else if (marker == 0xdb) {
            const raw = try self.readBytes(4);
            const len = std.mem.readInt(u32, raw[0..4], .big);
            _ = try self.readBytes(len);
        }
    }
};

pub fn deserialize(comptime T: type, allocator: std.mem.Allocator, input: []const u8) MsgPackError!T {
    var de = Deserializer.init(input);
    return de.parseValue(T, allocator);
}

pub fn deserializeBorrowed(comptime T: type, input: []const u8) MsgPackError!T {
    var de = Deserializer.init(input);
    return de.parseValue(T, null);
}
