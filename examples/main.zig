const std = @import("std");
const zserde = @import("zserde");

const ServerConfig = struct {
    bind_ip: []const u8 = "0.0.0.0",
    port: u16 = 8080,
};

const ServiceManifest = struct {
    service_name: []const u8,
    version: []const u8,
    replicas: u32,
    internal_token: []const u8,
    server: ServerConfig,

    pub const zserde = .{
        .rename = .{
            .service_name = "serviceName",
        },
        .skip = .{
            .internal_token = true,
        },
    };

    pub const zvalidate = .{
        .service_name = .{ .min_len = 3, .max_len = 32 },
        .replicas = .{ .min = 1, .max = 100 },
    };
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    std.debug.print("\n=================================================================================\n", .{});
    std.debug.print("  ⚡ zserde v1.0.1: Unified Multi-Format Serialization & Validation for Zig\n", .{});
    std.debug.print("=================================================================================\n\n", .{});

    const manifest = ServiceManifest{
        .service_name = "auth-gateway",
        .version = "1.0.1",
        .replicas = 8,
        .internal_token = "tok_super_secret_never_leak",
        .server = .{
            .bind_ip = "127.0.0.1",
            .port = 9090,
        },
    };

    // 1. Compile-Time Schema Validation
    try zserde.validate(manifest);
    std.debug.print("✅ 1. [Schema Validation] Passed (replicas: {}, service: {s})\n\n", .{
        manifest.replicas,
        manifest.service_name,
    });

    // 2. JSON Serialization
    const json_data = try zserde.json.toSlice(allocator, manifest, .{ .pretty = true });
    defer allocator.free(json_data);
    std.debug.print("📄 2. [JSON Serialization] (internal_token skipped, serviceName renamed):\n{s}\n\n", .{json_data});

    // 3. MessagePack Binary Encoding & Zero-Copy Decoding
    const msgpack_bytes = try zserde.msgpack.toSlice(allocator, manifest);
    defer allocator.free(msgpack_bytes);
    const decoded_mp = try zserde.msgpack.fromSliceBorrowed(ServiceManifest, msgpack_bytes);
    std.debug.print("📦 3. [MessagePack Binary] Size: {} bytes (JSON: {} bytes, {d:.1}% reduction)\n", .{
        msgpack_bytes.len,
        json_data.len,
        (1.0 - @as(f64, @floatFromInt(msgpack_bytes.len)) / @as(f64, @floatFromInt(json_data.len))) * 100.0,
    });
    std.debug.print("   -> Decoded from MsgPack: service={s}, port={d}\n\n", .{
        decoded_mp.service_name,
        decoded_mp.server.port,
    });

    // 4. CBOR Binary Encoding & Zero-Copy Decoding
    const cbor_bytes = try zserde.cbor.toSlice(allocator, manifest);
    defer allocator.free(cbor_bytes);
    const decoded_cbor = try zserde.cbor.fromSliceBorrowed(ServiceManifest, cbor_bytes);
    std.debug.print("🔷 4. [CBOR Binary RFC-8949] Size: {} bytes\n", .{cbor_bytes.len});
    std.debug.print("   -> Decoded from CBOR: service={s}, replicas={d}\n\n", .{
        decoded_cbor.service_name,
        decoded_cbor.replicas,
    });

    // 5. TOML Configuration Serialization
    const toml_data = try zserde.toml.toSlice(allocator, manifest);
    defer allocator.free(toml_data);
    std.debug.print("⚙️  5. [TOML Config Output]:\n{s}\n", .{toml_data});

    // 6. YAML Configuration Serialization
    const yaml_data = try zserde.yaml.toSlice(allocator, manifest);
    defer allocator.free(yaml_data);
    std.debug.print("📜 6. [YAML Document Output]:\n{s}\n", .{yaml_data});

    std.debug.print("🎉 All 5 formats (JSON, MsgPack, CBOR, TOML, YAML) validated successfully!\n\n", .{});
}
