<!--
SPDX-FileCopyrightText: 2025 SyoBoN <syobon@syobon.net>

SPDX-License-Identifier: CC-BY-4.0
-->

# shiori_zig

Zig用のSHIORI/3.0パーサ

## 使用例

```zig
const std = @import("std");
const shiori = @import("shiori");

fn request(arena: std.mem.Allocator, body: []const u8) [:0]const u8 {
    var req = shiori.request.parse(arena, body) catch {
        const resp = shiori.response.Response{
            .status = .bad_request,
        };
        return resp.render(arena);
    };

    const value = std.fmt.allocPrint(arena, "\\0こんにちは、{s}ユーザーさん。\\e", .{ req.sender }) catch {
        return shiori.response.OOM_ERROR_RESPONSE;
    };

    const resp = shiori.response.Response{
        .status = .ok,
        .value = value,
    };
    return resp.render(arena);
}
```

## 関連

- [ukadll_zig](https://github.com/syobocat/ukadll_zig/)
