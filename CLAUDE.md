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

Sheet `TonKho` (A→F): **Mã vạch | Tên sản phẩm | Date (HSD) | Số lượng | Giá bán | ID** (ID ẩn, bảo vệ chỉ cảnh báo — để sửa đúng dòng kể cả khi sheet bị sắp xếp lại). Mỗi dòng = một date của một sản phẩm. Date ghi lúc 12:00 trưa để không lệch ngày giữa múi giờ.

API (mọi request kèm `key`; ghi bọc `LockService`; mọi lệnh ghi gọi `damBaoId_` trước):
- `GET ?action=lookup&barcode=` → `{found, product:{barcode,name,price}, lots:[{id,hsd,qty}]}`
- `GET ?action=snapshot` → `{rows:[[id, barcode, name, hsd, qty, price]]}`
- `POST add {barcode?, name, price, lots:[{hsd,qty}], confirmMerge}` → `{results:[{hsd, status: created|duplicate|merged, id, currentQty?, newQty?}]}`; tên/giá khác bản đang lưu → cập nhật mọi date của sản phẩm.
- `POST adjust {id, expect:{barcode,hsd,qty}, delta}` → `updated|conflict|notFound`
- `POST updateLot {id, expect, hsd?, qty?, confirmMerge}` → `updated|duplicate|merged|conflict|notFound`
- `POST deleteLot {id, expect}` → `deleted|conflict|notFound`
- `POST updateProduct {barcode? | oldName, name, price}` → `updated (rowsChanged)|notFound`

App giữ bản sao sheet trên máy (`inventory_cache.dart`, file JSON) → đọc/tìm tức thì; làm mới khi mở app, kéo xuống, sau khi ghi, hoặc cũ > 10 phút; đọc theo mã luôn hỏi lại sheet ngầm.

## 4. Hiện trạng file (2026-10-23)

Môi trường Windows: Flutter 3.47.7 tại `D:\dev\flutter`, Android SDK `D:\dev\android-sdk`, JDK 17 `D:\dev\jdk17`, `PUB_CACHE=D:\dev\pub-cache`, `GRADLE_USER_HOME=D:\dev\gradle-home` (ổ C gần đầy).

| File | Nội dung |
|---|---|
| `apps_script/Code.gs` | Bản 6 cột. `caiDat()` tạo/chuyển sheet (xoá tiêu đề thừa của bản 12 cột, chuyển bảo vệ ID sang cột F, ẩn cột F, tô màu ≤ 90 ngày). |
| `apps_script/test/code_gs.test.js` | 13 test Node giả lập SpreadsheetApp. |
| `flutter_app/lib/main.dart` | Màn chính: 2 nút lớn GHI / ĐỌC, ô tìm theo tên, đếm ≤ 90 ngày / hết hạn, ghi hàng không mã. |
| `lib/scanner_screen.dart` | Quét + công tắc Ghi/Đọc + `scanLoop()` quét liên tục. |
| `lib/entry_screen.dart` | GHI: tên, giá, nhiều dòng date + số lượng, hỏi cộng dồn (trước khi gửi và khi sheet báo trùng). |
| `lib/lookup_screen.dart` | ĐỌC: `SearchScreen`, `ProductScreen`, `LotCard` (−/+ gom lệnh), sửa date/tên/giá, xoá date. |
| `lib/inventory_cache.dart` | Bản sao sheet, `search()` (tên gần đúng `nameMatchScore`, mã/đuôi mã), lọc HSD. |
| `lib/api.dart`, `models.dart`, `date_parser.dart` (định dạng ngày/giá), `text_fold.dart`, `ui.dart`, `config.dart` (gitignore; mẫu `config.example.dart`). |
| `tool/live_test.dart` | Thử ghi thật lên sheet rồi dọn sạch: `dart run tool/live_test.dart` (cần Code.gs mới đã Deploy). |
| `test/*.dart` | 14 test: định dạng, tô màu 90 ngày, khoá mã/tên, tìm gần đúng, bản sao sheet. |
| `HUONG_DAN.md`, `BUILD_IOS.md` | Cài đặt Google Sheet; build iPhone trên Mac. |

`flutter analyze` sạch, `flutter test` qua, APK arm64 ≈ 25 MB (`KhoAnDam.apk`). Android: `kotlin.incremental=false` trong `android/gradle.properties` (project ổ E, cache ổ D). iOS: Info.plist có `NSCameraUsageDescription`; **build cần Mac** (xem `BUILD_IOS.md`).

**2026-10-23**: người dùng chuyển sang sheet ở **tài khoản Google khác**, deploy mới (URL mới trong `config.dart`, key mới). `tool/live_test.dart` chạy trên sheet thật: mọi bước qua (ghi nhiều date ~2,7 s, đọc ~1,6 s, −/+ ~2,6 s), sheet đã dọn sạch. **Chưa làm**: thử trên S24 Ultra; build iPhone trên Mac (`BUILD_IOS.md`, nhớ chép `lib/config.dart`).

## 5. Lịch sử (bản 1, đã bỏ 2026-10-23)

Bản 1 có: 12 cột (vị, trọng lượng, bảo quản, thành phần…), OCR HSD (kể cả chữ in chấm), danh mục tham khảo từ Excel, Open Food Facts, đoán tên/vị từ ảnh mặt trước. Code nằm trong lịch sử phiên làm việc, đã xoá khỏi project theo yêu cầu rút gọn. Nếu người dùng muốn lấy lại tính năng nào, hỏi trước.
