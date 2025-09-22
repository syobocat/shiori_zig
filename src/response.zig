// SPDX-FileCopyrightText: 2025 SyoBoN <syobon@syobon.net>
//
// SPDX-License-Identifier: UPL-1.0

const std = @import("std");
const root = @import("root.zig");

const Headers = root.Headers;
const References = root.References;
const XSstpPassThru = root.XSstpPassThru;
const SecurityLevel = root.SecurityLevel;

pub const OOM_ERROR_RESPONSE = "SHIORI/3.0 500 Internal Server Error\r\nCharset: UTF-8\r\nSender: zSHIORI\r\nErrorLevel: critical\r\nErrorDescription: Out of memory\r\n\r\n";

pub const Status = enum(u16) {
    ok = 200,
    no_content = 204,
    not_enough = 311,
    advice = 312,
    bad_request = 400,
    internal_server_error = 500,

    fn print(self: @This()) []const u8 {
        return switch (self) {
            .ok => "OK",
            .no_content => "No Content",
            .not_enough => "Not Enough",
            .advice => "Advice",
            .bad_request => "Bad Request",
            .internal_server_error => "Internal Server Error",
        };
    }
};

pub const ResponseRaw = struct {
    status: Status,
    headers: Headers,

    pub fn deinit(self: *@This()) void {
        self.headers.deinit();
    }

    /// レスポンスをレンダーします。OutOfMemoryの場合エラーを委託します。自前でエラーハンドリングをしたい場合に使用します。
    pub fn renderFailable(self: @This(), allocator: std.mem.Allocator) error{OutOfMemory}![:0]const u8 {
        var buffer = try std.ArrayList(u8).initCapacity(allocator, 0);
        defer buffer.deinit(allocator);

        const writer = buffer.writer(allocator);

        try writer.print("SHIORI/3.0 {d} {s}\r\n", .{ self.status, self.status.print() });

        var iterator = self.headers.iterator();
        while (iterator.next()) |header| {
            try writer.print("{s}: {s}\r\n", .{ header.key_ptr.*, header.value_ptr.* });
        }

        try writer.writeAll("\r\n");

        const response = try buffer.toOwnedSliceSentinel(allocator, 0);

        return response;
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

    fn print(self: @This(), allocator: std.mem.Allocator) error{OutOfMemory}![]const u8 {
        return try std.fmt.allocPrint(allocator, "({d},{d})", .{ self.x, self.y });
    }
};

pub const Response = struct {
    status: Status = .no_content,
    charset: []const u8 = "UTF-8",
    sender: []const u8 = "zSHIORI",
    value: ?[]const u8 = null,
    value_notify: ?[]const u8 = null,
    security_level: ?SecurityLevel = .local,
    marker: ?[]const u8 = null,
    errors: ?[]Error = null,
    balloon_offset: ?BalloonOffset = null,
    references: ?References = null,
    age: ?u32 = null,
    marker_send: ?[]const u8 = null,
    x_sstp_passthru: ?XSstpPassThru = null,

    /// `references`、もしくは`x_sstp_passthru`を使用した場合にのみ必要です。
    pub fn deinit(self: *@This()) void {
        if (self.references) |*references| {
            references.deinit();
        }
        if (self.x_sstp_passthru) |*x_sstp_passthru| {
            x_sstp_passthru.deinit();
        }
    }

    /// レスポンスをレンダーします。OutOfMemoryの場合エラーを委託します。自前でエラーハンドリングをしたい場合に使用します。
    pub fn renderFailable(self: @This(), gpa: std.mem.Allocator) error{OutOfMemory}![:0]const u8 {
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        const allocator = arena.allocator();

        var response = ResponseRaw{
            .status = self.status,
            .headers = Headers.init(allocator),
        };

        try response.headers.put("Charset", self.charset);
        try response.headers.put("Sender", self.sender);
        if (self.value) |value| {
            try response.headers.put("Value", value);
        }
        if (self.value_notify) |value_notify| {
            try response.headers.put("ValueNotify", value_notify);
        }
        if (self.security_level) |security_level| {
            try response.headers.put("SecurityLevel", @tagName(security_level));
        }
        if (self.marker) |marker| {
            try response.headers.put("Marker", marker);
        }
        if (self.errors) |errors| {
            var error_level = try std.ArrayList([]const u8).initCapacity(allocator, errors.len);
            var error_description = try std.ArrayList([]const u8).initCapacity(allocator, errors.len);
            for (errors) |err| {
                error_level.appendAssumeCapacity(@tagName(err.level));
                error_description.appendAssumeCapacity(err.description);
            }

            try response.headers.put("ErrorLevel", try std.mem.join(allocator, "\x01", error_level.items));
            try response.headers.put("ErrorDescription", try std.mem.join(allocator, "\x01", error_description.items));
        }
        if (self.balloon_offset) |balloon_offset| {
            try response.headers.put("BalloonOffset", try balloon_offset.print(allocator));
        }
        if (self.references) |references| {
            var iterator = references.iterator();
            while (iterator.next()) |reference| {
                try response.headers.put(try std.fmt.allocPrint(allocator, "Reference{d}", .{reference.key_ptr.*}), reference.value_ptr.*);
            }
        }
        if (self.age) |age| {
            try response.headers.put("Age", try std.fmt.allocPrint(allocator, "{d}", .{age}));
        }
        if (self.marker_send) |marker_send| {
            try response.headers.put("MarkerSend", marker_send);
        }
        if (self.x_sstp_passthru) |x_sstp_passthru| {
            var iterator = x_sstp_passthru.iterator();
            while (iterator.next()) |reference| {
                try response.headers.put(try std.fmt.allocPrint(allocator, "X-SSTP-PassThru-{s}", .{reference.key_ptr.*}), reference.value_ptr.*);
            }
        }

        return try response.renderFailable(gpa);
    }

    /// レスポンスをレンダーします。OutOfMemoryの場合、既定のエラーレスポンスを返します。
    pub fn render(self: @This(), gpa: std.mem.Allocator) [:0]const u8 {
        return self.renderFailable(gpa) catch OOM_ERROR_RESPONSE;
    }
};

test "Test simple response rendering" {
    const allocator = std.testing.allocator;

    var resp = Response{
        .status = .ok,
        .value = "\\1\\s[10]\\0\\s[0]\\e",
    };

    const expected = "SHIORI/3.0 200 OK\r\nCharset: UTF-8\r\nSender: zSHIORI\r\nValue: \\1\\s[10]\\0\\s[0]\\e\r\nSecurityLevel: local\r\n\r\n";

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
