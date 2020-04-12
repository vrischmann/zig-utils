const std = @import("std");
const heap = std.heap;
const io = std.io;
const mem = std.mem;
const testing = std.testing;

fn LineScanner(comptime InStreamType: type) type {
    return struct {
        const Self = @This();

        arena: heap.ArenaAllocator,

        in_stream: InStreamType,

        previous_buffer: [4096]u8,
        previous_buffer_slice: []u8,

        buffer: [4096]u8,
        buffer_slice: []u8,

        remaining: usize,

        pub fn deinit(self: *Self) void {
            self.arena.deinit();
        }

        pub fn init(allocator: *mem.Allocator, in_stream: InStreamType) Self {
            return Self{
                .arena = heap.ArenaAllocator.init(allocator),
                .in_stream = in_stream,
                .previous_buffer = undefined,
                .previous_buffer_slice = &[_]u8{},
                .buffer = undefined,
                .buffer_slice = &[_]u8{},
                .remaining = 0,
            };
        }

        fn refill(self: *Self) !void {
            const n = try self.in_stream.readAll(&self.buffer);
            self.buffer_slice = self.buffer[0..n];
            self.remaining = n;
        }

        pub fn scan(self: *Self) !?[]const u8 {
            comptime var i = 0;

            inline while (i < 2) : (i += 1) {
                if (self.remaining == 0) _ = try self.refill();
                if (self.remaining <= 0) return null;

                var j: usize = 0;
                while (j < self.buffer_slice.len) : (j += 1) {
                    if (self.buffer_slice[j] == '\n') {
                        const line = try mem.concat(&self.arena.allocator, u8, &[_][]const u8{
                            self.previous_buffer_slice,
                            self.buffer_slice[0..j],
                        });

                        mem.set(u8, &self.previous_buffer, 0);
                        self.buffer_slice = self.buffer_slice[j + 1 .. self.buffer_slice.len];
                        self.remaining -= 1;

                        return line;
                    }
                    self.remaining -= 1;
                }

                mem.copy(u8, &self.previous_buffer, self.buffer_slice);
                self.previous_buffer_slice = self.previous_buffer[0..self.buffer_slice.len];
                self.buffer_slice = &[_]u8{};
            }

            return null;
        }
    };
}

test "line scanner: scan" {
    const data = "foobar\nhello\nbonjour\n";
    var fbs = io.fixedBufferStream(data);
    var in_stream = fbs.inStream();

    var line_scanner = LineScanner(@TypeOf(in_stream)).init(testing.allocator, in_stream);
    defer line_scanner.deinit();

    var line = (try line_scanner.scan()).?;
    testing.expectEqualSlices(u8, "foobar", line);

    line = (try line_scanner.scan()).?;
    testing.expectEqualSlices(u8, "hello", line);

    line = (try line_scanner.scan()).?;
    testing.expectEqualSlices(u8, "bonjour", line);
}
