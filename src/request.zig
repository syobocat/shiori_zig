// SPDX-FileCopyrightText: 2025 SyoBoN <syobon@syobon.net>
//
// SPDX-License-Identifier: UPL-1.0

const std = @import("std");
const root = @import("root.zig");

const Headers = root.Headers;
const References = root.References;
const XSstpPassThru = root.XSstpPassThru;
const SecurityLevel = root.SecurityLevel;

pub const ParseError = error{
    OutOfMemory,
    UnsupportedProtocol,
    InvalidBody,
};

pub const Method = enum {
    get,
    notify,
};

pub const RequestRaw = struct {
    method: Method,
    headers: Headers,
    references: References,
    x_sstp_passthru: XSstpPassThru,

    pub fn deinit(self: *@This()) void {
        self.headers_raw.deinit();
        self.references.deinit();
        self.x_sstp_passthru.deinit();
    }
};

pub fn parseRaw(body: []const u8, allocator: std.mem.Allocator) ParseError!RequestRaw {
    var split = std.mem.tokenizeSequence(u8, body, "\r\n");

    const method_line = split.next() orelse return ParseError.InvalidBody;

    const method = if (std.mem.startsWith(u8, method_line, "GET SHIORI/3.0"))
        Method.get
    else if (std.mem.startsWith(u8, body, "NOTIFY SHIORI/3.0"))
        Method.notify
    else
        return ParseError.UnsupportedProtocol;

    var headers = Headers.init(allocator);
    var references = References.init(allocator);
    var x_sstp_passthru = XSstpPassThru.init(allocator);
    while (split.next()) |header| {
        const colon_index = std.mem.indexOfScalar(u8, header, ':') orelse continue;

        // ヘッダの形式は「HTTPと全く同じ」と述べられており、
        // HTTPではvalueの前後に空白が許容され、keyの前後には許されない
        const key = header[0..colon_index];
        const value_untrimmed = header[colon_index + 1 ..];

        const value = std.mem.trim(u8, value_untrimmed, &std.ascii.whitespace);

        if (std.mem.startsWith(u8, key, "Reference")) {
            const refnum = std.mem.trimLeft(u8, key, "Reference");
            const parsed = std.fmt.parseUnsigned(u64, refnum, 10) catch continue;
            try references.put(parsed, value);
        } else if (std.mem.startsWith(u8, key, "X-SSTP-PassThuru-")) {
            const sstp_key = std.mem.trimLeft(u8, key, "X-SSTP-PassThuru-");
            try x_sstp_passthru.put(sstp_key, value);
        } else {
            try headers.put(key, value);
        }
    }

    return .{
        .method = method,
        .headers = headers,
        .references = references,
        .x_sstp_passthru = x_sstp_passthru,
    };
}

pub const SenderType = enum {
    unknown,

    internal,
    external,
    sakuraapi,
    embed,
    raise,
    property,
    plugin,
    sstp,
    communicate,
};

// TODO: openingとballoonは値を持つので、Tagged Unionにしたい
pub const Status = enum {
    unknown,

    talking,
    choosing,
    minimizing,
    induction,
    passive,
    timecritical,
    nouserbreak,
    online,
    opening,
    balloon,
};

pub const Request = struct {
    allocator: std.mem.Allocator,

    method: Method,
    headers_raw: Headers,

    sender: []const u8,
    id: []const u8,
    references: References,

    // 拡張
    charset: ?[]const u8,
    security_level: ?SecurityLevel,
    sender_type: ?[]SenderType,
    security_origin: ?[]const u8,
    status: ?[]Status,
    base_id: ?[]const u8,
    x_sstp_passthru: XSstpPassThru,

    pub fn deinit(self: *@This()) void {
        if (self.sender_type) |*sender_type| {
            self.allocator.free(sender_type.*);
        }
        if (self.status) |*status| {
            self.allocator.free(status.*);
        }
        self.headers_raw.deinit();
        self.references.deinit();
        self.x_sstp_passthru.deinit();
    }
};

pub fn parse(body: []const u8, allocator: std.mem.Allocator) ParseError!Request {
    var raw = try parseRaw(body, allocator);

    const sender = raw.headers.get("Sender") orelse {
        return ParseError.InvalidBody;
    };

    const id = raw.headers.get("ID") orelse {
        return ParseError.InvalidBody;
    };

    const base_id = raw.headers.get("BaseID");

    const charset = raw.headers.get("Charset");

    const sender_type = if (raw.headers.get("SenderType")) |sender_type_raw| sender_type: {
        var sender_types = try std.ArrayList(SenderType).initCapacity(allocator, 9);
        var split = std.mem.splitScalar(u8, sender_type_raw, ',');
        while (split.next()) |sender_type_str| {
            if (std.meta.stringToEnum(SenderType, sender_type_str)) |sender_type| {
                try sender_types.append(allocator, sender_type);
            } else {
                try sender_types.append(allocator, SenderType.unknown);
            }
        }
        break :sender_type try sender_types.toOwnedSlice(allocator);
    } else null;

    const security_level = if (raw.headers.get("SecurityLevel")) |security_level|
        std.meta.stringToEnum(SecurityLevel, security_level)
    else
        null;

    const security_origin = raw.headers.get("SecurityOrigin");

    const status = if (raw.headers.get("Status")) |status_raw| status: {
        var statuses = try std.ArrayList(Status).initCapacity(allocator, 10);
        var split = std.mem.splitScalar(u8, status_raw, ',');
        while (split.next()) |status_str| {
            if (std.meta.stringToEnum(Status, status_str)) |status| {
                try statuses.append(allocator, status);
            } else {
                if (std.mem.startsWith(u8, status_str, "opening(")) {
                    try statuses.append(allocator, Status.opening);
                } else if (std.mem.startsWith(u8, status_str, "balloon(")) {
                    try statuses.append(allocator, Status.balloon);
                } else {
                    try statuses.append(allocator, Status.unknown);
                }
            }
        }
        break :status try statuses.toOwnedSlice(allocator);
    } else null;

    return .{
        .allocator = allocator,
        .method = raw.method,
        .headers_raw = raw.headers,
        .sender = sender,
        .id = id,
        .references = raw.references,
        .charset = charset,
        .security_level = security_level,
        .sender_type = sender_type,
        .security_origin = security_origin,
        .status = status,
        .base_id = base_id,
        .x_sstp_passthru = raw.x_sstp_passthru,
    };
}

test "Test simple request parsing" {
    const allocator = std.testing.allocator;

    const body = "GET SHIORI/3.0\r\nCharset: UTF-8\r\nSender: SSP\r\nSenderType: internal,raise\r\nSecurityLevel: local\r\nStatus: choosing,balloon(0=0)\r\nID: OnFirstBoot\r\nBaseID: OnBoot\r\nReference0: 1\r\n\r\n";
    var parsed = try parse(body, allocator);
    defer parsed.deinit();

    try std.testing.expectEqualStrings("UTF-8", parsed.charset.?);
    try std.testing.expectEqualStrings("SSP", parsed.sender);
    try std.testing.expectEqualSlices(SenderType, &.{ SenderType.internal, SenderType.raise }, parsed.sender_type.?);
    try std.testing.expectEqualSlices(Status, &.{ Status.choosing, Status.balloon }, parsed.status.?);
    try std.testing.expectEqualStrings("OnFirstBoot", parsed.id);
    try std.testing.expectEqualStrings("OnBoot", parsed.base_id.?);
    try std.testing.expectEqualStrings("1", parsed.references.get(0).?);
}
