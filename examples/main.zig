const std = @import("std");
const zserde = @import("zserde");

const DatabaseConfig = struct {
    host: []const u8,
    port: u16 = 5432,
    max_connections: u32 = 10,
    password: []const u8,

    pub const zserde = .{
        .rename = .{
            .max_connections = "maxConnections",
        },
        .skip = .{
            .password = true,
        },
    };

    pub const zvalidate = .{
        .port = .{ .min = 1, .max = 65535 },
        .max_connections = .{ .min = 1, .max = 1000 },
    };
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    std.debug.print("\n=== zserde: Zero-Allocation Serialization & Validation for Zig 0.16.0+ ===\n\n", .{});

    const config = DatabaseConfig{
        .host = "localhost",
        .port = 5432,
        .max_connections = 50,
        .password = "secret_pass_123",
    };

    // 1. Validation
    try zserde.validate(config);
    std.debug.print("1. Schema validation: PASS (port: {}, max_conns: {})\n", .{ config.port, config.max_connections });

    // 2. Serialization with Rename & Skip
    const json_str = try zserde.json.toSlice(allocator, config, .{ .pretty = true });
    defer allocator.free(json_str);

    std.debug.print("2. Serialized JSON (password skipped, maxConnections renamed):\n{s}\n\n", .{json_str});

    // 3. Zero-Allocation Deserialization (Borrowed)
    const incoming_payload =
        \\{"host":"postgres.internal","port":5433,"maxConnections":100}
    ;

    const parsed = try zserde.json.fromSliceBorrowed(DatabaseConfig, incoming_payload);
    std.debug.print("3. Deserialized (Zero-copy borrowed from source):\n", .{});
    std.debug.print("   - Host: {s}\n", .{parsed.host});
    std.debug.print("   - Port: {d}\n", .{parsed.port});
    std.debug.print("   - Max Conns: {d}\n", .{parsed.max_connections});

    std.debug.print("\nAll operations executed successfully!\n", .{});
}
