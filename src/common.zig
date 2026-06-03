// SPDX-FileCopyrightText: 2025 SyoBoN <syobon@syobon.net>
//
// SPDX-License-Identifier: UPL-1.0

const std = @import("std");

pub const Headers = std.StringArrayHashMapUnmanaged([]const u8);
pub const XSstpPassThru = std.StringArrayHashMapUnmanaged([]const u8);
pub const References = std.AutoArrayHashMapUnmanaged(u64, []const u8);

pub const SecurityLevel = enum {
    local,
    external,
};
