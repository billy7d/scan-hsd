# Build app cho iPhone 15 Pro Max (trên máy Mac)

Code dùng chung với Android; chỉ bước build cần Mac. Quét mã trên iPhone dùng Apple Vision (iOS ≥ 12).

## Chuẩn bị (một lần)

1. **Xcode** từ App Store (bản mới nhất), mở một lần để cài thành phần bổ sung.
2. **Flutter** cho macOS: <https://docs.flutter.dev/get-started/install/macos> (giải nén, thêm `flutter/bin` vào PATH).
3. **CocoaPods**: `sudo gem install cocoapods` (hoặc `brew install cocoapods`).
4. Kiểm tra: `flutter doctor` — mục Xcode và CocoaPods phải ✓.

## Lấy project sang Mac

Chép cả thư mục `E:\Scan-HSD\flutter_app` sang Mac (USB, Drive, AirDrop…). **Nhớ chép cả `lib/config.dart`** (file chứa URL + key, không có trên git).

## Build và cài lên iPhone

```bash
cd flutter_app
flutter pub get
open ios/Runner.xcworkspace
```

Trong Xcode:
1. Chọn **Runner** (cột trái) → tab **Signing & Capabilities** → **Team**: đăng nhập Apple ID của bạn.
2. Đổi **Bundle Identifier** thành tên riêng, ví dụ `vn.traphuong.khoandam` (phải duy nhất).
3. Cắm iPhone bằng cáp, trên iPhone bấm **Tin cậy máy tính này**. Bật **Chế độ nhà phát triển** (Cài đặt > Quyền riêng tư & Bảo mật > Chế độ nhà phát triển) nếu được hỏi.
4. Chọn iPhone ở thanh trên cùng → bấm ▶ (hoặc trong Terminal: `flutter run --release`).
5. Lần đầu: trên iPhone vào **Cài đặt > Cài đặt chung > Quản lý VPN & thiết bị** → tin cậy tài khoản nhà phát triển.

## Lưu ý tài khoản Apple

- **Apple ID miễn phí**: app chạy được **7 ngày**, sau đó cắm lại Mac và bấm ▶ để cài lại.
- **Apple Developer (99 USD/năm)**: cài lâu dài, có thể phát qua **TestFlight** cho nhiều máy không cần cắm cáp.
