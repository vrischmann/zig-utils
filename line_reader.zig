const std = @import("std");
const io = std.io;
const heap = std.heap;
const mem = std.mem;
const testing = std.testing;

pub const Line = struct {
    data: []const u8,
    start: u64,
    end: u64,
};

pub fn LineReader(comptime BufferSize: usize, comptime ReaderType: type) type {
    return struct {
        const Self = @This();

        allocator: mem.Allocator,
        reader: ReaderType,

        data: std.ArrayList(u8),
        file_position: u64,
        index: usize,

        pub fn init(allocator: mem.Allocator, reader: ReaderType) !Self {
            return Self{
                .allocator = allocator,
                .reader = reader,
                .data = try std.ArrayList(u8).initCapacity(allocator, BufferSize * 2),
                .file_position = 0,
                .index = 0,
            };
        }

        pub fn deinit(self: *Self) void {
            self.data.deinit();
        }

        pub fn next(self: *Self) !?Line {
            while (true) {
                // try to find the next line feed.
                if (mem.indexOfScalarPos(u8, self.data.items, self.index, '\n')) |pos| {
                    const data = self.data.items[self.index..pos];

                    self.index = pos + 1;

                    const start = self.file_position;
                    self.file_position += data.len + 1;

                    if (data.len == 0) return null;
                    return Line{
                        .data = data,
                        .start = start,
                        .end = start + data.len,
                    };
                }

                const remaining = self.data.items[self.index..];

                self.data.expandToCapacity();

                mem.copy(u8, self.data.items, remaining);
                mem.set(u8, self.data.items[remaining.len..], 0);

                const read = try self.reader.read(self.data.items[remaining.len..]);
                if (read <= 0) return null;

                self.index = 0;
            }
        }
    };
}

test "line reader" {
    const TestCase = struct {
        buffer_size: comptime_int,
        input: []const u8,
        exp: []const []const u8,
    };

    const testCases = &[_]TestCase{
        .{
            .buffer_size = 17,
            .input = "foobar\nbarbaz\nquxfoo\nhello\n",
            .exp = &[_][]const u8{
                "foobar", "barbaz", "quxfoo", "hello",
            },
        },
        .{
            .buffer_size = 6,
            .input = "foobar\nbarbaz\nquxfoo\nhello\n",
            .exp = &[_][]const u8{
                "foobar", "barbaz", "quxfoo", "hello",
            },
        },
        .{
            .buffer_size = 1024,
            .input = "foobar\nbarbaz\nquxfoo\nhello\n",
            .exp = &[_][]const u8{
                "foobar", "barbaz", "quxfoo", "hello",
            },
        },
        .{
            .buffer_size = 1024,
            .input = "foobarbazqux\n",
            .exp = &[_][]const u8{
                "foobarbazqux",
            },
        },
    };

    inline for (testCases) |tc| {
        var data_fbs = io.fixedBufferStream(tc.input);
        var data_reader = data_fbs.reader();

        const LineReaderType = LineReader(tc.buffer_size, @TypeOf(data_reader));
        var reader = try LineReaderType.init(testing.allocator, data_reader);
        defer reader.deinit();

        var lines = std.ArrayList([]const u8).init(testing.allocator);
        defer {
            for (lines.items) |line| testing.allocator.free(line);
            lines.deinit();
        }

        while (try reader.next()) |line| {
            try lines.append(try testing.allocator.dupe(u8, line.data));
        }

        try testing.expectEqual(@as(usize, tc.exp.len), lines.items.len);
        for (tc.exp) |exp, i| {
            try testing.expectEqualStrings(exp, lines.items[i]);
        }
    }
}

test "line reader 2" {
    const data =
        \\0.926180288429449,49.4405866526212,IMB/76056/X/0098,45,,rue,bouchée,,76480,Bardouville,individuel,cible,FI-76056-0003,deploye,FRTE,f,pavillon
        \\2.68171572103789,48.7695509509645,IMB/77350/X/029D,3,,rue,lavoisier,,77330,Ozoir-la-Ferrière,entre 2 et 11,cible,FI-77350-000K,deploye,FRTE,f,immeuble
        \\2.65426573589452,48.5293885834212,IMB/77288/S/02OK,46,,avenue,thiers,,77000,Melun,entre 2 et 11,en cours de deploiement,FI-77288-001A,deploye,FRTE,f,pavillon
        \\4.58216820843911,46.0628503177034,IMB/69151/X/00JG,23,,chemin,d'emilienne,,69460,Le Perréon,individuel,cible,FI-69151-0006,deploye,FRTE,f,pavillon
        \\0.932963897800278,49.4343680744479,IMB/76056/X/000O,2390,,chemin,du roy,,76480,Bardouville,individuel,cible,FI-76056-0003,deploye,FRTE,f,pavillon
    ;
    const exp = &[_][]const u8{
        "0.926180288429449,49.4405866526212,IMB/76056/X/0098,45,,rue,bouchée,,76480,Bardouville,individuel,cible,FI-76056-0003,deploye,FRTE,f,pavillon",
        "2.68171572103789,48.7695509509645,IMB/77350/X/029D,3,,rue,lavoisier,,77330,Ozoir-la-Ferrière,entre 2 et 11,cible,FI-77350-000K,deploye,FRTE,f,immeuble",
        "2.65426573589452,48.5293885834212,IMB/77288/S/02OK,46,,avenue,thiers,,77000,Melun,entre 2 et 11,en cours de deploiement,FI-77288-001A,deploye,FRTE,f,pavillon",
        "4.58216820843911,46.0628503177034,IMB/69151/X/00JG,23,,chemin,d'emilienne,,69460,Le Perréon,individuel,cible,FI-69151-0006,deploye,FRTE,f,pavillon",
        "0.932963897800278,49.4343680744479,IMB/76056/X/000O,2390,,chemin,du roy,,76480,Bardouville,individuel,cible,FI-76056-0003,deploye,FRTE,f,pavillon",
    };

    var data_fbs = io.fixedBufferStream(data);
    var data_reader = data_fbs.reader();

    const LineReaderType = LineReader(1024, @TypeOf(data_reader));
    var reader = try LineReaderType.init(testing.allocator, data_reader);
    defer reader.deinit();

    var i: usize = 0;
    while (try reader.next()) |line| {
        try testing.expectEqualStrings(exp[i], line.data);

        i += 1;
    }
}
