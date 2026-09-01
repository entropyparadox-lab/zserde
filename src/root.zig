const std = @import("std");

pub const meta = @import("meta.zig");
pub const schema = @import("schema/validator.zig");
pub const validate = schema.validate;
pub const validateWithReport = schema.validateWithReport;
pub const ValidationReport = schema.ValidationReport;
pub const FieldViolation = schema.FieldViolation;

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

pub const cbor = struct {
    pub const serializer = @import("cbor/serializer.zig");
    pub const deserializer = @import("cbor/deserializer.zig");
    pub const CborError = serializer.CborError;

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

pub const yaml = struct {
    pub const serializer = @import("yaml/serializer.zig");
    pub const deserializer = @import("yaml/deserializer.zig");
    pub const YamlError = serializer.YamlError;

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

test {
    _ = @import("edge_cases.zig");
}

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

test "zserde: CBOR binary serialization and zero-copy deserialization" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const IoTMetric = struct {
        sensor_id: u32,
        temperature: f64,
        humidity: f64,
        is_alert: bool,

        pub const zserde = .{
            .rename_all = .camelCase,
        };
    };

    const metric = IoTMetric{
        .sensor_id = 90210,
        .temperature = 23.85,
        .humidity = 58.2,
        .is_alert = false,
    };

    const cbor_bytes = try cbor.toSlice(allocator, metric);
    defer allocator.free(cbor_bytes);

    const decoded = try cbor.fromSliceBorrowed(IoTMetric, cbor_bytes);
    try testing.expectEqual(@as(u32, 90210), decoded.sensor_id);
    try testing.expectEqual(false, decoded.is_alert);
}

test "zserde: YAML serialization and deserialization with nested optional struct" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const ServiceConfig = struct {
        name: []const u8,
        port: u16,
        enabled: bool,
    };

    const Deployment = struct {
        app: []const u8,
        replicas: u32,
        service: ?ServiceConfig = null,
    };

    const dep = Deployment{
        .app = "web-backend",
        .replicas = 5,
        .service = ServiceConfig{
            .name = "http-api",
            .port = 8080,
            .enabled = true,
        },
    };

    const yaml_str = try yaml.toSlice(allocator, dep);
    defer allocator.free(yaml_str);

    try testing.expect(std.mem.indexOf(u8, yaml_str, "app: web-backend") != null);
    try testing.expect(std.mem.indexOf(u8, yaml_str, "replicas: 5") != null);

    const parsed = try yaml.fromSliceBorrowed(Deployment, yaml_str);
    try testing.expectEqualStrings("web-backend", parsed.app);
    try testing.expectEqual(@as(u32, 5), parsed.replicas);
    try testing.expect(parsed.service != null);
    try testing.expectEqualStrings("http-api", parsed.service.?.name);
    try testing.expectEqual(@as(u16, 8080), parsed.service.?.port);
    try testing.expectEqual(true, parsed.service.?.enabled);
}

test "zschema: structured error reporting via validateWithReport" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const UserForm = struct {
        username: []const u8,
        age: u32,
        email: []const u8,

        pub const zvalidate = .{
            .username = .{ .min_len = 5 },
            .age = .{ .min = 18, .max = 65 },
            .email = .{ .contains = "@" },
        };
    };

    const invalid_form = UserForm{
        .username = "al", // too short (min 5)
        .age = 15, // underage (min 18)
        .email = "no_at_sign.com", // missing @
    };

    var report = try validateWithReport(invalid_form, allocator);
    defer report.deinit();

    try testing.expectEqual(false, report.isValid());
    try testing.expectEqual(@as(usize, 3), report.violations.len);
    try testing.expectEqualStrings("username", report.violations[0].field);
    try testing.expectEqualStrings("age", report.violations[1].field);
    try testing.expectEqualStrings("email", report.violations[2].field);
}
