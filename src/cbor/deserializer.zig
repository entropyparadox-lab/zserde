const std = @import("std");
const meta = @import("../meta.zig");

pub const CborError = error{
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

    fn readByte(self: *Deserializer) CborError!u8 {
        if (self.pos >= self.input.len) return CborError.UnexpectedEndOfInput;
        const b = self.input[self.pos];
        self.pos += 1;
        return b;
    }

    fn readBytes(self: *Deserializer, len: usize) CborError![]const u8 {
        if (self.pos + len > self.input.len) return CborError.UnexpectedEndOfInput;
        const slice = self.input[self.pos .. self.pos + len];
        self.pos += len;
        return slice;
    }

    fn readTypeAndLength(self: *Deserializer) CborError!struct { major: u8, len: u64 } {
        const initial = try self.readByte();
        const major = initial >> 5;
        const info = initial & 0x1f;

        if (info < 24) {
            return .{ .major = major, .len = info };
        } else if (info == 24) {
            const b = try self.readByte();
            return .{ .major = major, .len = b };
        } else if (info == 25) {
            const raw = try self.readBytes(2);
            return .{ .major = major, .len = std.mem.readInt(u16, raw[0..2], .big) };
        } else if (info == 26) {
            const raw = try self.readBytes(4);
            return .{ .major = major, .len = std.mem.readInt(u32, raw[0..4], .big) };
        } else if (info == 27) {
            const raw = try self.readBytes(8);
            return .{ .major = major, .len = std.mem.readInt(u64, raw[0..8], .big) };
        } else {
            return CborError.InvalidTypeMarker;
        }
    }

    pub fn parseStringBorrowed(self: *Deserializer) CborError![]const u8 {
        const header = try self.readTypeAndLength();
        if (header.major != 3 and header.major != 2) {
            return CborError.TypeMismatch;
        }
        return try self.readBytes(@intCast(header.len));
    }

    pub fn parseValue(self: *Deserializer, comptime T: type, allocator: ?std.mem.Allocator) CborError!T {
        const info = @typeInfo(T);

        switch (info) {
            .bool => {
                if (self.pos >= self.input.len) return CborError.UnexpectedEndOfInput;
                const b = self.input[self.pos];
                if (b == 0xf5) {
                    self.pos += 1;
                    return true;
                } else if (b == 0xf4) {
                    self.pos += 1;
                    return false;
                }
                return CborError.TypeMismatch;
            },
            .optional => |opt| {
                if (self.pos < self.input.len and self.input[self.pos] == 0xf6) {
                    self.pos += 1;
                    return null;
                }
                return try self.parseValue(opt.child, allocator);
            },
            .int => |int_info| {
                const header = try self.readTypeAndLength();
                if (header.major == 0) {
                    return @intCast(header.len);
                } else if (header.major == 1) {
                    if (int_info.signedness == .unsigned) return CborError.TypeMismatch;
                    const val: i64 = -1 - @as(i64, @intCast(header.len));
                    return @intCast(val);
                }
                return CborError.TypeMismatch;
            },
            .float => {
                const initial = try self.readByte();
                if (initial == 0xfb) {
                    const raw = try self.readBytes(8);
                    const bits = std.mem.readInt(u64, raw[0..8], .big);
                    const f: f64 = @bitCast(bits);
                    return @floatCast(f);
                } else if (initial == 0xfa) {
                    const raw = try self.readBytes(4);
                    const bits = std.mem.readInt(u32, raw[0..4], .big);
                    const f: f32 = @bitCast(bits);
                    return @floatCast(f);
                }
                return CborError.TypeMismatch;
            },
            .@"enum" => {
                const name = try self.parseStringBorrowed();
                return std.meta.stringToEnum(T, name) orelse CborError.TypeMismatch;
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
                            const alloc = allocator orelse return CborError.OutOfMemory;
                            const header = try self.readTypeAndLength();
                            if (header.major != 4) return CborError.TypeMismatch;

                            var list: std.ArrayList(ptr_info.child) = .empty;
                            errdefer list.deinit(alloc);

                            var i: usize = 0;
                            while (i < header.len) : (i += 1) {
                                const item = try self.parseValue(ptr_info.child, alloc);
                                try list.append(alloc, item);
                            }
                            return list.toOwnedSlice(alloc);
                        }
                    },
                    else => @compileError("Unsupported pointer type in CBOR: " ++ @typeName(T)),
                }
            },
            .@"struct" => {
                return self.parseStruct(T, allocator);
            },
            else => @compileError("Unsupported type for CBOR: " ++ @typeName(T)),
        }
    }

    fn parseStruct(self: *Deserializer, comptime T: type, allocator: ?std.mem.Allocator) CborError!T {
        const header = try self.readTypeAndLength();
        if (header.major != 5) return CborError.TypeMismatch;

        var result: T = undefined;
        const fields = std.meta.fields(T);
        var field_set = std.StaticBitSet(fields.len).initEmpty();

        var idx: usize = 0;
        while (idx < header.len) : (idx += 1) {
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
                    return CborError.MissingRequiredField;
                }
            }
        }

        return result;
    }

    fn skipValue(self: *Deserializer) CborError!void {
        const header = try self.readTypeAndLength();
        switch (header.major) {
            0, 1, 7 => {},
            2, 3 => {
                _ = try self.readBytes(@intCast(header.len));
            },
            4 => {
                var i: usize = 0;
                while (i < header.len) : (i += 1) {
                    try self.skipValue();
                }
            },
            5 => {
                var i: usize = 0;
                while (i < header.len * 2) : (i += 1) {
                    try self.skipValue();
                }
            },
            else => return CborError.InvalidTypeMarker,
        }
    }
};

pub fn deserialize(comptime T: type, allocator: std.mem.Allocator, input: []const u8) CborError!T {
    var de = Deserializer.init(input);
    return de.parseValue(T, allocator);
}

pub fn deserializeBorrowed(comptime T: type, input: []const u8) CborError!T {
    var de = Deserializer.init(input);
    return de.parseValue(T, null);
}
