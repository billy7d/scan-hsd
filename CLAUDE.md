# Dự án: App quét kho đồ ăn dặm (Kho ăn dặm) — bản 2 (rút gọn)

Tài liệu bàn giao cho agent. Đọc hết trước khi làm. Trả lời người dùng bằng tiếng Việt.

## 1. Bối cảnh

Chủ shop bán đồ ăn dặm nhập khẩu (hàng Anh: Heinz, Ella's Kitchen, Organix, HiPP, Kendamil, Cerelac, Kiddylicious, Aptamil… — danh sách shop ở metraphuong.com, cần quyền truy cập qua Facebook Group). Quản lý kho trên **1 Google Sheet**. App điện thoại quét mã vạch để **ghi** (nhập hàng) và **đọc** (tra cứu, sửa số lượng). Thiết bị chính: **iPhone 15 Pro Max** và **Samsung S24 Ultra**.

## 2. Yêu cầu đã chốt (2026-10-23 — thay toàn bộ phạm vi bản 1)

- **Dữ liệu chỉ còn**: Tên sản phẩm, Date (HSD), Số lượng, Giá bán. Mã vạch là khoá định vị sản phẩm. Bỏ hẳn: vị, trọng lượng, bảo quản, thành phần, số lô, ngày nhập; bỏ danh mục tham khảo, Open Food Facts, đoán tên/vị từ ảnh, **không còn nút "Chụp HSD"** (người dùng chọn date trên lịch).
- **Ghi**: quét mã → mã đã có thì điền sẵn tên + giá; mã mới thì nhập tên + giá một lần → nhập **một hoặc nhiều date**, mỗi date một số lượng, lưu một lần. Cùng mã + cùng date → hỏi cộng dồn. Cùng mã khác date → dòng riêng.
- **Hàng không mã vạch vẫn ghi được**: nhận diện theo **tên** (không phân biệt hoa thường, bỏ khoảng trắng thừa); có danh sách chọn sản phẩm không mã đã có.
- **Giá bán theo sản phẩm**: mọi date của một sản phẩm cùng giá; sửa tên/giá áp dụng cho mọi date.
- **Đọc**: theo mã vạch (quét camera, phải **trùng khớp** mã đã ghi; UPC-A 12 số = EAN-13 có số 0 đầu) hoặc theo **tên gần đúng** (không dấu, sai 1–2 chữ, gõ đầu chữ). Hiện **đủ mọi date** của sản phẩm, gần hết hạn trước.
- **Sửa số lượng nhanh** trên mỗi date: nút −5 / −1 / +1 / +5, chạm số để gõ; số đổi ngay trên màn hình, các lần bấm trong ~1,2 giây gom thành một lệnh gửi sheet; lỗi → số quay lại; về 0 → hỏi xoá date. Có sửa date, xoá date, sửa tên/giá.
- **Tô màu**: đỏ nhạt = đã hết hạn, **vàng = còn ≤ 90 ngày**.
- Miễn phí, không dịch vụ trả phí. Không đưa `API_KEY` thật lên git công khai.

## 3. Kiến trúc

```
[App Flutter, Android + iOS] --quét mã (mobile_scanner: ML Kit trên Android, Apple Vision trên iOS ≥ 12)
                             --HTTP JSON--> [Google Apps Script Web App] --> [Google Sheet "TonKho"]
```

Sheet `TonKho`, 6 cột **tìm theo tên tiêu đề ở dòng 1** (không theo vị trí — chủ shop được chèn cột tự nhập, đổi thứ tự): **Mã vạch | Tên sản phẩm | Date (HSD) | Số lượng | Giá bán | ID** (ID ẩn, bảo vệ chỉ cảnh báo — để sửa đúng dòng kể cả khi sheet bị sắp xếp lại). Mỗi dòng = một date của một sản phẩm. Date ghi lúc 12:00 trưa để không lệch ngày giữa múi giờ.

Giá bán (2026-11-05): số nguyên 0..10.000.000 ₫ (`MAX_PRICE` trong Code.gs = `maxPrice` trong `date_parser.dart`). Sheet cũ từng có ID 8 ký tự nằm trong cột giá (vd. `9a0649ba`, `59970494`, `2.6E+58`) → đọc ra 0; `damBaoGia_` (chạy cùng `damBaoId_` trước mỗi lệnh ghi/snapshot) tự sửa ô rác: lấy giá date khác cùng sản phẩm, không có thì để trống; chữ "140.000" → số. `add` với giá trống/0 **giữ giá đang lưu**; đặt giá 0 thì dùng `updateProduct`. Giá sai / > max → lỗi, không ghi.

Hàng lẻ (tách lốc, 2026-11-05): cột tuỳ chọn **"Loại"** (`LOAI_HEADER`, `damBaoCotLoai_` tự thêm vào cuối trước mỗi lệnh ghi/snapshot) — ghi `Lẻ` cho hàng lẻ, trống = nguyên lốc (dữ liệu cũ đều là lốc). Hàng lẻ là dòng riêng, chung mã + tên với hàng lốc; trùng date và giá tính theo `unitKey_` (sản phẩm + loại). Tên sửa cho cả hai loại, giá theo từng loại. App gộp lốc + lẻ của một mã vào một `ProductSummary` (`lotRows`/`leRows`, `priceLe`, `totalLe`); số hộp / lốc khi mở lốc nhớ trên máy (`PackSizes`, `pack_sizes.json`), không lưu vào sheet.

API (mọi request kèm `key`; ghi bọc `LockService`; mọi lệnh ghi gọi `damBaoCotLoai_`, `damBaoId_`, `damBaoGia_` trước):
- `GET ?action=lookup&barcode=` → `{found, product:{barcode,name,price,priceLe}, lots:[{id,hsd,qty,le}]}` (price = giá lốc)
- `GET ?action=snapshot` → `{rows:[[id, barcode, name, hsd, qty, price, le(0/1)]]}`
- `POST add {barcode?, name, price, le?, lots:[{hsd,qty}], confirmMerge}` → `{results:[{hsd, status: created|duplicate|merged, id, currentQty?, newQty?}]}`; tên khác → cập nhật mọi dòng của sản phẩm; giá khác → mọi date cùng loại.
- `POST adjust {id, expect:{barcode,hsd,qty}, delta}` → `updated|conflict|notFound`
- `POST updateLot {id, expect, hsd?, qty?, confirmMerge}` → `updated|duplicate|merged|conflict|notFound`
- `POST deleteLot {id, expect}` → `deleted|conflict|notFound`
- `POST updateProduct {barcode? | oldName, name, price?, priceLe?}` → `updated (rowsChanged)|notFound` (giá bỏ trống = không đổi)
- `POST openPack {id (dòng lốc), expect, perPack, count?=1, priceLe?}` → `{status: opened, newQty (lốc), leId, leQty, created}`|`conflict|notFound`; trừ lốc, cộng `count×perPack` vào dòng lẻ cùng date (chưa có thì tạo).

App giữ bản sao sheet trên máy (`inventory_cache.dart`, file JSON) → đọc/tìm tức thì; làm mới khi mở app, kéo xuống, sau khi ghi, hoặc cũ > 10 phút; đọc theo mã luôn hỏi lại sheet ngầm.

## 4. Hiện trạng file (2026-10-23)

Môi trường Windows: Flutter 3.47.7 tại `D:\dev\flutter`, Android SDK `D:\dev\android-sdk`, JDK 17 `D:\dev\jdk17`, `PUB_CACHE=D:\dev\pub-cache`, `GRADLE_USER_HOME=D:\dev\gradle-home` (ổ C gần đầy).

| File | Nội dung |
|---|---|
| `apps_script/Code.gs` | Bản 6 cột, vị trí cột đọc từ tiêu đề (`cols_()`); thiếu tiêu đề → báo lỗi. Ghi từng ô vào đúng cột, không đụng cột tự thêm. `caiDat()` thêm tiêu đề còn thiếu vào cuối, bảo vệ + ẩn cột ID, tô màu ≤ 90 ngày. |
| `apps_script/test/code_gs.test.js` | 30 test Node giả lập SpreadsheetApp (`node apps_script/test/code_gs.test.js`), gồm đổi thứ tự cột, thiếu tiêu đề, giá rác / giá dạng chữ, hàng lẻ / mở lốc. |
| `flutter_app/lib/main.dart` | Màn chính: 2 nút lớn GHI / ĐỌC, nút HOÁ ĐƠN, ô tìm theo tên, đếm ≤ 90 ngày / hết hạn, ghi hàng không mã. |
| `lib/scanner_screen.dart` | Quét + công tắc Ghi/Đọc + `scanLoop()` quét liên tục. |
| `lib/entry_screen.dart` | GHI: tên, giá, nhiều dòng date + số lượng, hỏi cộng dồn (trước khi gửi và khi sheet báo trùng). |
| `lib/lookup_screen.dart` | ĐỌC: `SearchScreen`, `ProductScreen` (phần Nguyên lốc / Hàng lẻ), `LotCard` (−/+ gom lệnh; trừ thành công → `InvoiceStore.recordAdjust`), mở lốc, sửa date/tên/giá lốc/giá lẻ, xoá date. |
| `lib/invoice.dart` | Hoá đơn tạm trên máy (`invoices.json`), không đụng sheet. Hoá đơn tự tạo gom các lần trừ ở ĐỌC theo sản phẩm + loại (+ lại kho thì giảm dòng); hết hạn 30 phút kể từ lần trừ / sửa cuối (`InvoiceStore.ttl`), đang mở sửa/xem trước thì `hold`. Hoá đơn thủ công không tự xoá. Xuất ảnh xong → xoá hoá đơn. |
| `lib/invoice_screen.dart` | HOÁ ĐƠN: danh sách, sửa (khách, dòng: thêm từ kho / nhập tay, ship), xem trước, lưu ảnh PNG vào Thư viện (`gal`; iOS `NSPhotoLibraryAddUsageDescription`, Android `WRITE_EXTERNAL_STORAGE` ≤ API 29). |
| `lib/invoice_view.dart` | Mẫu ảnh "HOÁ ĐƠN TẠM TÍNH" rộng 400 (xuất ×3): tên shop `Đồ ăn dặm -  Trà Phương 🍼`, `0816 950 666`, tiêu đề (không in giờ), khách, bảng kẻ nét liền (Sản phẩm/SL/Đơn giá/T.tiền), Tổng, Phí ship, Tổng hoá đơn — mọi chữ màu đen. Không QR / STK / lời cảm ơn (theo yêu cầu). Giờ bấm Xuất chỉ dùng đặt tên file ảnh. |
| `lib/stock_list_screen.dart` | "Dsach tồn kho" (nút trên màn chính): bảng 3 cột STT / Tên sản phẩm / Số lượng, số lượng = tổng mọi date, thấp → cao (hết hàng đầu danh sách), bằng nhau theo tên (`InventoryCache.stockList()`). Lốc và lẻ là 2 dòng riêng, dòng lẻ ghi "Tên (Lẻ)". Mở màn là tải lại sheet. Sản phẩm đã xoá hết dòng khỏi sheet thì không còn trong danh sách, nên hộp thoại xoá date cảnh báo khi đó là date cuối cùng của sản phẩm / loại (`ProductSummary.lastDateWarning`). |
| `lib/inventory_cache.dart` | Bản sao sheet, `search()` (tên gần đúng `nameMatchScore`, mã/đuôi mã), lọc HSD. |
| `lib/api.dart`, `models.dart`, `date_parser.dart` (định dạng ngày/giá), `text_fold.dart`, `ui.dart`, `config.dart` (gitignore; mẫu `config.example.dart`). |
| `tool/live_test.dart` | Thử ghi thật lên sheet rồi dọn sạch: `dart run tool/live_test.dart` (cần Code.gs mới đã Deploy). |
| `test/*.dart` | 14 test: định dạng, tô màu 90 ngày, khoá mã/tên, tìm gần đúng, bản sao sheet. |
| `HUONG_DAN.md`, `BUILD_IOS.md` | Cài đặt Google Sheet; build iPhone trên Mac. |

`flutter analyze` sạch, `flutter test` qua, APK arm64 ≈ 25 MB (`KhoAnDam.apk`). Android: `kotlin.incremental=false` trong `android/gradle.properties` (project ổ E, cache ổ D). iOS: Info.plist có `NSCameraUsageDescription`; **build cần Mac** (xem `BUILD_IOS.md`).

**2026-10-23**: người dùng chuyển sang sheet ở **tài khoản Google khác**, deploy mới (URL mới trong `config.dart`, key mới). `tool/live_test.dart` chạy trên sheet thật: mọi bước qua (ghi nhiều date ~2,7 s, đọc ~1,6 s, −/+ ~2,6 s), sheet đã dọn sạch. **Chưa làm**: thử trên S24 Ultra; build iPhone trên Mac (`BUILD_IOS.md`, nhớ chép `lib/config.dart`).

## 5. Lịch sử (bản 1, đã bỏ 2026-10-23)

Bản 1 có: 12 cột (vị, trọng lượng, bảo quản, thành phần…), OCR HSD (kể cả chữ in chấm), danh mục tham khảo từ Excel, Open Food Facts, đoán tên/vị từ ảnh mặt trước. Code nằm trong lịch sử phiên làm việc, đã xoá khỏi project theo yêu cầu rút gọn. Nếu người dùng muốn lấy lại tính năng nào, hỏi trước.
