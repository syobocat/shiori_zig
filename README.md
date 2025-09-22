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

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

fn request(body: []const u8) [:0]const u8 {
    var req = shiori.request.parse(body, allocator) catch {
        const resp = shiori.response.Response{
            .status = .bad_request,
        };
        return resp.render(allocator);
    };
    defer req.deinit();

    const value = std.fmt.allocPrint(allocator, "\\0こんにちは、{s}ユーザーさん。\\e", .{ req.sender }) catch {
        return shiori.response.OOM_ERROR_RESPONSE;
    };

    const resp = shiori.response.Response{
        .status = .ok,
        .value = value,
    };
    return resp.render(allocator);
}
```

## 関連

- [ukadll_zig](https://github.com/syobocat/ukadll_zig/)
