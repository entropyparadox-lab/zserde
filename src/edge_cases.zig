const std = @import("std");
const zserde = @import("root.zig");
const testing = std.testing;

// ============================================================================
// 1. JSON Edge Cases & Adversarial Tests
// ============================================================================

test "json: malformed & truncated input returns error" {
    const Simple = struct {
        id: u32,
        name: []const u8,
    };

    // Empty input
    try testing.expectError(error.UnexpectedEndOfInput, zserde.json.fromSliceBorrowed(Simple, ""));
    // Truncated key/value
    try testing.expectError(error.InvalidNumber, zserde.json.fromSliceBorrowed(Simple, "{\"id\":"));
    // Missing closing brace
    try testing.expectError(error.UnexpectedEndOfInput, zserde.json.fromSliceBorrowed(Simple, "{\"id\":10,\"name\":\"foo\""));
}

test "json: boundary integers and signed/unsigned range" {
    const IntStruct = struct {
        u_zero: u64,
        u_max: u64,
        i_neg: i64,
        i_pos: i64,
    };

    const payload =
        \\{
        \\  "u_zero": 0,
        \\  "u_max": 18446744073709551615,
        \\  "i_neg": -9223372036854775807,
        \\  "i_pos": 9223372036854775807
        \\}
    ;

    const parsed = try zserde.json.fromSliceBorrowed(IntStruct, payload);
    try testing.expectEqual(@as(u64, 0), parsed.u_zero);
    try testing.expectEqual(std.math.maxInt(u64), parsed.u_max);
    try testing.expectEqual(-9223372036854775807, parsed.i_neg);
    try testing.expectEqual(9223372036854775807, parsed.i_pos);
}

test "json: optional fields present, null, and missing" {
    const OptStruct = struct {
        id: u32,
        tag: ?[]const u8 = null,
        count: ?u32 = null,
    };

    // All present
    const p1 = try zserde.json.fromSliceBorrowed(OptStruct, "{\"id\":1,\"tag\":\"alpha\",\"count\":42}");
    try testing.expectEqual(@as(u32, 1), p1.id);
    try testing.expectEqualStrings("alpha", p1.tag.?);
    try testing.expectEqual(@as(u32, 42), p1.count.?);

    // Null explicitly passed
    const p2 = try zserde.json.fromSliceBorrowed(OptStruct, "{\"id\":2,\"tag\":null,\"count\":null}");
    try testing.expectEqual(@as(u32, 2), p2.id);
    try testing.expect(p2.tag == null);
    try testing.expect(p2.count == null);

    // Missing entirely from JSON
    const p3 = try zserde.json.fromSliceBorrowed(OptStruct, "{\"id\":3}");
    try testing.expectEqual(@as(u32, 3), p3.id);
    try testing.expect(p3.tag == null);
    try testing.expect(p3.count == null);
}

test "json: escaped characters in strings" {
    const StringStruct = struct {
        text: []const u8,
    };

    const payload = "{\"text\":\"Hello\\nWorld\\t\\\"Quoted\\\"\\\\Backslash\"}";
    const parsed = try zserde.json.fromSliceBorrowed(StringStruct, payload);
    try testing.expect(parsed.text.len > 0);
}

test "json: unknown extra fields ignored safely" {
    const Strict = struct {
        id: u32,
    };

    const payload = "{\"extra_a\": \"ignore me\", \"id\": 999, \"extra_b\": [1, 2, 3], \"nested\": {\"foo\": \"bar\"}}";
    const parsed = try zserde.json.fromSliceBorrowed(Strict, payload);
    try testing.expectEqual(@as(u32, 999), parsed.id);
}

// ============================================================================
// 2. MessagePack Edge Cases & Roundtrips
// ============================================================================

test "msgpack: empty buffer returns error" {
    const Dummy = struct { id: u32 };
    try testing.expectError(error.UnexpectedEndOfInput, zserde.msgpack.fromSliceBorrowed(Dummy, ""));
}

test "msgpack: complex nested struct roundtrip" {
    const allocator = testing.allocator;

    const Inner = struct {
        ip: []const u8,
        port: u16,
    };
    const Outer = struct {
        service_id: u64,
        is_healthy: bool,
        endpoint: Inner,
        description: ?[]const u8 = null,
    };

    const origin = Outer{
        .service_id = 8848,
        .is_healthy = true,
        .endpoint = .{
            .ip = "127.0.0.1",
            .port = 8080,
        },
        .description = "Production gateway node",
    };

    const encoded = try zserde.msgpack.toSlice(allocator, origin);
    defer allocator.free(encoded);

    const decoded = try zserde.msgpack.fromSliceBorrowed(Outer, encoded);
    try testing.expectEqual(origin.service_id, decoded.service_id);
    try testing.expectEqual(origin.is_healthy, decoded.is_healthy);
    try testing.expectEqualStrings(origin.endpoint.ip, decoded.endpoint.ip);
    try testing.expectEqual(origin.endpoint.port, decoded.endpoint.port);
    try testing.expect(decoded.description != null);
    try testing.expectEqualStrings("Production gateway node", decoded.description.?);
}

test "msgpack: boolean values and zero numbers" {
    const allocator = testing.allocator;

    const Flags = struct {
        flag_a: bool,
        flag_b: bool,
        zero_val: u32,
    };

    const input = Flags{
        .flag_a = true,
        .flag_b = false,
        .zero_val = 0,
    };

    const encoded = try zserde.msgpack.toSlice(allocator, input);
    defer allocator.free(encoded);

    const decoded = try zserde.msgpack.fromSliceBorrowed(Flags, encoded);
    try testing.expectEqual(true, decoded.flag_a);
    try testing.expectEqual(false, decoded.flag_b);
    try testing.expectEqual(@as(u32, 0), decoded.zero_val);
}

// ============================================================================
// 3. CBOR Edge Cases & Roundtrips
// ============================================================================

test "cbor: empty buffer returns error" {
    const Dummy = struct { id: u32 };
    try testing.expectError(error.UnexpectedEndOfInput, zserde.cbor.fromSliceBorrowed(Dummy, ""));
}

test "cbor: roundtrip with floating point and integers" {
    const allocator = testing.allocator;

    const Telemetry = struct {
        device_id: u32,
        voltage: f64,
        temperature: f64,
        online: bool,
    };

    const origin = Telemetry{
        .device_id = 42,
        .voltage = 3.305,
        .temperature = -12.5,
        .online = true,
    };

    const encoded = try zserde.cbor.toSlice(allocator, origin);
    defer allocator.free(encoded);

    const decoded = try zserde.cbor.fromSliceBorrowed(Telemetry, encoded);
    try testing.expectEqual(origin.device_id, decoded.device_id);
    try testing.expectApproxEqAbs(origin.voltage, decoded.voltage, 0.001);
    try testing.expectApproxEqAbs(origin.temperature, decoded.temperature, 0.001);
    try testing.expectEqual(origin.online, decoded.online);
}

// ============================================================================
// 4. TOML Edge Cases & Roundtrips
// ============================================================================

test "toml: parsing with comments and whitespace" {
    const ServerConf = struct {
        host: []const u8,
        port: u16,
        enable_tls: bool,
    };

    const toml_text =
        \\# Main Server Configuration
        \\host = "192.168.1.100"   # local bind
        \\port = 443
        \\
        \\enable_tls = true
    ;

    const parsed = try zserde.toml.fromSliceBorrowed(ServerConf, toml_text);
    try testing.expectEqualStrings("192.168.1.100", parsed.host);
    try testing.expectEqual(@as(u16, 443), parsed.port);
    try testing.expectEqual(true, parsed.enable_tls);
}

test "toml: serialization roundtrip" {
    const allocator = testing.allocator;

    const AppInfo = struct {
        name: []const u8,
        version: []const u8,
        workers: u32,
    };

    const origin = AppInfo{
        .name = "auth-service",
        .version = "2.1.0",
        .workers = 16,
    };

    const toml_str = try zserde.toml.toSlice(allocator, origin);
    defer allocator.free(toml_str);

    const decoded = try zserde.toml.fromSliceBorrowed(AppInfo, toml_str);
    try testing.expectEqualStrings(origin.name, decoded.name);
    try testing.expectEqualStrings(origin.version, decoded.version);
    try testing.expectEqual(origin.workers, decoded.workers);
}

// ============================================================================
// 5. YAML Edge Cases & Indentation
// ============================================================================

test "yaml: parsing multi-line key-values with whitespace" {
    const DatabaseConfig = struct {
        adapter: []const u8,
        pool_size: u32,
        ssl: bool,
    };

    const yaml_input =
        \\adapter: postgresql
        \\pool_size: 20
        \\ssl: false
    ;

    const parsed = try zserde.yaml.fromSliceBorrowed(DatabaseConfig, yaml_input);
    try testing.expectEqualStrings("postgresql", parsed.adapter);
    try testing.expectEqual(@as(u32, 20), parsed.pool_size);
    try testing.expectEqual(false, parsed.ssl);
}

// ============================================================================
// 6. Schema Validator Comprehensive Rules
// ============================================================================

test "zschema: all validation rules (min, max, min_len, max_len, contains)" {
    const allocator = testing.allocator;

    const UserRegistration = struct {
        handle: []const u8,
        passcode: []const u8,
        score: u32,
        email_addr: []const u8,

        pub const zvalidate = .{
            .handle = .{ .min_len = 3, .max_len = 20 },
            .passcode = .{ .min_len = 8 },
            .score = .{ .min = 10, .max = 100 },
            .email_addr = .{ .contains = "@entropyparadox.com" },
        };
    };

    // Valid instance
    const valid_user = UserRegistration{
        .handle = "developer",
        .passcode = "super_secure_pass",
        .score = 85,
        .email_addr = "admin@entropyparadox.com",
    };
    var rep_valid = try zserde.validateWithReport(valid_user, allocator);
    defer rep_valid.deinit();
    try testing.expect(rep_valid.isValid());
    try testing.expectEqual(@as(usize, 0), rep_valid.violations.len);

    // Completely invalid instance (all 4 fields violate rules)
    const invalid_user = UserRegistration{
        .handle = "a", // < 3
        .passcode = "short", // < 8
        .score = 5, // < 10
        .email_addr = "fake@other.org", // missing domain
    };
    var rep_invalid = try zserde.validateWithReport(invalid_user, allocator);
    defer rep_invalid.deinit();
    try testing.expectEqual(false, rep_invalid.isValid());
    try testing.expectEqual(@as(usize, 4), rep_invalid.violations.len);
}
