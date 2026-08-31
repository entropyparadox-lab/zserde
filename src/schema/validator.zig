const std = @import("std");

pub const ValidationError = error{
    ValueTooSmall,
    ValueTooLarge,
    StringTooShort,
    StringTooLong,
    PatternMismatch,
    CustomValidationFailed,
};

pub const FieldViolation = struct {
    field: []const u8,
    code: ValidationError,
    message: []const u8,
};

pub const ValidationReport = struct {
    violations: []const FieldViolation,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ValidationReport) void {
        self.allocator.free(self.violations);
    }

    pub fn isValid(self: *const ValidationReport) bool {
        return self.violations.len == 0;
    }
};

pub fn validate(value: anytype) ValidationError!void {
    const T = @TypeOf(value);
    const info = @typeInfo(T);

    switch (info) {
        .@"struct" => {
            if (@hasDecl(T, "zvalidate")) {
                const rules = @field(T, "zvalidate");
                const rules_type = @TypeOf(rules);

                inline for (std.meta.fields(T)) |f| {
                    if (@hasField(rules_type, f.name)) {
                        const rule = @field(rules, f.name);
                        const field_val = @field(value, f.name);
                        try validateField(field_val, rule);
                    }
                }
            }

            // Recursively validate nested structs (direct, optional, or slice)
            inline for (std.meta.fields(T)) |f| {
                const field_info = @typeInfo(f.type);
                if (field_info == .@"struct") {
                    try validate(@field(value, f.name));
                } else if (field_info == .optional and @typeInfo(field_info.optional.child) == .@"struct") {
                    if (@field(value, f.name)) |unwrapped| {
                        try validate(unwrapped);
                    }
                } else if (field_info == .pointer and field_info.pointer.size == .slice and @typeInfo(field_info.pointer.child) == .@"struct") {
                    for (@field(value, f.name)) |item| {
                        try validate(item);
                    }
                }
            }
        },
        else => {},
    }
}

pub fn validateWithReport(value: anytype, allocator: std.mem.Allocator) !ValidationReport {
    var violations_list: std.ArrayList(FieldViolation) = .empty;
    errdefer violations_list.deinit(allocator);

    const T = @TypeOf(value);
    if (@typeInfo(T) == .@"struct" and @hasDecl(T, "zvalidate")) {
        const rules = @field(T, "zvalidate");
        const rules_type = @TypeOf(rules);

        inline for (std.meta.fields(T)) |f| {
            if (@hasField(rules_type, f.name)) {
                const rule = @field(rules, f.name);
                const field_val = @field(value, f.name);
                if (validateField(field_val, rule)) {} else |err| {
                    try violations_list.append(allocator, .{
                        .field = f.name,
                        .code = err,
                        .message = @errorName(err),
                    });
                }
            }
        }
    }

    return .{
        .violations = try violations_list.toOwnedSlice(allocator),
        .allocator = allocator,
    };
}

fn validateField(val: anytype, rule: anytype) ValidationError!void {
    const ValType = @TypeOf(val);
    const val_info = @typeInfo(ValType);
    const RuleType = @TypeOf(rule);

    // Handle Optionals
    if (val_info == .optional) {
        if (val) |unwrapped| {
            return validateField(unwrapped, rule);
        }
        return; // null is valid
    }

    // Number constraints: min, max
    if (val_info == .int or val_info == .float) {
        if (@hasField(RuleType, "min")) {
            if (val < rule.min) return ValidationError.ValueTooSmall;
        }
        if (@hasField(RuleType, "max")) {
            if (val > rule.max) return ValidationError.ValueTooLarge;
        }
    }

    // String constraints: min_len, max_len, contains, starts_with, ends_with
    if (val_info == .pointer and val_info.pointer.size == .slice and val_info.pointer.child == u8) {
        if (@hasField(RuleType, "min_len")) {
            if (val.len < rule.min_len) return ValidationError.StringTooShort;
        }
        if (@hasField(RuleType, "max_len")) {
            if (val.len > rule.max_len) return ValidationError.StringTooLong;
        }
        if (@hasField(RuleType, "contains")) {
            if (std.mem.indexOf(u8, val, rule.contains) == null) {
                return ValidationError.PatternMismatch;
            }
        }
        if (@hasField(RuleType, "starts_with")) {
            if (!std.mem.startsWith(u8, val, rule.starts_with)) {
                return ValidationError.PatternMismatch;
            }
        }
        if (@hasField(RuleType, "ends_with")) {
            if (!std.mem.endsWith(u8, val, rule.ends_with)) {
                return ValidationError.PatternMismatch;
            }
        }
    }

    // Slice / Array item length validation
    if (val_info == .pointer and val_info.pointer.size == .slice and val_info.pointer.child != u8) {
        if (@hasField(RuleType, "min_len")) {
            if (val.len < rule.min_len) return ValidationError.StringTooShort;
        }
        if (@hasField(RuleType, "max_len")) {
            if (val.len > rule.max_len) return ValidationError.StringTooLong;
        }
    }

    // Custom validator function
    if (@hasField(RuleType, "custom")) {
        const is_valid = rule.custom(val);
        if (!is_valid) return ValidationError.CustomValidationFailed;
    }
}
