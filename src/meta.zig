const std = @import("std");

pub const NamingConvention = enum {
    exact,
    snake_case,
    camelCase,
    kebab_case,
    PascalCase,
};

pub const FieldOptions = struct {
    rename: ?[]const u8 = null,
    skip: bool = false,
    default: ?*const anyopaque = null,
};

pub fn computeConvertedLength(comptime input: []const u8, comptime convention: NamingConvention) usize {
    if (convention == .exact or convention == .snake_case) {
        return input.len;
    }
    var len: usize = 0;
    for (input) |c| {
        if (c != '_' and c != '-') {
            len += 1;
        } else if (convention == .kebab_case) {
            len += 1;
        }
    }
    return len;
}

pub fn convertCaseArray(
    comptime input: []const u8,
    comptime convention: NamingConvention,
    comptime len: usize,
) [len]u8 {
    var result: [len]u8 = undefined;
    var out_idx: usize = 0;
    var capitalize_next: bool = (convention == .PascalCase);

    for (input) |c| {
        if (c == '_' or c == '-') {
            if (convention == .kebab_case) {
                result[out_idx] = '-';
                out_idx += 1;
            } else {
                capitalize_next = true;
            }
        } else {
            var char_to_write = c;
            if (capitalize_next) {
                if (char_to_write >= 'a' and char_to_write <= 'z') {
                    char_to_write -= 32;
                }
                capitalize_next = false;
            }
            result[out_idx] = char_to_write;
            out_idx += 1;
        }
    }
    return result;
}

fn CaseStorage(comptime input: []const u8, comptime convention: NamingConvention) type {
    const len = computeConvertedLength(input, convention);
    return struct {
        pub const value: [len]u8 = convertCaseArray(input, convention, len);
    };
}

pub fn convertCase(comptime input: []const u8, comptime convention: NamingConvention) []const u8 {
    if (convention == .exact or convention == .snake_case) {
        return input;
    }
    return &CaseStorage(input, convention).value;
}

/// Check if type T has custom zserde options declared
pub fn getFieldOptions(comptime T: type, comptime field_name: []const u8) FieldOptions {
    if (!@hasDecl(T, "zserde")) {
        return .{};
    }
    const decl = @field(T, "zserde");
    const decl_type = @TypeOf(decl);

    var opts = FieldOptions{};

    // 1. Direct field rename
    if (@hasField(decl_type, "rename")) {
        const renames = decl.rename;
        if (@hasField(@TypeOf(renames), field_name)) {
            opts.rename = @field(renames, field_name);
        }
    }

    // 2. Global rename_all convention fallback
    if (opts.rename == null and @hasField(decl_type, "rename_all")) {
        const convention: NamingConvention = decl.rename_all;
        opts.rename = convertCase(field_name, convention);
    }

    // 3. Skip rule
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

pub fn getFieldOptionsWithOverride(
    comptime T: type,
    comptime field_name: []const u8,
    comptime override_opts: anytype,
) FieldOptions {
    var opts = getFieldOptions(T, field_name);
    const OverrideType = @TypeOf(override_opts);

    if (@hasField(OverrideType, "rename")) {
        const renames = override_opts.rename;
        if (@hasField(@TypeOf(renames), field_name)) {
            opts.rename = @field(renames, field_name);
        }
    }

    if (@hasField(OverrideType, "rename_all")) {
        const convention: NamingConvention = override_opts.rename_all;
        opts.rename = convertCase(field_name, convention);
    }

    if (@hasField(OverrideType, "skip")) {
        const skips = override_opts.skip;
        if (@hasField(@TypeOf(skips), field_name)) {
            opts.skip = @field(skips, field_name);
        }
    }

    return opts;
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
