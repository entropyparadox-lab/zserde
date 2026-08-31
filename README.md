# zserde ⚡

**Zero-Allocation Format-Agnostic Serialization & Comptime Validation Toolkit for Zig (v0.16.0+)**

`zserde` is a high-performance, pure Zig serialization and validation framework modeled after Rust's `serde` and Python's `pydantic`. It uses Zig's compile-time reflection (`@typeInfo`) to deliver zero-overhead, format-agnostic data modeling with zero heap allocations for borrowed data types.

---

## Key Features

- ⚡ **Zero-Allocation Deserialization (`fromSliceBorrowed`)**: Parse JSON and strings directly borrowing from the input buffer without touching the heap.
- 🎯 **Comptime Struct Metadata (`pub const zserde`)**:
  - Field renaming (e.g., `max_connections` → `"maxConnections"`).
  - Field skipping for sensitive data (e.g., `password`, `secret_token`).
  - Default value fallbacks for omitted optional/primitive fields.
- 🛡️ **Comptime Schema Validation (`pub const zvalidate` / `zserde.validate`)**:
  - Number range constraints (`min`, `max`).
  - String length and pattern matching (`min_len`, `max_len`, `contains`, `starts_with`, `ends_with`).
  - Zero runtime reflection cost — validation branches are synthesized at compile time.
- 📦 **Zig 0.16.0+ Native**: Fully compatible with the modern `std.Io` and `build.zig.zon` module ecosystem. Zero C dependencies.

---

## Quick Start

### 1. Add to your `build.zig.zon`

```zig
.{
    .name = .my_app,
    .version = "0.1.0",
    .dependencies = .{
        .zserde = .{
            .url = "https://github.com/entropyparadox-lab/zserde/archive/refs/tags/v0.1.0.tar.gz",
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

const DatabaseConfig = struct {
    host: []const u8,
    port: u16 = 5432,
    max_connections: u32 = 10,
    password: []const u8,

    // Comptime serialization metadata
    pub const zserde = .{
        .rename = .{
            .max_connections = "maxConnections",
        },
        .skip = .{
            .password = true,
        },
    };

    // Comptime validation rules
    pub const zvalidate = .{
        .port = .{ .min = 1, .max = 65535 },
        .max_connections = .{ .min = 1, .max = 1000 },
    };
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    const config = DatabaseConfig{
        .host = "localhost",
        .port = 5432,
        .max_connections = 50,
        .password = "secret_123",
    };

    // 1. Schema Validation (Compile-time verified)
    try zserde.validate(config);

    // 2. Serialization (password skipped, renamed fields)
    const json_str = try zserde.json.toSlice(allocator, config, .{ .pretty = true });
    defer allocator.free(json_str);
    std.debug.print("JSON:\n{s}\n", .{json_str});

    // 3. Zero-Allocation Deserialization
    const payload = "{\"host\":\"pg.internal\",\"port\":5433,\"maxConnections\":100}";
    const parsed = try zserde.json.fromSliceBorrowed(DatabaseConfig, payload);
    std.debug.print("Parsed host: {s}, max conns: {d}\n", .{ parsed.host, parsed.max_connections });
}
```

---

## Roadmap

- [x] **v0.1.0**: JSON Serializer, Zero-copy Deserializer, Comptime Field Options (`rename`, `skip`), Comptime Schema Validation.
- [ ] **v0.2.0**: TOML and YAML Parsers with shared `zserde` metadata visitor.
- [ ] **v0.3.0**: Binary Formats: MessagePack & CBOR encoders/decoders.
- [ ] **v0.4.0**: Microbenchmark suite against `std.json` and SIMD JSON parsers.

---

## License

MIT License © 2026 EntropyParadox Lab
