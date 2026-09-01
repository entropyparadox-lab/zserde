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

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const io = init.io;

    const sample_json =
        \\{"id":104928,"username":"developer_alice","email":"alice@enterprise.com","isActive":true,"score":99.45,"retryCount":5}
    ;

    const iterations = 500_000;

    std.debug.print("\n=========================================================================\n", .{});
    std.debug.print("  ⚡ zserde High-Throughput Microbenchmark (Iterations: {d})\n", .{iterations});
    std.debug.print("=========================================================================\n\n", .{});

    // 1. zserde JSON Zero-Copy Benchmark
    const start_json_ts = std.Io.Clock.awake.now(io);
    var i: usize = 0;
    var dummy: u64 = 0;

    while (i < iterations) : (i += 1) {
        const parsed = try zserde.json.fromSliceBorrowed(UserPayload, sample_json);
        dummy +%= parsed.id;
    }
    const end_json_ts = std.Io.Clock.awake.now(io);
    const zserde_json_duration = start_json_ts.durationTo(end_json_ts);
    const zserde_json_ns: u64 = @intCast(@max(1, zserde_json_duration.nanoseconds));
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

    const start_mp_ts = std.Io.Clock.awake.now(io);
    i = 0;
    while (i < iterations) : (i += 1) {
        const parsed = try zserde.msgpack.fromSliceBorrowed(UserPayload, mp_bytes);
        dummy +%= parsed.id;
    }
    const end_mp_ts = std.Io.Clock.awake.now(io);
    const zserde_mp_duration = start_mp_ts.durationTo(end_mp_ts);
    const zserde_mp_ns: u64 = @intCast(@max(1, zserde_mp_duration.nanoseconds));
    const zserde_mp_ops = (@as(f64, @floatFromInt(iterations)) / @as(f64, @floatFromInt(zserde_mp_ns))) * 1_000_000_000.0;
    const zserde_mp_mb = (zserde_mp_ops * @as(f64, @floatFromInt(mp_bytes.len))) / (1024.0 * 1024.0);

    std.debug.print("📦 2. zserde MessagePack (Zero-Copy Binary Deserialization):\n", .{});
    std.debug.print("   - Total Time: {d:.2} ms\n", .{@as(f64, @floatFromInt(zserde_mp_ns)) / 1_000_000.0});
    std.debug.print("   - Throughput: {d:.2} M ops/sec ({d:.2} MB/s)\n\n", .{ zserde_mp_ops / 1_000_000.0, zserde_mp_mb });

    std.debug.print("Checksum verification: {d}\n\n", .{dummy});
}
