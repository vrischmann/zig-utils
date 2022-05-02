const std = @import("std");
const meta = std.meta;
const io = std.io;
const testing = std.testing;

pub fn copy(dest: anytype, source: anytype) (error{BufferTooSmall} || @TypeOf(dest).Error || @TypeOf(source).Error)!usize {
    var buffer: [4096]u8 = undefined;
    return copyUsingBuffer(dest, source, &buffer);
}

pub fn copyUsingBuffer(dest: anytype, source: anytype, buffer: []u8) (error{BufferTooSmall} || @TypeOf(dest).Error || @TypeOf(source).Error)!usize {
    const WriterType = @TypeOf(dest);
    const ReaderType = @TypeOf(source);

    if (!comptime meta.trait.hasFn("write")(WriterType)) {
        @compileError("dest must be a io.Writer type");
    }
    if (!comptime meta.trait.hasFn("read")(ReaderType)) {
        @compileError("source must be a io.Reader type");
    }

    if (buffer.len <= 0) return error.BufferTooSmall;

    var copied: usize = 0;
    while (true) {
        const n = try source.read(buffer);
        if (n <= 0) return copied;

        const data = buffer[0..n];

        var write_index: usize = 0;
        while (write_index != n) {
            write_index += try dest.write(data[write_index..]);
        }

        copied += n;
    }
}

test "copy empty buffer" {
    var source = io.fixedBufferStream("foobar");

    var dest_buffer: [1024]u8 = undefined;
    var dest = io.fixedBufferStream(&dest_buffer);

    var empty_buffer: [0]u8 = undefined;
    try testing.expectError(error.BufferTooSmall, copyUsingBuffer(dest.writer(), source.reader(), &empty_buffer));
}

test "copy all buffers" {
    const data = "my_source";

    var source = io.fixedBufferStream(data);

    var dest_buffer: [1024]u8 = undefined;
    var dest = io.fixedBufferStream(&dest_buffer);

    var copy_buffer: [4096]u8 = undefined;
    const copied = try copyUsingBuffer(dest.writer(), source.reader(), &copy_buffer);
    try testing.expectEqual(data.len, copied);
    try testing.expectEqualStrings(data, dest.getWritten());
}

test "copy file" {
    var dir = testing.tmpDir(.{});
    defer dir.cleanup();

    var file1 = try dir.dir.createFile("file1.txt", .{ .read = true });
    defer file1.close();
    var file2 = try dir.dir.createFile("file2.txt", .{ .read = true });
    defer file2.close();

    const data = "old_data";

    try file1.writeAll(data);
    try file1.seekTo(0);

    const copied = try copy(file2.writer(), file1.reader());
    try testing.expectEqual(data.len, copied);

    try file2.seekTo(0);
    const file2_data = try file2.readToEndAlloc(testing.allocator, 1024);
    defer testing.allocator.free(file2_data);
    try testing.expectEqualStrings(data, file2_data);
}

test "hash file" {
    var dir = testing.tmpDir(.{});
    defer dir.cleanup();

    var file1 = try dir.dir.createFile("file1.txt", .{ .read = true });
    defer file1.close();

    const data = "a" ** 200;

    try file1.writeAll(data);
    try file1.seekTo(0);

    var hasher = std.crypto.hash.Blake3.init(.{});

    const copied = try copy(hasher.writer(), file1.reader());
    try testing.expectEqual(data.len, copied);

    var hash: [std.crypto.hash.Blake3.digest_length]u8 = undefined;
    hasher.final(&hash);

    const expected_hash = "22dee5ebfe8248a5fe4fb663016d8524c9a61eb36b7f7be8bb57057613230447";

    const result_hash = try std.fmt.allocPrint(testing.allocator, "{s}", .{
        std.fmt.fmtSliceHexLower(&hash),
    });
    defer testing.allocator.free(result_hash);

    try testing.expectEqualStrings(expected_hash, result_hash);

    std.debug.print("hash: {s}\n", .{result_hash});
}

test "copy process output" {
    var dir = testing.tmpDir(.{});
    defer dir.cleanup();

    var file1 = try dir.dir.createFile("file1.txt", .{ .read = true });
    defer file1.close();

    var process = std.ChildProcess.init(&[_][]const u8{"uptime"}, testing.allocator);
    process.stdin_behavior = .Pipe;
    process.stdout_behavior = .Pipe;
    try process.spawn();

    const copied = try copy(file1.writer(), process.stdout.?.reader());
    try testing.expect(copied > 0);

    switch (try process.wait()) {
        .Exited => |code| {
            try testing.expectEqual(@as(u8, 0), code);

            try file1.seekTo(0);
            const data = try file1.readToEndAlloc(testing.allocator, 1024);
            defer testing.allocator.free(data);

            std.debug.print("data: \"{s}\"\n", .{data});
        },
        else => unreachable,
    }
}
