# Contributing to zserde ⚡

Thank you for your interest in contributing to `zserde`!

## Development Workflow

### 1. Requirements
* **Zig `0.16.0+`** (Master or latest official release).

### 2. Setup Local Git Hooks
Run the hook setup script to configure automated format and test verification before each commit:
```bash
./scripts/setup-hooks.sh
```

### 3. Running Verification Commands
Before submitting a PR, make sure all gates pass:
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

## Branching & Release Strategy

We follow **GitHub Flow** (Trunk-based development):

* `main`: Protected production branch. All changes land here via reviewed Pull Requests.
* `feat/<name>`: Feature branch (e.g. `feat/cbor-tag-support`).
* `fix/<name>`: Bug fix branch (e.g. `fix/yaml-indent-edge-case`).
* `perf/<name>`: Benchmark and performance optimizations.
* `docs/<name>`: Documentation improvements.

## Commit Message Guidelines

We enforce **Conventional Commits**:
* `feat(scope): add new feature`
* `fix(scope): fix bug`
* `docs(scope): documentation update`
* `perf(scope): performance optimization`
* `test(scope): add or update test suites`
* `chore(release): bump version`

## Versioning Policy

`zserde` strictly follows [Semantic Versioning (SemVer 2.0.0)](https://semver.org):
* **PATCH (`x.y.Z`)**: Bug fixes, performance improvements, documentation updates.
* **MINOR (`x.Y.z`)**: New formats, new validation rules, backwards-compatible API additions.
* **MAJOR (`X.y.z`)**: Breaking API alterations.

Whenever bumping version:
1. Update `.version = "x.y.z"` in `build.zig.zon`.
2. Update version badge and install commands in `README.md`.
3. Add release notes to `CHANGELOG.md`.
4. Cut an annotated git tag `git tag -a vx.y.z -m "Release vx.y.z"`.
