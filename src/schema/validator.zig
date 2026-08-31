const std = @import("std");

pub const ValidationError = error{
    ValueTooSmall,
    ValueTooLarge,
    StringTooShort,
    StringTooLong,
    PatternMismatch,
    CustomValidationFailed,
};

pub const ValidationResult = struct {
    valid: bool,
    error_message: ?[]const u8 = null,
    field_name: ?[]const u8 = null,
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

            // Also validate nested structs if applicable
            inline for (std.meta.fields(T)) |f| {
                if (@typeInfo(f.type) == .@"struct") {
                    try validate(@field(value, f.name));
                }
            }
        },
        else => {},
    }
}

fn validateField(val: anytype, rule: anytype) ValidationError!void {
    const ValType = @TypeOf(val);
    const val_info = @typeInfo(ValType);
    const RuleType = @TypeOf(rule);

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

    // Custom validator function
    if (@hasField(RuleType, "custom")) {
        const is_valid = rule.custom(val);
        if (!is_valid) return ValidationError.CustomValidationFailed;
    }
}
