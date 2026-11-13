# AluzSpy 1.2.3 Stable — Implementation Report

Cập nhật ngày 13/11/2026 · 23 module Lua · 8.868 dòng bundle

## Trạng thái roadmap

| Phase | Sprint | Trạng thái | Kết quả |
|---|---|---|---|
| 0 — Cầm máu | Sprint 0 | **Xong** | 6/6 lỗi runtime đã sửa và có test |
| 1 — Nền tảng | Sprint 1–2 | **Xong (một phần)** | Testkit headless trong repo, đo bộ nhớ thật, self-tune |
| 2 — Hook Engine v2 | Sprint 3–4 | **Xong** | Registry, retry/backoff, restore, 1 capture path, HttpPost, re-resolve |
| 3 — Dump Engine v2 | Sprint 5–6 | **Xong** | Ngân sách 4 lớp, LRU evict, quota thu hồi, writer qua hàng đợi, disassembler Lua 5.1 |
| 4 — Phát hành | Sprint 7 | **Một phần** | Manifest + bundle hash + dependency check; CI ngoài repo |

## 6 lỗi runtime đã sửa (R-01 … R-06)

| ID | Trước | Sau |
|---|---|---|
| R-01 | Chặn 96 MB tổng dung lượng dump chết (logic nằm trong hàm đã bị ghi đè) | `D.writeOne` kiểm tra `K.DUMP_TOTAL` và `D.evictTotal()` xoá file cũ nhất. Test T1: `D.bytes=80166 ≤ cap 100000` |
| R-02 | Sau 750 script là kẹt vĩnh viễn | Hạn ngạch tính từ tập script còn sống, tự thu hồi khi script bị GC. Test T2: `reclaimAfterRelease=true` |
| R-03 | `X.memNow` không bao giờ được gán → mọi ngưỡng bộ nhớ chết | Đo thật bằng `collectgarbage("count")` mỗi 30 frame. Test T3: `X.memNow=4902 KB` |
| R-04 | `vip("scan")` không bao giờ deobfuscate | `vip.lua` gọi `F.api.deobAll`; thêm alias `deobfAll`. Test T4/T5 |
| R-05 | 3 lệnh trong README không tồn tại | Đã hiện thực `deobf`, `deobfAll`, `reverseFind`; `split` có thật. Smoke test: `missing (documented but absent): none` |
| R-06 | `stageReport()` in `err=true` cho stage thành công | Tách `err` (lỗi thật) và `result` (giá trị trả về). Test T6: `nc.err=nil result=true` |

## 18 phát hiện tĩnh đã xử lý

| ID | Xử lý |
|---|---|
| F-01 | `F.hookWith` không còn khóa vĩnh viễn; thất bại thì `seenFn` được xoá và hook được thử lại với backoff |
| F-02 | Probe kiểm tra wrapper đã cài, không suy đoán từ traffic; đường fallback được đăng ký vào registry |
| F-03 | Hook của chính AluzSpy bị loại khỏi quét integrity (đánh dấu qua `F.ours`) → không còn cảnh báo giả |
| F-04 | Bỏ cửa sổ khử trùng 4 ms; mỗi lần gọi remote chỉ có **một** đường capture |
| F-05 | `HttpPost`/`HttpPostAsync` đã được hook (cả dạng method lẫn field) |
| F-06 | Global `request` được resolve lại mỗi 30 s |
| F-07 | `AluzSpy.restore()` khôi phục `__namecall`, `FireServer`, `InvokeServer`, `HttpGet`, `request` |
| F-08 | Cache fingerprint khoá theo **src + url**; tính fingerprint đúng 1 lần mỗi file |
| F-09 | Vòng giải mã có gate theo FPS và ngân sách bộ nhớ; `D.flush` có giới hạn ngân sách |
| F-10 | `D.flushBudgeted()` không còn hash đồng bộ toàn bộ job |
| F-11 | `deep.lua` dùng cơ chế override stage mới → giữ được instrumentation của `core2` |
| F-12 | Mọi file phái sinh đi qua `D.emit` → số liệu byte và quota chính xác |
| F-13 | `applyMax` không ghi đè lựa chọn tắt module của người dùng (cờ `CFG.explicit`) |
| F-14 | `F.setMod` chỉ ghi `CFG.mods=true` khi cài đặt thực sự thành công |
| F-15 | Redaction bảo vệ chuỗi phiên bản (`1.2.3.4` còn nguyên, IP thật vẫn bị che) |
| F-16 | `vip redact` đã bao gồm `FullScripts` và `Index` |
| F-17 | `F.api.split` hiện thực thật thay vì stub trả `false` |
| F-18 | `F.job` nhận được cả `(timeout, prio)` lẫn `{timeout=…, prio=…}` |

## VM dump mới

Module `src/vm.lua` — disassembler Lua 5.1 tự viết:

- Đọc header bytecode (version, endianness, kích thước int/size_t/instruction/number)
- Dựng cây prototype, bảng hằng (nil/boolean/number/string/upvalue), tên upvalue, line info
- Liệt kê lệnh có tên opcode + toán hạng, `LOADK`/`GETGLOBAL` gắn luôn hằng tương ứng
- Trích toàn bộ chuỗi hằng và mọi URL tìm thấy trong bytecode
- Chấm điểm VM (số prototype, số lệnh, nhảy, bảng, closure) để biết script có bị virtualize không
- Ghi `.bytecode.txt` + `.bytecode.json` cạnh file dump
- Bắt chuỗi runtime qua `string.char` / `string.sub` / `table.concat` — bắt được chuỗi **sau khi giải mã**

## Tự điều chỉnh liên tục

- Ngân sách capture co giãn theo thời gian frame đo được (3 mức)
- Ngưỡng bộ nhớ thật, tự giảm tải khi vượt
- Dọn state cũ (netRecs, srcRecs, spam) định kỳ
- Fingerprint obfuscator được ghi nhớ qua các phiên, tăng độ tin cậy theo thời gian
- Hook lỗi tự thử lại với backoff luỹ tiến

## Kiểm thử

```bash
bash tests/run_all.sh
```

| Bộ test | Kết quả |
|---|---|
| Boot harness | `boot ok=true`, 0 warning |
| White-box (17 test) | **0 FAILED / 17** |
| API smoke test (57 lệnh) | **0 FAILURE / 57** |
| Hợp đồng API ↔ README | `missing (documented but absent): none` |
| Syntax | 23/23 module parse sạch, bundle 8.868 dòng compile sạch |

Testkit nằm trong `tests/` và chạy headless hoàn toàn: mock Roblox + executor API, không cần mạng, không cần Roblox, không cần executor thật.

## Ghi chú giới hạn

- Disassembler phục vụ Lua 5.1 (đúng định dạng bytecode của executor Roblox). Bytecode định dạng khác sẽ không parse được — báo lỗi rõ ràng thay vì crash.
- Với script đã virtualize, đầu ra là **cấu trúc lệnh + hằng + URL**, không phải source gốc. Đó là giới hạn thực tế của công cụ phân tích, đã ghi rõ trong README.
- Benchmark dùng Lua 5.3; Roblox chạy LuaJIT nhanh hơn khoảng 2–4×.
