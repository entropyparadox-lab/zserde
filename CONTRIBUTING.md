# Contributing to zserde ⚡

Thank you for contributing to `zserde`! To maintain the highest reliability, performance, and community trust in the Zig ecosystem, we follow strict quality guidelines.

---

## 1. Compiler Versioning & Branch Strategy

Zig standard library evolves rapidly. We maintain a strict **Dual-Branch Strategy**:

* **`main` (Protected)**: Targets **Official Stable Zig (`0.16.x`)**. All production releases (`vX.Y.Z`) are cut exclusively from `main`.
* **`zig-master`**: Tracks upstream `ziglang/zig` nightly builds to prepare for upcoming breaking changes in advance.
* **`feat/<name>` / `fix/<name>`**: Branch off `main` for stable changes, or off `zig-master` for nightly-only fixes.

---

## 2. Strict Quality & Verification Gate

In alignment with the Zig Software Foundation community standards:

1. **100% Tested & Verified**: Every PR must include reproducible test coverage (`zig build test`). Unverified code submissions or untested AI-generated patches will be rejected.
2. **Zero-Allocation Invariant**: Codec parsing methods ending in `Borrowed` (`fromSliceBorrowed`) must **NEVER** allocate heap memory under any circumstance.
3. **No Regressions**: Benchmark throughput (`zig build bench`) must not degrade.

---

## 3. Fast Local Development & Git Hooks

Install the lightweight local pre-commit hook (<0.3s fast feedback):
```bash
./scripts/setup-hooks.sh
```

Before opening a PR, run full local verification:
```bash
# 1. Format code
zig fmt src/ examples/ tests/ build.zig

# 2. Run unit & integration tests
zig build test

# 3. Run multi-format example
zig build run-example

# 4. Verify benchmark throughput
zig build bench
```

---

## 4. Immutable Release & SemVer Policy

* **Semantic Versioning (SemVer 2.0.0)**:
  * `PATCH (1.0.X)`: Bug fixes, parser edge cases, documentation.
  * `MINOR (1.X.0)`: New codecs, new validation attributes, backwards-compatible additions.
  * `MAJOR (X.0.0)`: Breaking API changes.
* **Tag Immutability Principle**:
  * **Never modify or delete a published Git tag.**
  * Zig package manager relies on strict content multihashes (`.hash`). Altering a tagged release corrupts downstream user builds. Any typo or hotfix requires an immediate next patch bump (`v1.0.2`).

---

## 5. Commit Message Format

We strictly enforce **Conventional Commits**:
```
<type>(<scope>): <subject>

Examples:
  feat(cbor): add RFC-8949 undefined marker support
  fix(yaml): resolve nested optional section mapping
  perf(json): optimize SIMD quote scan loop
  docs: add std.json migration matrix
```
