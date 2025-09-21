// SPDX-FileCopyrightText: 2025 SyoBoN <syobon@syobon.net>
//
// SPDX-License-Identifier: UPL-1.0

const std = @import("std");

pub const Headers = std.StringArrayHashMap([]const u8);
pub const XSstpPassThru = std.StringArrayHashMap([]const u8);
pub const References = std.AutoArrayHashMap(u64, []const u8);

pub const SecurityLevel = enum {
    local,
    external,
};
