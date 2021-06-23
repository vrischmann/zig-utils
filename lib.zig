const std = @import("std");

usingnamespace @import("scanner.zig");
usingnamespace @import("linereader.zig");

test "" {
    std.testing.refAllDecls(@This());
}
