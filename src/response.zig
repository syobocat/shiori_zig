// SPDX-FileCopyrightText: 2025 SyoBoN <syobon@syobon.net>
//
// SPDX-License-Identifier: UPL-1.0

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const common = @import("common.zig");
const Headers = common.Headers;
const References = common.References;
const XSstpPassThru = common.XSstpPassThru;
const SecurityLevel = common.SecurityLevel;

pub const OOM_ERROR_RESPONSE = "SHIORI/3.0 500 Internal Server Error\r\nCharset: UTF-8\r\nSender: zSHIORI\r\nErrorLevel: critical\r\nErrorDescription: Out of memory\r\n\r\n";

pub const Status = enum(u16) {
    ok = 200,
    no_content = 204,
    not_enough = 311,
    advice = 312,
    bad_request = 400,
    internal_server_error = 500,

    fn msg(self: @This()) []const u8 {
        return switch (self) {
            .ok => "OK",
            .no_content => "No Content",
            .not_enough => "Not Enough",
            .advice => "Advice",
            .bad_request => "Bad Request",
            .internal_server_error => "Internal Server Error",
        };
    }

    pub fn format(self: @This(), writer: *Io.Writer) Io.Writer.Error!void {
        try writer.print("{d} {s}", .{ self, self.msg() });
    }
};

pub const ResponseRaw = struct {
    status: Status = .no_content,
    headers: Headers = .empty,

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        self.headers.deinit(allocator);
    }

    pub fn format(self: @This(), writer: *Io.Writer) Io.Writer.Error!void {
        try writer.print("SHIORI/3.0 {f}\r\n", .{self.status});

        var iter = self.headers.iterator();
        while (iter.next()) |header| {
            try writer.print("{s}: {s}\r\n", .{ header.key_ptr.*, header.value_ptr.* });
        }

        try writer.writeAll("\r\n");
    }

    /// レスポンスをレンダーします。OutOfMemoryの場合エラーを委託します。
    pub fn renderFailable(self: @This(), allocator: Allocator) error{OutOfMemory}![:0]const u8 {
        var awriter: Io.Writer.Allocating = .init(allocator);
        defer awriter.deinit();
        const writer = &awriter.writer;

        writer.print("{f}", .{self}) catch return error.OutOfMemory;

        return try awriter.toOwnedSliceSentinel(0);
    }

    /// レスポンスをレンダーします。OutOfMemoryの場合、既定のエラーレスポンスを返します。
    pub fn render(self: @This(), allocator: std.mem.Allocator) [:0]const u8 {
        return self.renderFailable(allocator) catch OOM_ERROR_RESPONSE;
    }
};

pub const ErrorLevel = enum {
    info,
    notice,
    warning,
    @"error",
    critical,
};

pub const Error = struct {
    level: ErrorLevel,
    description: []const u8,
};

pub const BalloonOffset = struct {
    x: u32,
    y: u32,

    pub fn format(self: @This(), writer: *Io.Writer) Io.Writer.Error!void {
        try writer.print("({d},{d})", .{ self.x, self.y });
    }
};

pub const Response = struct {
    status: Status = .no_content,
    charset: []const u8 = "UTF-8",
    sender: []const u8 = "zSHIORI",
    value: ?[]const u8 = null,
    value_notify: ?[]const u8 = null,
    security_level: ?SecurityLevel = null,
    marker: ?[]const u8 = null,
    errors: ?[]const Error = null,
    balloon_offset: ?BalloonOffset = null,
    references: ?References = null,
    age: ?u32 = null,
    marker_send: ?[]const u8 = null,
    x_sstp_passthru: ?XSstpPassThru = null,

    /// `references`と`x_sstp_passthru`を解放します。どちらも`null`の場合noopです。
    pub fn deinit(self: @This(), allocator: Allocator) void {
        if (self.references) |*references| {
            references.deinit(allocator);
        }
        if (self.x_sstp_passthru) |*x_sstp_passthru| {
            x_sstp_passthru.deinit(allocator);
        }
    }

    pub fn format(self: @This(), writer: *Io.Writer) Io.Writer.Error!void {
        try writer.print("SHIORI/3.0 {f}\r\n", .{self.status});
        try writer.print("Charset: {s}\r\n", .{self.charset});
        try writer.print("Sender: {s}\r\n", .{self.sender});
        if (self.value) |value| {
            try writer.print("Value: {s}\r\n", .{value});
        }
        if (self.value_notify) |value_notify| {
            try writer.print("ValueNotify: {s}\r\n", .{value_notify});
        }
        if (self.security_level) |security_level| {
            try writer.print("SecurityLevel: {s}\r\n", .{@tagName(security_level)});
        }
        if (self.marker) |marker| {
            try writer.print("Marker: {s}\r\n", .{marker});
        }
        if (self.errors) |errors| {
            if (errors.len > 0) {
                try writer.writeAll("ErrorLevel: ");
                for (errors, 0..) |err, i| {
                    try writer.print("{s}", .{@tagName(err.level)});
                    if (i < errors.len - 1) {
                        try writer.writeByte('\x01');
                    }
                }
                try writer.writeAll("\r\n");
                try writer.writeAll("ErrorDescription: ");
                for (errors, 0..) |err, i| {
                    try writer.print("{s}", .{err.description});
                    if (i < errors.len - 1) {
                        try writer.writeByte('\x01');
                    }
                }
                try writer.writeAll("\r\n");
            }
        }
        if (self.balloon_offset) |ballon_offset| {
            try writer.print("BalloonOffset: {f}\r\n", .{ballon_offset});
        }
        if (self.references) |references| {
            var iterator = references.iterator();
            while (iterator.next()) |reference| {
                try writer.print("Reference{d}: {s}\r\n", .{ reference.key_ptr.*, reference.value_ptr.* });
            }
        }
        if (self.age) |age| {
            try writer.print("Age: {d}\r\n", .{age});
        }
        if (self.marker_send) |marker_send| {
            try writer.print("MarkerSend: {s}\r\n", .{marker_send});
        }
        if (self.x_sstp_passthru) |x_sstp_passthru| {
            var iterator = x_sstp_passthru.iterator();
            while (iterator.next()) |reference| {
                try writer.print("X-SSTP-PassThru-{s}: {s}\r\n", .{ reference.key_ptr.*, reference.value_ptr.* });
            }
        }

        try writer.writeAll("\r\n");
    }

    /// レスポンスをレンダーします。OutOfMemoryの場合エラーを委託します。
    pub fn renderFailable(self: @This(), allocator: Allocator) error{OutOfMemory}![:0]const u8 {
        var awriter: Io.Writer.Allocating = .init(allocator);
        defer awriter.deinit();
        const writer = &awriter.writer;

        writer.print("{f}", .{self}) catch return error.OutOfMemory;

        return try awriter.toOwnedSliceSentinel(0);
    }

    /// レスポンスをレンダーします。OutOfMemoryの場合、既定のエラーレスポンスを返します。
    pub fn render(self: @This(), allocator: std.mem.Allocator) [:0]const u8 {
        return self.renderFailable(allocator) catch OOM_ERROR_RESPONSE;
    }
};

test "Test ResponseRaw rendering" {
    const allocator = std.testing.allocator;

    var resp: ResponseRaw = .{};
    defer resp.deinit(allocator);

    try resp.headers.put(allocator, "Charset", "UTF-8");
    try resp.headers.put(allocator, "Sender", "zSHIORI");

    const expected = "SHIORI/3.0 204 No Content\r\nCharset: UTF-8\r\nSender: zSHIORI\r\n\r\n";

    const rendered = try resp.renderFailable(allocator);
    defer allocator.free(rendered);

    try std.testing.expectEqualStrings(expected, rendered);
}

test "Test default Response rendering" {
    const allocator = std.testing.allocator;

    const resp: Response = .{};

    const expected = "SHIORI/3.0 204 No Content\r\nCharset: UTF-8\r\nSender: zSHIORI\r\n\r\n";

    const rendered = try resp.renderFailable(allocator);
    defer allocator.free(rendered);

    try std.testing.expectEqualStrings(expected, rendered);
}

test "Test simple Response rendering" {
    const allocator = std.testing.allocator;

    const resp = Response{
        .status = .ok,
        .value = "\\1\\s[10]\\0\\s[0]\\e",
    };

    const expected = "SHIORI/3.0 200 OK\r\nCharset: UTF-8\r\nSender: zSHIORI\r\nValue: \\1\\s[10]\\0\\s[0]\\e\r\n\r\n";

    const rendered = try resp.renderFailable(allocator);
    defer allocator.free(rendered);

    try std.testing.expectEqualStrings(expected, rendered);
}

test "Test complex Response rendering" {
    const allocator = std.testing.allocator;

    var references: References = .empty;
    defer references.deinit(allocator);

    try references.put(allocator, 0, "GhostName");
    try references.put(allocator, 1, "Information");

    const resp = Response{
        .status = .ok,
        .value = "\\1\\s[10]\\0\\s[0]\\e",
        .security_level = .local,
        .marker = "foo",
        .errors = &.{
            .{ .level = .info, .description = "This is info" },
            .{ .level = .notice, .description = "This is notice" },
        },
        .balloon_offset = .{ .x = 1, .y = 2 },
        .references = references,
        .age = 123,
        .marker_send = "bar",
    };

    const expected = "SHIORI/3.0 200 OK\r\nCharset: UTF-8\r\nSender: zSHIORI\r\nValue: \\1\\s[10]\\0\\s[0]\\e\r\nSecurityLevel: local\r\nMarker: foo\r\nErrorLevel: info\x01notice\r\nErrorDescription: This is info\x01This is notice\r\nBalloonOffset: (1,2)\r\nReference0: GhostName\r\nReference1: Information\r\nAge: 123\r\nMarkerSend: bar\r\n\r\n";

    const rendered = try resp.renderFailable(allocator);
    defer allocator.free(rendered);

    try std.testing.expectEqualStrings(expected, rendered);
}

test "Test OutOfMemory response" {
    const allocator = std.testing.failing_allocator;
    var resp = Response{};

    const rendered = resp.render(allocator);

    try std.testing.expectEqualStrings(OOM_ERROR_RESPONSE, rendered);
}
