# zserde ⚡

[![Zig Version](https://img.shields.io/badge/Zig-0.16.0%2B-orange.svg)](https://ziglang.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Zero Allocations](https://img.shields.io/badge/Zero--Copy-Borrowed%20Slices-brightgreen.svg)]()
[![Codecs](https://img.shields.io/badge/5--in--1-JSON%20|%20MsgPack%20|%20CBOR%20|%20TOML%20|%20YAML-purple.svg)]()

**Zero-Allocation Multi-Format Serialization & Comptime Validation for Zig (v0.16.0+)**

`zserde` gives Zig developers the ergonomic power of Rust's `serde` and Python's `pydantic`. It provides **zero-copy deserialization**, **comptime struct reflection**, and **zero-cost schema validation** across **JSON, MessagePack, CBOR, TOML, and YAML** with 100% pure Zig and zero C dependencies.

---

## Why zserde vs std.json?

| Feature | `std.json` (Stdlib) | `zserde` ⚡ |
| :--- | :--- | :--- |
| **Supported Formats** | JSON only | **5-in-1**: JSON, MessagePack, CBOR (RFC 8949), TOML, YAML |
| **Zero-Allocation Mode** | Requires `Parsed(T)` wrapper + deinit | Direct struct return (`fromSliceBorrowed`) with **0 heap bytes** |
| **Field Renaming** | Manual mapping | Comptime `rename` or `rename_all = .camelCase` |
| **Sensitive Field Hiding**| Manual exclusion | Declarative `skip = .{ .password = true }` |
| **Validation Engine** | None (manual `if` checks) | Comptime-synthesized rules (`min`, `max`, `starts_with`, etc.) |
| **SIMD Acceleration** | Scalar loops | `@Vector(16, u8)` accelerated scanning (~840 MB/s JSON, ~3.5 GB/s MsgPack) |
| **Third-Party Structs** | Boilerplate wrapper structs | Call-site config override (`toSliceWithConfig`) |

---

## Installation (30 Seconds)

### 1. Fetch package into `build.zig.zon`

```bash
zig fetch --save https://github.com/entropyparadox-lab/zserde/archive/refs/tags/v1.0.0.tar.gz
```

### 2. Add module in your `build.zig`

```zig
const zserde_dep = b.dependency("zserde", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zserde", zserde_dep.module("zserde"));
```

---

## Quick Reference API Matrix

| Goal | Function Signature | Memory Requirement |
| :--- | :--- | :--- |
| **Zero-Copy Parse** | `zserde.<format>.fromSliceBorrowed(T, bytes)` | **0 bytes** (borrows string slices directly) |
| **Allocating Parse** | `zserde.<format>.fromSlice(T, allocator, bytes)` | Duplicates strings & allocates dynamic arrays |
| **Serialize to Slice**| `zserde.<format>.toSlice(allocator, value)` | Caller owns returned `[]u8` slice |
| **In-Place Unescape** | `zserde.json.unescapeInPlace(mutable_buf)` | **0 bytes** (in-place compacting without heap) |
| **Validate Struct** | `zserde.validate(value)` | **0 bytes** (Comptime-generated assertions) |

*(Replace `<format>` with `json`, `msgpack`, `cbor`, `toml`, or `yaml`)*

---

## Practical Developer Recipes

### 1. Zero-Copy JSON Parsing (No Memory Allocator Needed)

```zig
const std = @import("std");
const zserde = @import("zserde");

const User = struct {
    id: u64,
    username: []const u8, // Borrowed directly from input buffer!
    is_admin: bool,
};

pub fn main() !void {
    const raw_json = "{\"id\": 101, \"username\": \"alice\", \"is_admin\": true}";
    
    // No allocator required! Returns User struct with slices pointing into raw_json.
    const user = try zserde.json.fromSliceBorrowed(User, raw_json);
    
    std.debug.print("User: {s} (ID: {d})\n", .{ user.username, user.id });
}
```

---

### 2. Automatic CamelCase Renaming & Secret Masking

```zig
const DatabaseConfig = struct {
    host: []const u8,
    port: u16 = 5432,
    max_connections: u32 = 20,
    secret_password: []const u8,

    // Declarative Comptime Metadata
    pub const zserde = .{
        .rename_all = .camelCase,              // max_connections -> "maxConnections"
        .skip = .{ .secret_password = true },  // never serialized to output
    };
};

// Serializes to: {"host":"localhost","port":5432,"maxConnections":20}
```

---

### 3. High-Throughput Binary Formats (MessagePack & CBOR)

When microsecond latency or bandwidth matters (Game networking, IPC, Redis, IoT):

```zig
const Telemetry = struct {
    device_id: u32,
    voltage: f64,
    active: bool,
};

const data = Telemetry{ .device_id = 992, .voltage = 3.31, .active = true };

// MessagePack (~40% smaller than JSON)
const mp_bytes = try zserde.msgpack.toSlice(allocator, data);
defer allocator.free(mp_bytes);
const decoded_mp = try zserde.msgpack.fromSliceBorrowed(Telemetry, mp_bytes);

// CBOR (RFC 8949 / IoT & WebAuthn standard)
const cbor_bytes = try zserde.cbor.toSlice(allocator, data);
defer allocator.free(cbor_bytes);
const decoded_cbor = try zserde.cbor.fromSliceBorrowed(Telemetry, cbor_bytes);
```

---

### 4. Zero-Overhead Comptime Validation (`zvalidate`)

Validation checks compile directly into raw branch instructions with **zero runtime reflection**:

```zig
const Registration = struct {
    username: []const u8,
    age: ?u32, // Optional fields are validated ONLY if not null
    email: []const u8,

    pub const zvalidate = .{
        .username = .{ .min_len = 3, .max_len = 24, .starts_with = "user_" },
        .age = .{ .min = 18, .max = 120 },
        .email = .{ .contains = "@", .ends_with = ".com" },
    };
};

const input = Registration{
    .username = "user_bob",
    .age = 25,
    .email = "bob@corp.com",
};

// Returns error.ValueTooSmall / error.PatternMismatch if invalid
try zserde.validate(input);
```

---

### 5. Third-Party Struct Overrides (Call-Site Config)

If you're using a struct from an external library that you cannot edit:

```zig
const ExternalItem = struct {
    item_id: u32,
    stock_count: u32,
};

const item = ExternalItem{ .item_id = 12, .stock_count = 500 };

// Override at call-site without wrapping the struct
const json_str = try zserde.json.toSliceWithConfig(allocator, item, .{}, .{
    .rename_all = .camelCase,
});
// Outputs: {"itemId":12,"stockCount":500}
```

---

## Performance Benchmarks (AMD Ryzen / ReleaseFast)

```
=========================================================================
  ⚡ zserde High-Throughput Microbenchmark (500,000 runs)
=========================================================================

🚀 1. zserde JSON (Zero-Copy + SIMD):
   - Speed: 7.67 Million ops/sec (~863 MB/s)
   - Allocations: 0 bytes

📦 2. zserde MessagePack (Zero-Copy Binary):
   - Speed: 37.4 Million ops/sec (~3,500 MB/s)
   - Allocations: 0 bytes

🔷 3. zserde CBOR (Zero-Copy Binary RFC-8949):
   - Speed: 35.1 Million ops/sec (~3,300 MB/s)
   - Allocations: 0 bytes
```

To run benchmarks on your own hardware:
```bash
zig build bench
```

---

## License

MIT License © 2026 EntropyParadox Lab
