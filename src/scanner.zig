const std = @import("std");
const heap = std.heap;
const io = std.io;
const mem = std.mem;
const testing = std.testing;

/// A scanner reads tokens from a stream. Tokens are byte slices delimited by a set of possible bytes.
/// The BufferSize must be big enough to hold a single token
///
/// For example, here's how to scan for lines:
///
///  var line_scanner = Scanner(...).init(in_stream, "\n");
///  while ()
pub fn Scanner(comptime InStreamType: type, comptime BufferSize: comptime_int) type {
    return struct {
        const Self = @This();

        allocator: *mem.Allocator,

        in_stream: InStreamType,
        delimiter_bytes: []const u8,

        previous_buffer: [BufferSize]u8,
        previous_buffer_slice: []u8,

        buffer: [BufferSize]u8,
        buffer_slice: []u8,

        remaining: usize,

        token: ?[]const u8,

        pub fn init(allocator: *mem.Allocator, in_stream: InStreamType, delimiter_bytes: []const u8) Self {
            return Self{
                .allocator = allocator,
                .in_stream = in_stream,
                .delimiter_bytes = delimiter_bytes,
                .previous_buffer = undefined,
                .previous_buffer_slice = &[_]u8{},
                .buffer = undefined,
                .buffer_slice = &[_]u8{},
                .remaining = 0,
                .token = null,
            };
        }

        fn refill(self: *Self) !void {
            const n = try self.in_stream.readAll(&self.buffer);
            self.buffer_slice = self.buffer[0..n];
            self.remaining = n;
        }

        fn isSplitByte(self: Self, c: u8) bool {
            for (self.delimiter_bytes) |b| {
                if (b == c) {
                    return true;
                }
            }
            return false;
        }

        pub fn getToken(self: Self) ?[]const u8 {
            return self.token;
        }

        pub fn scan(self: *Self) !bool {
            comptime var i = 0;

            inline while (i < 2) : (i += 1) {
                if (self.remaining == 0) _ = try self.refill();
                if (self.remaining <= 0) return false;

                var j: usize = 0;
                while (j < self.buffer_slice.len) : (j += 1) {
                    if (self.isSplitByte(self.buffer_slice[j])) {
                        const line = if (self.previous_buffer_slice.len > 0)
                            try mem.concat(self.allocator, u8, &[_][]const u8{
                                self.previous_buffer_slice,
                                self.buffer_slice[0..j],
                            })
                        else
                            self.buffer_slice[0..j];

                        mem.set(u8, &self.previous_buffer, 0);
                        self.buffer_slice = self.buffer_slice[j + 1 .. self.buffer_slice.len];
                        self.remaining -= 1;

                        self.token = line;
                        return true;
                    }
                    self.remaining -= 1;
                }

                mem.copy(u8, &self.previous_buffer, self.buffer_slice);
                self.previous_buffer_slice = self.previous_buffer[0..self.buffer_slice.len];
                self.buffer_slice = &[_]u8{};
            }

            return false;
        }
    };
}

test "line scanner: scan" {
    var arena = heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const data = "foobar\nhello\rbonjour\x00";
    var fbs = io.fixedBufferStream(data);
    var in_stream = fbs.inStream();

    var scanner = Scanner(@TypeOf(in_stream), 1024).init(&arena.allocator, in_stream, "\r\n\x00");

    testing.expect(try scanner.scan());
    testing.expectEqualSlices(u8, "foobar", scanner.getToken().?);

    testing.expect(try scanner.scan());
    testing.expectEqualSlices(u8, "hello", scanner.getToken().?);

    testing.expect(try scanner.scan());
    testing.expectEqualSlices(u8, "bonjour", scanner.getToken().?);

    testing.expect((try scanner.scan()) == false);
}
