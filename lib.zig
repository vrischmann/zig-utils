const std = @import("std");

usingnamespace @import("scanner.zig");
usingnamespace @import("line_reader.zig");

test "" {
    std.testing.refAllDecls(@This());
}
