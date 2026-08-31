# Changelog

All notable changes to `zserde` will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.1] - 2026-09-01

### Fixed
- **Recursive Optional Validation**: Fixed missing validation on optional nested struct fields (`?ServerConfig`).
- **TOML & YAML Section Mapping**: Added support for optional nested struct sections in TOML `[section]` and YAML `section:` headers.
- **CBOR RFC 8949**: Added support for `undefined (0xf7)` marker handling alongside `null (0xf6)`.
- **JSON Escape Safety**: Added early bounds escape sequence check in `deserializer.zig`.

### Added
- **Structured Validation Reports**: Introduced `validateWithReport(value, allocator)` returning `ValidationReport` with field names and error codes.

---

## [1.0.0] - 2026-09-01

### Added
- **5-in-1 Unified Codecs**: Full support for JSON, MessagePack, CBOR (RFC 8949), TOML, and YAML.
- **SIMD Acceleration**: `@Vector(16, u8)` accelerated string quote and whitespace scanning.
- **Naming Conventions**: Automatic Comptime `rename_all` (.camelCase, .kebab_case, .PascalCase).
- **In-Place Compaction**: `unescapeInPlace` for zero-allocation JSON string unescaping.
- **Call-Site Configuration**: `toSliceWithConfig` for overriding settings on unowned 3rd-party structs.
- **Microbenchmarking Suite**: `zig build bench` harness measuring ops/sec and MB/s throughput.

---

## [0.1.0] - 2026-09-01

### Added
- Initial release with JSON serializer/deserializer and basic Comptime validation.
