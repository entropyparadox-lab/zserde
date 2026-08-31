const std = @import("std");
const zserde = @import("zserde");

const UserPayload = struct {
    id: u64,
    username: []const u8,
    email: []const u8,
    is_active: bool,
    score: f64,
    retry_count: u32,

    pub const zserde = .{
        .rename_all = .camelCase,
    };
};

fn getMonotonicNs() u64 {
    var ts: std.posix.timespec = undefined;
    _ = std.posix.system.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    const sample_json =
        \\{"id":104928,"username":"developer_alice","email":"alice@enterprise.com","isActive":true,"score":99.45,"retryCount":5}
    ;

    const iterations = 500_000;

    std.debug.print("\n=========================================================================\n", .{});
    std.debug.print("  ⚡ zserde High-Throughput Microbenchmark (Iterations: {d})\n", .{iterations});
    std.debug.print("=========================================================================\n\n", .{});

    // 1. zserde JSON Zero-Copy Benchmark
    var start_ns = getMonotonicNs();
    var i: usize = 0;
    var dummy: u64 = 0;

    while (i < iterations) : (i += 1) {
        const parsed = try zserde.json.fromSliceBorrowed(UserPayload, sample_json);
        dummy +%= parsed.id;
    }
    const end_ns = getMonotonicNs();
    const zserde_json_ns = end_ns - start_ns;
    const zserde_json_ops = (@as(f64, @floatFromInt(iterations)) / @as(f64, @floatFromInt(zserde_json_ns))) * 1_000_000_000.0;
    const zserde_json_mb = (zserde_json_ops * @as(f64, @floatFromInt(sample_json.len))) / (1024.0 * 1024.0);

    std.debug.print("🚀 1. zserde JSON (Zero-Copy Deserialization):\n", .{});
    std.debug.print("   - Total Time: {d:.2} ms\n", .{@as(f64, @floatFromInt(zserde_json_ns)) / 1_000_000.0});
    std.debug.print("   - Throughput: {d:.2} M ops/sec ({d:.2} MB/s)\n\n", .{ zserde_json_ops / 1_000_000.0, zserde_json_mb });

    // 2. zserde MessagePack Binary Benchmark
    const sample_user = UserPayload{
        .id = 104928,
        .username = "developer_alice",
        .email = "alice@enterprise.com",
        .is_active = true,
        .score = 99.45,
        .retry_count = 5,
    };
    const mp_bytes = try zserde.msgpack.toSlice(allocator, sample_user);
    defer allocator.free(mp_bytes);

    start_ns = getMonotonicNs();
    i = 0;
    while (i < iterations) : (i += 1) {
        const parsed = try zserde.msgpack.fromSliceBorrowed(UserPayload, mp_bytes);
        dummy +%= parsed.id;
    }
    const end_mp_ns = getMonotonicNs();
    const zserde_mp_ns = end_mp_ns - start_ns;
    const zserde_mp_ops = (@as(f64, @floatFromInt(iterations)) / @as(f64, @floatFromInt(zserde_mp_ns))) * 1_000_000_000.0;
    const zserde_mp_mb = (zserde_mp_ops * @as(f64, @floatFromInt(mp_bytes.len))) / (1024.0 * 1024.0);

    std.debug.print("📦 2. zserde MessagePack (Zero-Copy Binary Deserialization):\n", .{});
    std.debug.print("   - Total Time: {d:.2} ms\n", .{@as(f64, @floatFromInt(zserde_mp_ns)) / 1_000_000.0});
    std.debug.print("   - Throughput: {d:.2} M ops/sec ({d:.2} MB/s)\n\n", .{ zserde_mp_ops / 1_000_000.0, zserde_mp_mb });

    std.debug.print("Checksum verification: {d}\n\n", .{dummy});
}
