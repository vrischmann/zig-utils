const std = @import("std");
const mem = std.mem;
const testing = std.testing;

pub fn LineReader(comptime BufferSize: comptime_int, comptime Reader: type) type {
    return struct {
        const Self = @This();

        const FifoType = std.fifo.LinearFifo(u8, std.fifo.LinearFifoBufferType{ .Static = BufferSize });

        reader: Reader,
        fifo: FifoType,
        last_token_size: usize,

        pub fn init(self: *Self, reader: Reader) !void {
            self.reader = reader;
            self.fifo = FifoType.init();
            self.last_token_size = 0;
        }

        pub fn readLine(self: *Self) !?[]const u8 {
            if (self.last_token_size > 0) {
                self.fifo.discard(self.last_token_size);
                self.fifo.realign();
            }

            while (true) {
                const readable = self.fifo.readableSlice(0);

                if (mem.indexOf(u8, readable, "\n")) |pos| {
                    const token = readable[0..pos];
                    self.last_token_size = token.len + 1;
                    return token;
                }

                var writable = self.fifo.writableSlice(0);
                const read = try self.reader.read(writable);
                if (read == 0) break;

                self.fifo.update(read);
            }

            return if (self.fifo.readableLength() > 0) self.fifo.readableSlice(0) else null;
        }
    };
}

test "line reader" {
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

    const FBS = std.io.FixedBufferStream([]const u8);
    var fbs = FBS{ .buffer = data, .pos = 0 };

    const LineReaderType = LineReader(1024, FBS.Reader);
    var line_reader: LineReaderType = undefined;
    try line_reader.init(fbs.reader());

    var i: usize = 0;
    while (i < 5) : (i += 1) {
        const line = try line_reader.readLine();
        std.debug.print("got line: {s}\n", .{line});
        try testing.expect(line != null);
        try testing.expectEqualStrings(exp[i], line.?);
    }
}
