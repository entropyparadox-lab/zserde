const std = @import("std");

pub const NamingConvention = enum {
    exact,
    snake_case,
    camelCase,
    kebab_case,
};

pub const FieldOptions = struct {
    rename: ?[]const u8 = null,
    skip: bool = false,
    default: ?*const anyopaque = null,
};

/// Check if type T has custom zserde options declared
pub fn getFieldOptions(comptime T: type, comptime field_name: []const u8) FieldOptions {
    if (!@hasDecl(T, "zserde")) {
        return .{};
    }
    const decl = @field(T, "zserde");
    const decl_type = @TypeOf(decl);

    var opts = FieldOptions{};

    if (@hasField(decl_type, "rename")) {
        const renames = decl.rename;
        if (@hasField(@TypeOf(renames), field_name)) {
            opts.rename = @field(renames, field_name);
        }
    }

    if (@hasField(decl_type, "skip")) {
        const skips = decl.skip;
        if (@hasField(@TypeOf(skips), field_name)) {
            opts.skip = @field(skips, field_name);
        }
    }

    return opts;
}

pub fn getFieldName(comptime T: type, comptime field: std.builtin.Type.StructField) []const u8 {
    const opts = getFieldOptions(T, field.name);
    if (opts.rename) |custom| {
        return custom;
    }
    return field.name;
}

pub fn isOptional(comptime T: type) bool {
    return @typeInfo(T) == .optional;
}

pub fn unwrapOptional(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .optional => |opt| opt.child,
        else => T,
    };
}
