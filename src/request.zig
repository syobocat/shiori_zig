// SPDX-FileCopyrightText: 2025 SyoBoN <syobon@syobon.net>
//
// SPDX-License-Identifier: UPL-1.0

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const common = @import("common.zig");
const Headers = common.Headers;
const References = common.References;
const XSstpPassThru = common.XSstpPassThru;
const SecurityLevel = common.SecurityLevel;

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

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        self.headers.deinit(allocator);
        self.references.deinit(allocator);
        self.x_sstp_passthru.deinit(allocator);
    }
};

pub fn parseRaw(allocator: Allocator, body: []const u8) ParseError!RequestRaw {
    var split = std.mem.tokenizeSequence(u8, body, "\r\n");

    const method_line = split.next() orelse return ParseError.InvalidBody;

    const method: Method = if (std.mem.startsWith(u8, method_line, "GET SHIORI/3.0"))
        .get
    else if (std.mem.startsWith(u8, body, "NOTIFY SHIORI/3.0"))
        .notify
    else
        return ParseError.UnsupportedProtocol;

    var headers: Headers = .empty;
    var references: References = .empty;
    var x_sstp_passthru: XSstpPassThru = .empty;
    while (split.next()) |header| {
        const colon_index = std.mem.indexOfScalar(u8, header, ':') orelse continue;

        // ヘッダの形式は「HTTPと全く同じ」と述べられており、
        // HTTPではvalueの前後に空白が許容され、keyの前後には許されない
        const key = header[0..colon_index];
        const value_untrimmed = header[colon_index + 1 ..];

        const value = std.mem.trim(u8, value_untrimmed, &std.ascii.whitespace);

        if (std.mem.startsWith(u8, key, "Reference")) {
            const refnum = std.mem.trimStart(u8, key, "Reference");
            const parsed = std.fmt.parseUnsigned(u64, refnum, 10) catch continue;
            try references.put(allocator, parsed, value);
        } else if (std.mem.startsWith(u8, key, "X-SSTP-PassThuru-")) {
            const sstp_key = std.mem.trimStart(u8, key, "X-SSTP-PassThuru-");
            try x_sstp_passthru.put(allocator, sstp_key, value);
        } else {
            try headers.put(allocator, key, value);
        }
    }

    return .{
        .method = method,
        .headers = headers,
        .references = references,
        .x_sstp_passthru = x_sstp_passthru,
    };
}

const SenderTypeTag = enum {
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

pub const SenderType = packed struct {
    internal: bool = false,
    external: bool = false,
    sakuraapi: bool = false,
    embed: bool = false,
    raise: bool = false,
    property: bool = false,
    plugin: bool = false,
    sstp: bool = false,
    communicate: bool = false,
};

pub const Status = struct {
    flags: StatusFlags = .{},
    opening: ?[]const []const u8 = null,
    baloon: ?[]Baloon = null,
};

const StatusTag = enum {
    talking,
    choosing,
    minimizing,
    induction,
    passive,
    timecritical,
    nouserbreak,
    online,
};

const StatusFlags = packed struct {
    talking: bool = false,
    choosing: bool = false,
    minimizing: bool = false,
    induction: bool = false,
    passive: bool = false,
    timecritical: bool = false,
    nouserbreak: bool = false,
    online: bool = false,
};

const Baloon = struct {
    character: u32,
    baloon: u32,
};

pub const Request = struct {
    method: Method,
    headers_raw: Headers,

    sender: []const u8,
    id: []const u8,
    references: References,

    // 拡張
    charset: ?[]const u8,
    security_level: ?SecurityLevel,
    sender_type: ?SenderType,
    security_origin: ?[]const u8,
    status: ?Status,
    base_id: ?[]const u8,
    x_sstp_passthru: XSstpPassThru,

    pub fn deinit(self: *@This(), allocator: Allocator) void {
        if (self.status) |status| {
            if (status.opening) |opening| {
                allocator.free(opening);
            }
            if (status.baloon) |baloon| {
                allocator.free(baloon);
            }
        }
        self.headers_raw.deinit(allocator);
        self.references.deinit(allocator);
        self.x_sstp_passthru.deinit(allocator);
    }
};

pub fn parse(allocator: std.mem.Allocator, body: []const u8) ParseError!Request {
    const raw = try parseRaw(allocator, body);

    const sender = raw.headers.get("Sender") orelse {
        return ParseError.InvalidBody;
    };

    const id = raw.headers.get("ID") orelse {
        return ParseError.InvalidBody;
    };

    const base_id = raw.headers.get("BaseID");

    const charset = raw.headers.get("Charset");

    const sender_type = if (raw.headers.get("SenderType")) |sender_type_raw| blk: {
        var sender_type: SenderType = .{};
        var split = std.mem.splitScalar(u8, sender_type_raw, ',');
        while (split.next()) |sender_type_str| {
            if (std.meta.stringToEnum(SenderTypeTag, sender_type_str)) |tag| {
                switch (tag) {
                    .internal => sender_type.internal = true,
                    .external => sender_type.external = true,
                    .sakuraapi => sender_type.sakuraapi = true,
                    .embed => sender_type.embed = true,
                    .raise => sender_type.raise = true,
                    .property => sender_type.property = true,
                    .plugin => sender_type.plugin = true,
                    .sstp => sender_type.sstp = true,
                    .communicate => sender_type.communicate = true,
                }
            }
        }
        break :blk sender_type;
    } else null;

    const security_level = if (raw.headers.get("SecurityLevel")) |security_level|
        std.meta.stringToEnum(SecurityLevel, security_level)
    else
        null;

    const security_origin = raw.headers.get("SecurityOrigin");

    const status = if (raw.headers.get("Status")) |status_raw| blk: {
        var status: Status = .{};
        var split = std.mem.splitScalar(u8, status_raw, ',');
        while (split.next()) |status_str| {
            if (std.meta.stringToEnum(StatusTag, status_str)) |tag| {
                switch (tag) {
                    .talking => status.flags.talking = true,
                    .choosing => status.flags.choosing = true,
                    .minimizing => status.flags.minimizing = true,
                    .induction => status.flags.induction = true,
                    .passive => status.flags.passive = true,
                    .timecritical => status.flags.timecritical = true,
                    .nouserbreak => status.flags.nouserbreak = true,
                    .online => status.flags.online = true,
                }
            } else if (std.mem.startsWith(u8, status_str, "opening(")) {
                var opening: ArrayList([]const u8) = .empty;
                defer opening.deinit(allocator);

                const trimed_1 = std.mem.trimStart(u8, status_str, "opening(");
                const trimed_2 = std.mem.trimEnd(u8, trimed_1, ")");
                var iter = std.mem.splitScalar(u8, trimed_2, '/');
                while (iter.next()) |item| {
                    try opening.append(allocator, item);
                }

                status.opening = try opening.toOwnedSlice(allocator);
            } else if (std.mem.startsWith(u8, status_str, "balloon(")) {
                var baloon: ArrayList(Baloon) = .empty;
                defer baloon.deinit(allocator);

                const trimed_1 = std.mem.trimStart(u8, status_str, "baloon(");
                const trimed_2 = std.mem.trimEnd(u8, trimed_1, ")");
                var iter = std.mem.splitScalar(u8, trimed_2, '/');
                while (iter.next()) |item| {
                    const equal_index = std.mem.indexOfScalar(u8, item, '=') orelse continue;
                    const cid_str = item[0..equal_index];
                    const bid_str = item[equal_index + 1 ..];
                    const cid = std.fmt.parseUnsigned(u32, cid_str, 10) catch continue;
                    const bid = std.fmt.parseUnsigned(u32, bid_str, 10) catch continue;
                    try baloon.append(allocator, .{ .character = cid, .baloon = bid });
                }

                status.baloon = try baloon.toOwnedSlice(allocator);
            }
        }
        break :blk status;
    } else null;

    return .{
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
    var parsed = try parse(allocator, body);
    defer parsed.deinit(allocator);

    try std.testing.expectEqualStrings("UTF-8", parsed.charset.?);
    try std.testing.expectEqualStrings("SSP", parsed.sender);
    try std.testing.expectEqual(SenderType{ .internal = true, .raise = true }, parsed.sender_type.?);
    try std.testing.expectEqual(StatusFlags{ .choosing = true }, parsed.status.?.flags);
    try std.testing.expectEqualSlices(Baloon, &.{.{ .baloon = 0, .character = 0 }}, parsed.status.?.baloon.?);
    try std.testing.expectEqualStrings("OnFirstBoot", parsed.id);
    try std.testing.expectEqualStrings("OnBoot", parsed.base_id.?);
    try std.testing.expectEqualStrings("1", parsed.references.get(0).?);
}
