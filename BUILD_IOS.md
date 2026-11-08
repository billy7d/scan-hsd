# Cài lại app Kho ăn dặm lên iPhone (từ MacBook)

App cài bằng Apple ID miễn phí chỉ dùng được **7 ngày**. Hết hạn thì app không mở được nữa, chỉ cần cài lại theo **Cách 1**.

Máy này đã cài sẵn đủ công cụ và đã cài đặt tài khoản Apple, nên **không cần** cài đặt gì thêm.

> ⚠️ **Đừng xoá app trên iPhone và đừng dùng lệnh `flutter install`** (lệnh này tự gỡ app cũ). Gỡ app sẽ làm mất **hoá đơn chưa xuất ảnh** và **số hộp / lốc đã nhớ**, vì hai thứ này chỉ lưu trên iPhone. Hàng tồn kho nằm trên Google Sheet nên không bị ảnh hưởng. Cài đè theo hướng dẫn dưới đây thì không mất gì.

---

## Cách 1: Dùng lệnh (nên dùng)

**Bước 1.** Mở khoá iPhone và nối cáp vào MacBook. Nếu chỉ dùng Wi-Fi thì iPhone và MacBook phải cùng một mạng.

**Bước 2.** Mở Terminal: bấm `Cmd + Space`, gõ `Terminal`, bấm Enter.

**Bước 3.** Copy nguyên dòng dưới đây, dán vào Terminal, bấm Enter:

```bash
cd ~/Documents/KhoAnDam && git pull && cd flutter_app && flutter pub get && flutter run --release --no-resident -d 00008130
```

**Bước 4.** Chờ từ vài chục giây đến vài phút và giữ iPhone mở khoá. Xong khi Terminal hiện lại dấu nhắc để gõ lệnh. Bình thường app sẽ tự mở trên iPhone; nếu không thấy app hiện lên hoặc app đóng lại ngay (nhất là khi màn hình iPhone đang tắt), chỉ cần chạm vào biểu tượng app để mở.

**Bước 5.** Xem ngày hết hạn mới:

```bash
date -r $(security cms -D -i ~/Documents/KhoAnDam/flutter_app/build/ios/iphoneos/Runner.app/embedded.mobileprovision | plutil -extract ExpirationDate raw -o - - | xargs -I{} date -j -u -f '%Y-%m-%dT%H:%M:%SZ' {} +%s) '+App hết hạn lúc %H:%M ngày %d/%m/%Y'
```

> Cài lại khi chưa hết hạn có thể **chưa được thêm 7 ngày**, vì Xcode dùng lại giấy phép cũ cho đến khi nó hết hạn. Vì vậy hãy luôn xem ngày ở Bước 5, đừng tự tính.

**Chỉ muốn cài lại bản đang có trên máy, không lấy code mới** (hoặc đang không có mạng để `git pull`):

```bash
cd ~/Documents/KhoAnDam/flutter_app && flutter pub get && flutter run --release --no-resident -d 00008130
```

---

## Cách 2: Bấm trong Xcode (khi Cách 1 báo lỗi ký app)

**Bước 1.** Chạy lệnh sau trong Terminal, Xcode sẽ tự mở đúng project:

```bash
cd ~/Documents/KhoAnDam/flutter_app && flutter pub get && flutter build ios --config-only --release && open ios/Runner.xcworkspace
```

**Bước 2. Kiểm tra tài khoản ký app**

1. Ở cột bên trái, bấm biểu tượng thư mục rồi bấm **Runner** (dòng trên cùng, biểu tượng màu xanh).
2. Ở cột giữa, mục **TARGETS**, chọn **Runner**.
3. Mở tab **Signing & Capabilities** và kiểm tra:
   - **Automatically manage signing**: có dấu tick.
   - **Team**: `Lan Phương (Personal Team)`.
   - **Bundle Identifier**: `vn.traphuong.khoandam`. **Không đổi dòng này**, đổi là iPhone coi như một app mới và mất dữ liệu trên máy.
4. Không còn dòng báo lỗi màu đỏ là được. Nếu có nút **Try Again**, hãy bấm nút đó.

**Bước 3. Chọn bản Release (chỉ cần làm một lần)**

1. Trên thanh menu, chọn **Product > Scheme > Edit Scheme…**
2. Ở cột trái, chọn **Run**; ở tab **Info**, đặt **Build Configuration** thành **Release**.
3. Bấm **Close**.

> Đừng bỏ qua bước này. Nếu để **Debug**, app thường không tự mở lại được từ màn hình chính iPhone sau khi rút khỏi Mac. Bước này làm file `Runner.xcscheme` hiện là đã sửa trong git; không ảnh hưởng gì đến app.

**Bước 4. Cài lên iPhone**

1. Ở thanh trên cùng của Xcode, bấm vào tên thiết bị và chọn iPhone thật **Phươnggg**, không chọn máy ảo.
2. Bấm nút **▶** (hoặc `Cmd + R`).
3. Chờ đến khi app tự mở trên iPhone.
4. Bấm nút **■** (hoặc `Cmd + .`) để dừng. App vẫn nằm trên iPhone, mở lại từ màn hình chính như bình thường.

---

## Khi gặp lỗi

| Thấy gì | Làm gì |
|---|---|
| Không thấy iPhone: `No devices found`, `No supported devices connected` | Mở khoá iPhone, cắm cáp, bấm **Tin cậy** nếu iPhone hỏi, rồi chạy `flutter devices` để xem iPhone đã hiện chưa. |
| iPhone khác, hoặc mã máy không khớp | Chạy `flutter devices`, lấy mã máy của iPhone (dạng `00008130-…`) rồi thay vào chỗ `00008130` trong lệnh. |
| `No Account for Team`, `No profiles for 'vn.traphuong.khoandam'`, `requires a development team` | Tài khoản Apple trong Xcode đã bị đăng xuất. Vào **Xcode > Settings… > Apple Accounts**, đăng nhập lại Apple ID, rồi làm **Cách 2**. |
| iPhone báo chưa tin cậy nhà phát triển, hoặc `invalid code signature` | Trên iPhone: **Cài đặt > Cài đặt chung > Quản lý VPN & thiết bị** → chọn tài khoản nhà phát triển → **Tin cậy**. |
| `Developer Mode` đang tắt | Trên iPhone: **Cài đặt > Quyền riêng tư & Bảo mật > Chế độ nhà phát triển** → bật, iPhone khởi động lại rồi xác nhận **Bật**. |
| `maximum number of apps` | Apple ID miễn phí chỉ cài được 3 app tự build trên một iPhone. Xoá app tự build **khác**, không xoá Kho ăn dặm. |
| `maximum App ID limit` | Apple ID miễn phí chỉ tạo được 10 App ID trong 7 ngày. Đừng đổi Bundle Identifier nữa, chờ vài ngày rồi thử lại. |
| `git pull` báo lỗi | Dùng lệnh "chỉ cài lại bản đang có" ở cuối Cách 1 để cài trước, xử lý git sau. |
| Thiếu file `config.dart` | File này chứa URL + key của sheet và không có trên git. Chép lại từ máy khác vào `flutter_app/lib/`, hoặc chạy `cp lib/config.example.dart lib/config.dart` trong `flutter_app` rồi điền URL + key. |
| Lỗi build lạ, chưa rõ nguyên nhân | Dọn bản build cũ (không ảnh hưởng dữ liệu trên iPhone), rồi chạy lại lệnh ở Cách 1: |

```bash
cd ~/Documents/KhoAnDam/flutter_app && flutter clean && flutter pub get
```

---

## Ghi chú

- **Code Apps Script:** `git pull` chỉ cập nhật code trên MacBook. Nếu `apps_script/Code.gs` có thay đổi, vẫn phải **Deploy** lại trên Google Apps Script (xem `HUONG_DAN.md`).
- **Không muốn cài lại mỗi tuần:** tài khoản Apple Developer (99 USD/năm) cho app dùng được lâu dài và phát qua TestFlight, không cần nối với Mac.
- **Chuyển sang máy Mac khác:** cài Xcode từ App Store, chạy `brew install --cask flutter`, chạy `git clone https://github.com/billy7d/scan-hsd.git`, chép `lib/config.dart`, rồi đăng nhập Apple ID theo Cách 2. Lần đầu nhớ bật Chế độ nhà phát triển và tin cậy tài khoản trên iPhone như bảng trên. Project dùng Swift Package Manager nên không cần CocoaPods.

Quét mã trên iPhone dùng Apple Vision (iOS ≥ 12).
