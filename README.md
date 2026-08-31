# zserde ⚡

**Zero-Allocation Multi-Format Serialization & Comptime Validation Toolkit for Zig (v0.16.0+)**

`zserde` is a high-performance, pure Zig serialization and validation framework modeled after Rust's `serde` and Python's `pydantic`. It uses Zig's compile-time reflection (`@typeInfo`) to deliver zero-overhead, format-agnostic data modeling with zero heap allocations for borrowed data types across **JSON**, **MessagePack**, and **TOML**.

---

## Key Features

- ⚡ **Multi-Format Support**:
  - **JSON**: Full spec support with zero-copy slice borrowing and pretty-printing.
  - **MessagePack (`msgpack`)**: High-throughput binary RPC format with ~40% size reduction over JSON.
  - **TOML (`toml`)**: Native configuration parsing with table sections `[section]` and scalar mapping.
- 🚀 **Zero-Allocation Deserialization (`fromSliceBorrowed`)**: Parse payloads directly borrowing string/binary slices from the input buffer without touching the heap.
- 🎯 **Comptime Struct Metadata (`pub const zserde`)**:
  - Field renaming (e.g., `service_name` → `"serviceName"`).
  - Field skipping for sensitive data (e.g., `password`, `internal_token`).
  - Automatic fallback to struct default values for omitted optional or primitive fields.
- 🛡️ **Comptime Schema Validation (`pub const zvalidate` / `zserde.validate`)**:
  - Numeric range bounds (`min`, `max`).
  - String constraints (`min_len`, `max_len`, `contains`, `starts_with`, `ends_with`).
  - Optional field validation (skips `null`, validates if `?T` has value).
  - Zero runtime reflection cost — validation checks compile directly into branch instructions.
- 📦 **Pure Zig 0.16.0+**: Zero C dependencies, instant build times, fully cross-compilable.

---

## Quick Start

### 1. Add to your `build.zig.zon`

```zig
.{
    .name = .my_app,
    .version = "0.1.0",
    .dependencies = .{
        .zserde = .{
            .url = "https://github.com/entropyparadox-lab/zserde/archive/refs/tags/v0.2.0.tar.gz",
            .hash = "...",
        },
    },
}
```

In your `build.zig`:
```zig
const zserde_dep = b.dependency("zserde", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zserde", zserde_dep.module("zserde"));
```

---

## Usage Example

```zig
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
        .rename = .{ .service_name = "serviceName" },
        .skip = .{ .internal_token = true },
    };

    pub const zvalidate = .{
        .service_name = .{ .min_len = 3, .max_len = 32 },
        .replicas = .{ .min = 1, .max = 100 },
    };
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    const manifest = ServiceManifest{
        .service_name = "auth-gateway",
        .version = "2.1.0",
        .replicas = 8,
        .internal_token = "tok_super_secret_never_leak",
        .server = .{ .bind_ip = "127.0.0.1", .port = 9090 },
    };

    // 1. Schema Validation (Zero-overhead comptime checks)
    try zserde.validate(manifest);

    // 2. JSON Serialization
    const json_data = try zserde.json.toSlice(allocator, manifest, .{ .pretty = true });
    defer allocator.free(json_data);

    // 3. MessagePack Binary Encoding (Zero-Copy)
    const msgpack_bytes = try zserde.msgpack.toSlice(allocator, manifest);
    defer allocator.free(msgpack_bytes);
    const decoded_mp = try zserde.msgpack.fromSliceBorrowed(ServiceManifest, msgpack_bytes);

    // 4. TOML Config Serialization
    const toml_data = try zserde.toml.toSlice(allocator, manifest);
    defer allocator.free(toml_data);
}
```

---

## Roadmap

- [x] **v0.1.0**: JSON Serializer, Zero-copy Deserializer, Comptime Field Options (`rename`, `skip`), Comptime Schema Validation.
- [x] **v0.2.0**: MessagePack binary encoder/decoder, TOML config serializer/deserializer, optional validation rules.
- [ ] **v0.3.0**: CBOR binary encoding, YAML parser adapter.
- [ ] **v0.4.0**: Microbenchmark suite against `std.json` and SIMD JSON parsers.

---

## License

MIT License © 2026 EntropyParadox Lab
