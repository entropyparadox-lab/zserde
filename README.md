# zserde ⚡

**Zero-Allocation Multi-Format Serialization, SIMD Acceleration & Comptime Validation Toolkit for Zig (v0.16.0+)**

`zserde` is an enterprise-grade, pure Zig serialization and validation framework modeled after Rust's `serde` and Python's `pydantic`. It leverages Zig's compile-time reflection (`@typeInfo`) and native SIMD vector instructions (`@Vector(16, u8)`) to deliver unified data modeling with zero heap allocations for borrowed data types across **JSON**, **MessagePack**, **CBOR**, **TOML**, and **YAML**.

---

## Benchmark Highlights (AMD Ryzen / ReleaseFast, 500,000 runs)

| Format / Codec | Mode | Throughput (ops/sec) | Throughput (MB/s) | Allocations |
| :--- | :--- | :--- | :--- | :--- |
| **`zserde MsgPack`** | Binary Zero-Copy | **37.4 Million ops/sec** | **~3,500 MB/s** | **0 bytes (Zero-Alloc)** |
| **`zserde CBOR`** | Binary Zero-Copy | **35.1 Million ops/sec** | **~3,300 MB/s** | **0 bytes (Zero-Alloc)** |
| **`zserde JSON`** | Text Zero-Copy + SIMD | **7.67 Million ops/sec** | **~863 MB/s** | **0 bytes (Zero-Alloc)** |

---

## Key Features

- ⚡ **5-in-1 Unified Multi-Format Codecs**:
  - **JSON (`zserde.json`)**: Full spec support with SIMD-accelerated whitespace scanning and pretty-printing.
  - **MessagePack (`zserde.msgpack`)**: High-throughput binary RPC format with ~40% size reduction over JSON.
  - **CBOR (`zserde.cbor`)**: Standard RFC 8949 binary serialization for IoT, WebAuthn/FIDO2, and embedded systems.
  - **TOML (`zserde.toml`)**: Configuration parsing with table sections `[section]` and scalar mapping.
  - **YAML (`zserde.yaml`)**: Clean, human-readable indented document serialization.
- 🚀 **Zero-Allocation Deserialization (`fromSliceBorrowed`)**: Parse payloads directly borrowing string/binary slices from the input buffer without touching the heap.
- 🛠️ **In-Place Buffer Mutation (`unescapeInPlace`)**: Unescape JSON control characters (`\n`, `\t`, `\"`) in-place without heap allocations.
- 🎯 **Comptime Struct Metadata (`pub const zserde`)**:
  - Global naming conversion: `rename_all = .camelCase`, `.kebab_case`, `.snake_case`, `.PascalCase`.
  - Granular field renaming: `.rename = .{ .field_name = "customKey" }`.
  - Sensitive field skipping: `.skip = .{ .password = true }`.
  - Call-site configuration override (`toSliceWithConfig`) for unowned third-party struct types.
- 🛡️ **Comptime Schema Validation (`pub const zvalidate` / `zserde.validate`)**:
  - Numeric range bounds (`min`, `max`).
  - String constraints (`min_len`, `max_len`, `contains`, `starts_with`, `ends_with`).
  - Optional field validation (skips `null`, validates if `?T` has value).
  - Zero runtime reflection cost — validation checks compile directly into branch instructions.
- 📦 **Pure Zig 0.16.0+**: Zero C dependencies, instant build times, fully cross-compilable.

---

## Installation (`build.zig.zon`)

Add `zserde` to your `build.zig.zon`:

```bash
zig fetch --save https://github.com/entropyparadox-lab/zserde/archive/refs/tags/v1.0.0.tar.gz
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

const JobPayload = struct {
    job_id: u32,
    task_name: []const u8,
    max_retry_count: u8,
    secret_token: []const u8,

    // Comptime metadata
    pub const zserde = .{
        .rename_all = .camelCase,
        .skip = .{ .secret_token = true },
    };

    // Comptime schema validation
    pub const zvalidate = .{
        .task_name = .{ .min_len = 3, .starts_with = "task_" },
        .max_retry_count = .{ .min = 1, .max = 10 },
    };
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    const job = JobPayload{
        .job_id = 77,
        .task_name = "task_sync_db",
        .max_retry_count = 3,
        .secret_token = "tok_hidden",
    };

    // 1. Schema Validation (Zero-overhead comptime checks)
    try zserde.validate(job);

    // 2. JSON Serialization
    const json_str = try zserde.json.toSlice(allocator, job, .{ .pretty = true });
    defer allocator.free(json_str);

    // 3. MessagePack Binary Encoding (Zero-Copy)
    const mp_bytes = try zserde.msgpack.toSlice(allocator, job);
    defer allocator.free(mp_bytes);
    const parsed_mp = try zserde.msgpack.fromSliceBorrowed(JobPayload, mp_bytes);

    // 4. CBOR Binary Encoding (Zero-Copy)
    const cbor_bytes = try zserde.cbor.toSlice(allocator, job);
    defer allocator.free(cbor_bytes);
    const parsed_cbor = try zserde.cbor.fromSliceBorrowed(JobPayload, cbor_bytes);

    // 5. TOML / YAML Config Serialization
    const toml_str = try zserde.toml.toSlice(allocator, job);
    defer allocator.free(toml_str);
    const yaml_str = try zserde.yaml.toSlice(allocator, job);
    defer allocator.free(yaml_str);
}
```

---

## Running Tests & Benchmarks

```bash
# Run unit & integration tests across all formats
zig build test

# Run multi-format demo
zig build run-example

# Run high-throughput microbenchmark suite
zig build bench
```

---

## Roadmap Status

- [x] **v0.1.0**: JSON Serializer, Zero-copy Deserializer, Comptime Field Options (`rename`, `skip`), Comptime Schema Validation.
- [x] **v0.2.0**: MessagePack binary encoder/decoder, TOML config serializer/deserializer, optional validation rules.
- [x] **v0.3.0**: Native SIMD `@Vector(16, u8)` scanning, `rename_all` conventions, in-place unescape, call-site overrides.
- [x] **v1.0.0**: CBOR binary (RFC 8949), YAML parser/serializer, comprehensive 5-format test & microbenchmark suite.

---

## License

MIT License © 2026 EntropyParadox Lab
