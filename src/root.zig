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

// --- Comprehensive Unit Tests ---

test "zserde: basic json serialization and deserialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const User = struct {
        id: u64,
        name: []const u8,
        is_active: bool,
        score: f64,
    };

    const user = User{
        .id = 42,
        .name = "Alice",
        .is_active = true,
        .score = 98.5,
    };

    // Serialize
    const json_bytes = try json.toSlice(allocator, user, .{});
    defer allocator.free(json_bytes);

    try testing.expect(std.mem.indexOf(u8, json_bytes, "\"id\":42") != null);
    try testing.expect(std.mem.indexOf(u8, json_bytes, "\"name\":\"Alice\"") != null);
    try testing.expect(std.mem.indexOf(u8, json_bytes, "\"is_active\":true") != null);

    // Deserialize (Zero-copy borrowed)
    const parsed = try json.fromSliceBorrowed(User, json_bytes);
    try testing.expectEqual(@as(u64, 42), parsed.id);
    try testing.expectEqualStrings("Alice", parsed.name);
    try testing.expectEqual(true, parsed.is_active);
    try testing.expectEqual(@as(f64, 98.5), parsed.score);
}

test "zserde: custom field rename and skip metadata" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const Config = struct {
        api_key: []const u8,
        secret_token: []const u8,
        timeout_ms: u32 = 5000,
        debug_mode: ?bool = null,

        pub const zserde = .{
            .rename = .{
                .api_key = "apiKey",
                .timeout_ms = "timeout",
            },
            .skip = .{
                .secret_token = true,
            },
        };
    };

    const cfg = Config{
        .api_key = "pk_live_12345",
        .secret_token = "SUPER_SECRET_DO_NOT_SERIALIZE",
        .timeout_ms = 3000,
        .debug_mode = true,
    };

    // Serialize
    const json_bytes = try json.toSlice(allocator, cfg, .{});
    defer allocator.free(json_bytes);

    // Ensure secret_token was skipped
    try testing.expect(std.mem.indexOf(u8, json_bytes, "SUPER_SECRET") == null);
    try testing.expect(std.mem.indexOf(u8, json_bytes, "\"apiKey\":\"pk_live_12345\"") != null);
    try testing.expect(std.mem.indexOf(u8, json_bytes, "\"timeout\":3000") != null);

    // Deserialize from JSON containing renamed keys
    const incoming_json = "{\"apiKey\":\"pk_test_999\",\"timeout\":1000}";
    const parsed = try json.fromSliceBorrowed(Config, incoming_json);
    try testing.expectEqualStrings("pk_test_999", parsed.api_key);
    try testing.expectEqual(@as(u32, 1000), parsed.timeout_ms);
    try testing.expectEqual(@as(?bool, null), parsed.debug_mode);
}

test "zschema: compile-time struct field validation" {
    const testing = std.testing;

    const Registration = struct {
        username: []const u8,
        age: u32,
        email: []const u8,

        pub const zvalidate = .{
            .username = .{ .min_len = 3, .max_len = 20 },
            .age = .{ .min = 18, .max = 100 },
            .email = .{ .contains = "@" },
        };
    };

    // Valid user
    const valid_user = Registration{
        .username = "alice_dev",
        .age = 25,
        .email = "alice@example.com",
    };
    try validate(valid_user);

    // Invalid username (too short)
    const invalid_user1 = Registration{
        .username = "al",
        .age = 25,
        .email = "alice@example.com",
    };
    try testing.expectError(schema.ValidationError.StringTooShort, validate(invalid_user1));

    // Invalid age (underage)
    const invalid_user2 = Registration{
        .username = "bob_builder",
        .age = 16,
        .email = "bob@example.com",
    };
    try testing.expectError(schema.ValidationError.ValueTooSmall, validate(invalid_user2));

    // Invalid email (missing @)
    const invalid_user3 = Registration{
        .username = "charlie",
        .age = 30,
        .email = "invalid_email.com",
    };
    try testing.expectError(schema.ValidationError.PatternMismatch, validate(invalid_user3));
}
