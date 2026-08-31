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

    pub fn toSliceWithConfig(
        allocator: std.mem.Allocator,
        value: anytype,
        options: SerializeOptions,
        comptime config: anytype,
    ) ![]u8 {
        return serializer.serializeWithConfig(allocator, value, options, config);
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

    pub fn unescapeInPlace(buf: []u8) ![]u8 {
        return deserializer.unescapeInPlace(buf);
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

test "zserde: rename_all = .camelCase automatic conversion across JSON & MsgPack" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const JobPayload = struct {
        job_id: u32,
        task_name: []const u8,
        max_retry_count: u8,

        pub const zserde = .{
            .rename_all = .camelCase,
        };
    };

    const job = JobPayload{
        .job_id = 77,
        .task_name = "sync_database",
        .max_retry_count = 3,
    };

    // JSON
    const json_str = try json.toSlice(allocator, job, .{});
    defer allocator.free(json_str);

    try testing.expect(std.mem.indexOf(u8, json_str, "\"jobId\":77") != null);
    try testing.expect(std.mem.indexOf(u8, json_str, "\"taskName\":\"sync_database\"") != null);
    try testing.expect(std.mem.indexOf(u8, json_str, "\"maxRetryCount\":3") != null);

    const parsed_json = try json.fromSliceBorrowed(JobPayload, json_str);
    try testing.expectEqual(@as(u32, 77), parsed_json.job_id);
    try testing.expectEqualStrings("sync_database", parsed_json.task_name);
    try testing.expectEqual(@as(u8, 3), parsed_json.max_retry_count);

    // MsgPack
    const mp_bytes = try msgpack.toSlice(allocator, job);
    defer allocator.free(mp_bytes);
    const parsed_mp = try msgpack.fromSliceBorrowed(JobPayload, mp_bytes);
    try testing.expectEqual(@as(u32, 77), parsed_mp.job_id);
    try testing.expectEqualStrings("sync_database", parsed_mp.task_name);
}

test "zserde: Call-site configuration override without modifying struct" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Unowned third party struct (no pub const zserde)
    const ThirdPartyItem = struct {
        item_code: []const u8,
        stock_count: u32,
    };

    const item = ThirdPartyItem{
        .item_code = "SKU-990",
        .stock_count = 150,
    };

    const json_str = try json.toSliceWithConfig(allocator, item, .{}, .{
        .rename_all = .camelCase,
    });
    defer allocator.free(json_str);

    try testing.expect(std.mem.indexOf(u8, json_str, "\"itemCode\":\"SKU-990\"") != null);
    try testing.expect(std.mem.indexOf(u8, json_str, "\"stockCount\":150") != null);
}

test "zserde: In-place zero-copy unescaping of JSON strings" {
    const testing = std.testing;

    var escaped_buffer = "hello\\nworld\\t\\\"test\\\"".*;
    const unescaped = try json.unescapeInPlace(&escaped_buffer);

    try testing.expectEqualStrings("hello\nworld\t\"test\"", unescaped);
}

test "zserde: SIMD whitespace scanning across large padded payloads" {
    const testing = std.testing;

    const LargePadding = struct {
        status: []const u8,
        count: u32,
    };

    const padded_json =
        \\{
        \\                "status": "healthy",
        \\                "count": 1000
        \\}
    ;

    const parsed = try json.fromSliceBorrowed(LargePadding, padded_json);
    try testing.expectEqualStrings("healthy", parsed.status);
    try testing.expectEqual(@as(u32, 1000), parsed.count);
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
