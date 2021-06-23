const std = @import("std");

usingnamespace @import("scanner.zig");

test "" {
    std.testing.refAllDecls(@This());
}
