const std = @import("std");
const debug = std.debug;
const fmt = std.fmt;
const math = std.math;
const testing = std.testing;
const time = std.time;

const DefaultClock = struct {
    pub fn get(_: DefaultClock) i64 {
        return time.milliTimestamp();
    }
};

pub fn default(node_id: NodeID) Clock(DefaultClock) {
    return Clock(DefaultClock).init(node_id);
}

/// A Hybrid Logical Clock using the provided type as a physical clock to get the wall-time.
///
/// The physical clock must work with a default value.
pub fn Clock(comptime PhysicalClockType: type) type {
    if (!(comptime std.meta.trait.hasFn("get")(PhysicalClockType))) {
        @compileError("PhysicalClock must have a get() i64 method");
    }

    return struct {
        const Self = @This();

        physical_clock: PhysicalClockType = .{},
        wall: i64,
        count: u16,
        node_id: NodeID,

        /// Creates a new clock for this node.
        /// `node_id` should be a unique random identifier.
        pub fn init(node_id: NodeID) Self {
            var res = Self{
                .wall = undefined,
                .count = 0,
                .node_id = node_id,
            };
            res.wall = res.physical_clock.get();
            return res;
        }

        /// Returns a new local timestamp, updating the clock.
        pub fn now(self: *Self) Timestamp {
            const wall = self.physical_clock.get();

            const l_tmp = self.wall;
            const l = math.max(l_tmp, wall);

            if (l == l_tmp) {
                self.count += 1;
            } else {
                self.count = 0;
            }

            self.wall = l;

            return .{
                .wall = self.wall,
                .count = self.count,
                .node_id = self.node_id,
            };
        }

        /// Observe a remote timestamp, updating the clock.
        pub fn observe(self: *Self, ts: Timestamp) void {
            const wall = self.physical_clock.get();

            const l_tmp = self.wall;
            const l = math.max(ts.wall, math.max(l_tmp, wall));

            if (l == l_tmp and l == ts.wall) {
                self.count = math.max(self.count, ts.count) + 1;
            } else if (l == l_tmp) {
                self.count += 1;
            } else if (l == ts.wall) {
                self.count = ts.count + 1;
            } else {
                self.count = 0;
            }

            self.wall = l;
        }
    };
}

pub const Timestamp = struct {
    wall: i64,
    count: u16,
    node_id: NodeID,

    pub fn format(value: Timestamp, comptime fmt_s: []const u8, options: fmt.FormatOptions, writer: anytype) !void {
        _ = fmt_s;
        _ = options;

        const wall = @intCast(u64, value.wall);

        return writer.print("{d:0>15}-{d:0>6}-{d:0>6}", .{ wall, value.count, value.node_id });
    }

    pub fn lessThan(self: Timestamp, rhs: Timestamp) bool {
        if (self.wall < rhs.wall) return true;
        if (self.wall > rhs.wall) return false;

        if (self.count < rhs.count) return true;
        if (self.count > rhs.count) return false;

        return self.node_id < rhs.node_id;
    }
};

pub const NodeID = u16;

const TestClock = struct {
    n: i64 = 0,

    pub fn inc(self: *TestClock) void {
        self.n += 1;
    }

    pub fn get(self: *TestClock) i64 {
        return self.n;
    }
};

test "format" {
    {
        var clock = Clock(TestClock).init(3421);
        clock.physical_clock.n = 123275792220;

        var ts = clock.now();
        ts.count = 230;

        const result = try fmt.allocPrint(testing.allocator, "{}", .{ts});
        defer testing.allocator.free(result);

        try testing.expectEqualStrings("000123275792220-000230-003421", result);
    }

    {
        var real_clock = default(1054);

        const ts = real_clock.now();

        debug.print("result: {}\n", .{ts});
    }
}

test "now" {
    var rand = std.rand.DefaultPrng.init(@intCast(u64, time.milliTimestamp()));
    const node_id = rand.random().int(NodeID);

    var clock = Clock(TestClock).init(node_id);
    clock.physical_clock.n = 20;

    clock.physical_clock.n = 24;
    var ts = clock.now();

    try testing.expectEqual(@as(i64, 24), ts.wall);
    try testing.expectEqual(@as(u16, 0), ts.count);
    try testing.expectEqual(node_id, ts.node_id);

    // Wall clock has increased
    // Expect the timestamp wall clock to increase too
    {
        clock.physical_clock.n = 30;
        var ts2 = clock.now();

        try testing.expectEqual(@as(i64, 30), ts2.wall);
        try testing.expectEqual(@as(u16, 0), ts2.count);
        try testing.expectEqual(node_id, ts2.node_id);
    }

    // Timestamp is the same or has decreased
    {
        inline for (&[_]u64{ 20, 4 }) |n, i| {
            clock.physical_clock.n = n;
            var ts2 = clock.now();

            // Expect the counter to increment starting from 0
            const exp_counter = i + 1;

            // Expect the timestamp wall clock to stay the same
            try testing.expectEqual(@as(i64, 30), ts2.wall);
            try testing.expectEqual(@as(u16, exp_counter), ts2.count);
            try testing.expectEqual(node_id, ts2.node_id);
        }
    }
}

test "observe" {
    var rand = std.rand.DefaultPrng.init(@intCast(u64, time.milliTimestamp()));
    const node_id = rand.random().int(NodeID);
    const node_id2 = rand.random().int(NodeID);

    var clock1 = Clock(TestClock).init(node_id);

    // Remote clock is ahead; use it
    {
        clock1.physical_clock.n = 10;
        clock1.observe(Timestamp{ .wall = 59, .count = 0, .node_id = node_id2 });

        try testing.expectEqual(@as(i64, 59), clock1.wall);
        try testing.expectEqual(@as(u16, 1), clock1.count);
    }

    // Local clock is ahead, physical clock went backwards; use the local clock
    {
        clock1.physical_clock.n = 32;
        clock1.observe(Timestamp{ .wall = 42, .count = 0, .node_id = node_id2 });

        try testing.expectEqual(@as(i64, 59), clock1.wall);
        try testing.expectEqual(@as(u16, 2), clock1.count);
    }

    // Wall clock is ahead, use it
    {
        clock1.physical_clock.n = 84;
        clock1.observe(Timestamp{ .wall = 79, .count = 0, .node_id = node_id2 });

        try testing.expectEqual(@as(i64, 84), clock1.wall);
        try testing.expectEqual(@as(u16, 0), clock1.count);
    }

    // All clocks the same
    {
        clock1.physical_clock.n = 84;
        clock1.observe(Timestamp{ .wall = 84, .count = 22, .node_id = node_id2 });

        try testing.expectEqual(@as(i64, 84), clock1.wall);
        try testing.expectEqual(@as(u16, 23), clock1.count);
    }
}

test "paper figure 5" {
    var clock0 = Clock(TestClock).init(0);
    var clock1 = Clock(TestClock).init(1);
    var clock2 = Clock(TestClock).init(2);
    var clock3 = Clock(TestClock).init(3);

    clock0.physical_clock.n = 10;

    // new events on 0, 2, 3
    const ts0 = blk: {
        const ts = clock0.now();

        try testing.expectEqual(@as(i64, 10), ts.wall);
        try testing.expectEqual(@as(u16, 0), ts.count);

        break :blk ts;
    };

    {
        clock2.physical_clock.inc();
        const ts = clock2.now();

        try testing.expectEqual(@as(i64, 1), clock2.physical_clock.n);
        try testing.expectEqual(@as(i64, 1), ts.wall);
        try testing.expectEqual(@as(u16, 0), ts.count);
    }
    {
        clock3.physical_clock.inc();
        const ts = clock3.now();

        try testing.expectEqual(@as(i64, 1), clock3.physical_clock.n);
        try testing.expectEqual(@as(i64, 1), ts.wall);
        try testing.expectEqual(@as(u16, 0), ts.count);
    }

    // send event from 0 -> 1
    {
        clock1.physical_clock.inc();
        clock1.observe(ts0);

        try testing.expectEqual(@as(i64, 1), clock1.physical_clock.n);
        try testing.expectEqual(@as(i64, 10), clock1.wall);
        try testing.expectEqual(@as(u16, 1), clock1.count);
    }

    // new event on 1
    const ts1_1 = blk: {
        clock1.physical_clock.inc();
        const ts = clock1.now();

        try testing.expectEqual(@as(i64, 2), clock1.physical_clock.n);
        try testing.expectEqual(@as(i64, 10), ts.wall);
        try testing.expectEqual(@as(u16, 2), ts.count);

        break :blk ts;
    };

    // send event from 1 -> 2
    {
        clock2.physical_clock.inc();
        clock2.observe(ts1_1);

        try testing.expectEqual(@as(i64, 2), clock2.physical_clock.n);
        try testing.expectEqual(@as(i64, 10), clock2.wall);
        try testing.expectEqual(@as(u16, 3), clock2.count);
    }

    // new event on 2, 3
    const ts2 = blk: {
        clock2.physical_clock.inc();
        break :blk clock2.now();
    };
    {
        clock3.physical_clock.inc();
        _ = clock3.now();
    }

    // send event from 2 -> 3
    {
        clock3.physical_clock.inc();
        clock3.observe(ts2);

        try testing.expectEqual(@as(i64, 3), clock3.physical_clock.n);
        try testing.expectEqual(@as(i64, 10), clock3.wall);
        try testing.expectEqual(@as(u16, 5), clock3.count);
    }

    // new event on 1
    {
        clock1.physical_clock.inc();
        const ts = clock1.now();

        try testing.expectEqual(@as(i64, 3), clock1.physical_clock.n);
        try testing.expectEqual(@as(i64, 10), ts.wall);
        try testing.expectEqual(@as(u16, 3), ts.count);
    }

    var ts3 = blk: {
        clock3.physical_clock.inc();
        const ts = clock3.now();

        try testing.expectEqual(@as(i64, 4), clock3.physical_clock.n);
        try testing.expectEqual(@as(i64, 10), ts.wall);
        try testing.expectEqual(@as(u16, 6), ts.count);

        break :blk ts;
    };

    // send event from 3 -> 1
    {
        clock1.physical_clock.inc();
        clock1.observe(ts3);

        try testing.expectEqual(@as(i64, 4), clock1.physical_clock.n);
        try testing.expectEqual(@as(i64, 10), clock1.wall);
        try testing.expectEqual(@as(u16, 7), clock1.count);
    }
}

test "order" {
    var clock1 = Clock(TestClock).init(0);
    var clock2 = Clock(TestClock).init(0);

    // hlc1 ts < hlc2 ts
    {
        const ts1 = clock1.now();
        clock2.physical_clock.inc();
        const ts2 = clock2.now();

        try testing.expect(ts1.lessThan(ts2));
        try testing.expect(!ts2.lessThan(ts1));
    }

    // hlc1 count < hlc2 count
    {
        clock1.count = 2;
        const ts1 = clock1.now();
        clock2.count = 3;
        const ts2 = clock2.now();

        try testing.expect(ts1.lessThan(ts2));
        try testing.expect(!ts2.lessThan(ts1));
    }

    // hlc1 node_id < hlc2 node_id
    {
        clock1.node_id = 200;
        clock2.node_id = 300;

        const ts1 = clock1.now();
        const ts2 = clock2.now();

        try testing.expect(ts1.lessThan(ts2));
        try testing.expect(!ts2.lessThan(ts1));
    }
}

test "sort" {
    var hlcs = [_]Timestamp{
        .{ .wall = 400, .count = 2, .node_id = 40 },
        .{ .wall = 20, .count = 5, .node_id = 40 },
        .{ .wall = 20, .count = 5, .node_id = 0 },
        .{ .wall = 400, .count = 2, .node_id = 0 },
        .{ .wall = 20, .count = 0, .node_id = 0 },
    };

    std.sort.sort(
        Timestamp,
        hlcs[0..hlcs.len],
        {},
        struct {
            fn lessThan(_: void, lhs: Timestamp, rhs: Timestamp) bool {
                return lhs.lessThan(rhs);
            }
        }.lessThan,
    );

    const exp = &[_]Timestamp{
        .{ .wall = 20, .count = 0, .node_id = 0 },
        .{ .wall = 20, .count = 5, .node_id = 0 },
        .{ .wall = 20, .count = 5, .node_id = 40 },
        .{ .wall = 400, .count = 2, .node_id = 0 },
        .{ .wall = 400, .count = 2, .node_id = 40 },
    };

    try testing.expectEqualSlices(Timestamp, exp, hlcs[0..hlcs.len]);
}
