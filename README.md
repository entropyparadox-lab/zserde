# zserde ⚡

**Zero-Allocation Multi-Format Serialization, SIMD Acceleration & Comptime Validation Toolkit for Zig (v0.16.0+)**

`zserde` is a high-performance, pure Zig serialization and validation framework modeled after Rust's `serde` and Python's `pydantic`. It uses Zig's compile-time reflection (`@typeInfo`) and native SIMD vectors (`@Vector(16, u8)`) to deliver zero-overhead, format-agnostic data modeling with zero heap allocations for borrowed data types across **JSON**, **MessagePack**, and **TOML**.

---

## Benchmark Highlights (AMD Ryzen / ReleaseFast, 500,000 runs)

| Format / Codec | Throughput (ops/sec) | Throughput (MB/s) | Allocations |
| :--- | :--- | :--- | :--- |
| **`zserde MsgPack` (Zero-Copy)** | **34.8 Million ops/sec** | **~3,260 MB/s** | **0 bytes (Zero-Alloc)** |
| **`zserde JSON` (Zero-Copy + SIMD)** | **7.44 Million ops/sec** | **~837 MB/s** | **0 bytes (Zero-Alloc)** |

---

## Key Features

- ⚡ **Multi-Format Support**:
  - **JSON**: Full spec support with SIMD-accelerated whitespace scanning and zero-copy slice borrowing.
  - **MessagePack (`msgpack`)**: High-throughput binary RPC format with ~40% size reduction over JSON.
  - **TOML (`toml`)**: Native configuration parsing with table sections `[section]` and scalar mapping.
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

    // 2. JSON Serialization (jobId, taskName, maxRetryCount in camelCase)
    const json_str = try zserde.json.toSlice(allocator, job, .{ .pretty = true });
    defer allocator.free(json_str);

    // 3. MessagePack Binary Encoding (Zero-Copy)
    const mp_bytes = try zserde.msgpack.toSlice(allocator, job);
    defer allocator.free(mp_bytes);
    const parsed_mp = try zserde.msgpack.fromSliceBorrowed(JobPayload, mp_bytes);
}
```

---

## Running Tests & Benchmarks

```bash
# Run unit & integration tests
zig build test

# Run interactive example
zig build run-example

# Run high-throughput microbenchmark suite
zig build bench
```

---

## License

MIT License © 2026 EntropyParadox Lab
