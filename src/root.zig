const std = @import("std");

pub const meta = @import("meta.zig");
pub const schema = @import("schema/validator.zig");
pub const validate = schema.validate;

pub const json = struct {
    pub const serializer = @import("json/serializer.zig");
    pub const deserializer = @import("json/deserializer.zig");

    pub const SerializeOptions = serializer.SerializeOptions;
    pub const DeserializeError = deserializer.DeserializeError;

    pub fn toSlice(allocator: std.mem.Allocator, value: anytype, options: SerializeOptions) ![]u8 {
        return serializer.serialize(allocator, value, options);
    }

    pub fn toWriter(value: anytype, writer: anytype, options: SerializeOptions) !void {
        return serializer.serializeToWriter(value, writer, options);
    }

    pub fn fromSlice(comptime T: type, allocator: std.mem.Allocator, input: []const u8) !T {
        return deserializer.deserialize(T, allocator, input);
    }

    pub fn fromSliceBorrowed(comptime T: type, input: []const u8) !T {
        return deserializer.deserializeBorrowed(T, input);
    }
};

pub const msgpack = struct {
    pub const serializer = @import("msgpack/serializer.zig");
    pub const deserializer = @import("msgpack/deserializer.zig");
    pub const MsgPackError = serializer.MsgPackError;

    pub fn toSlice(allocator: std.mem.Allocator, value: anytype) ![]u8 {
        return serializer.serialize(allocator, value);
    }

    pub fn fromSlice(comptime T: type, allocator: std.mem.Allocator, input: []const u8) !T {
        return deserializer.deserialize(T, allocator, input);
    }

    pub fn fromSliceBorrowed(comptime T: type, input: []const u8) !T {
        return deserializer.deserializeBorrowed(T, input);
    }
};

pub const toml = struct {
    pub const serializer = @import("toml/serializer.zig");
    pub const deserializer = @import("toml/deserializer.zig");
    pub const TomlError = serializer.TomlError;

    pub fn toSlice(allocator: std.mem.Allocator, value: anytype) ![]u8 {
        return serializer.serialize(allocator, value);
    }

    pub fn fromSlice(comptime T: type, allocator: std.mem.Allocator, input: []const u8) !T {
        return deserializer.deserialize(T, allocator, input);
    }

    pub fn fromSliceBorrowed(comptime T: type, input: []const u8) !T {
        return deserializer.deserializeBorrowed(T, input);
    }
};

// --- Comprehensive Unit Tests ---

test "zserde: JSON serialization, deserialization, skip, rename" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const User = struct {
        id: u64,
        name: []const u8,
        secret: []const u8 = "masked",
        is_active: bool = true,

        pub const zserde = .{
            .rename = .{ .is_active = "isActive" },
            .skip = .{ .secret = true },
        };
    };

    const u = User{
        .id = 101,
        .name = "Alice",
        .secret = "do_not_share",
        .is_active = true,
    };

    const serialized = try json.toSlice(allocator, u, .{});
    defer allocator.free(serialized);

    try testing.expect(std.mem.indexOf(u8, serialized, "\"isActive\":true") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "do_not_share") == null);

    const parsed = try json.fromSliceBorrowed(User, serialized);
    try testing.expectEqual(@as(u64, 101), parsed.id);
    try testing.expectEqualStrings("Alice", parsed.name);
    try testing.expectEqual(true, parsed.is_active);
}

test "zserde: MsgPack binary zero-copy roundtrip" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const Packet = struct {
        cmd_id: u16,
        session: []const u8,
        latency_ms: f64,
        is_encrypted: bool,
    };

    const pkt = Packet{
        .cmd_id = 4096,
        .session = "sess_01J98X7ABQ",
        .latency_ms = 1.45,
        .is_encrypted = true,
    };

    const binary = try msgpack.toSlice(allocator, pkt);
    defer allocator.free(binary);

    const decoded = try msgpack.fromSliceBorrowed(Packet, binary);
    try testing.expectEqual(@as(u16, 4096), decoded.cmd_id);
    try testing.expectEqualStrings("sess_01J98X7ABQ", decoded.session);
    try testing.expectEqual(true, decoded.is_encrypted);
}

test "zserde: TOML configuration serialization and deserialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const ServerConfig = struct {
        host: []const u8,
        port: u16,
        workers: u32,
    };

    const AppConfig = struct {
        app_name: []const u8,
        version: []const u8,
        server: ServerConfig,

        pub const zserde = .{
            .rename = .{ .app_name = "appName" },
        };
    };

    const cfg = AppConfig{
        .app_name = "EntropyHub",
        .version = "1.0.0",
        .server = .{
            .host = "127.0.0.1",
            .port = 8080,
            .workers = 4,
        },
    };

    const toml_str = try toml.toSlice(allocator, cfg);
    defer allocator.free(toml_str);

    try testing.expect(std.mem.indexOf(u8, toml_str, "appName = \"EntropyHub\"") != null);
    try testing.expect(std.mem.indexOf(u8, toml_str, "[server]") != null);

    const parsed = try toml.fromSliceBorrowed(AppConfig, toml_str);
    try testing.expectEqualStrings("EntropyHub", parsed.app_name);
    try testing.expectEqualStrings("1.0.0", parsed.version);
    try testing.expectEqualStrings("127.0.0.1", parsed.server.host);
    try testing.expectEqual(@as(u16, 8080), parsed.server.port);
    try testing.expectEqual(@as(u32, 4), parsed.server.workers);
}

test "zschema: rich validation constraints" {
    const testing = std.testing;

    const Profile = struct {
        username: []const u8,
        age: ?u32,
        email: []const u8,

        pub const zvalidate = .{
            .username = .{ .min_len = 3, .max_len = 20, .starts_with = "user_" },
            .age = .{ .min = 18, .max = 100 },
            .email = .{ .contains = "@", .ends_with = ".com" },
        };
    };

    const valid = Profile{
        .username = "user_john",
        .age = 28,
        .email = "john@company.com",
    };
    try validate(valid);

    // Optional age = null is valid
    const valid_null_age = Profile{
        .username = "user_smith",
        .age = null,
        .email = "smith@company.com",
    };
    try validate(valid_null_age);

    // Prefix mismatch
    const invalid_prefix = Profile{
        .username = "admin_john",
        .age = 30,
        .email = "john@company.com",
    };
    try testing.expectError(schema.ValidationError.PatternMismatch, validate(invalid_prefix));
}
