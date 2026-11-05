# Hướng dẫn cài đặt — Kho ăn dặm (bản 2, 6 cột tìm theo tiêu đề)

## 1. Cập nhật Apps Script (bắt buộc khi chuyển từ bản cũ)

1. Mở Google Sheet → **Tiện ích mở rộng > Apps Script**.
2. Xoá hết code cũ, dán toàn bộ `apps_script/Code.gs` mới.
3. Dòng `const API_KEY = '...'` → điền **lại đúng key cũ** của bạn (key trong `flutter_app/lib/config.dart`).
4. **Ctrl+S** để lưu.
5. Chọn hàm **`caiDat`** → **Chạy**. Hàm sẽ:
   - đảm bảo có đủ 6 tiêu đề: Mã vạch | Tên sản phẩm | Date (HSD) | Số lượng | Giá bán | ID (sheet trống → ghi vào A→F; thiếu tiêu đề nào thì thêm vào cuối);
   - không xoá, không đụng tới cột bạn tự thêm;
   - định dạng giá ₫, tô **đỏ** = hết hạn, **vàng** = còn ≤ 90 ngày;
   - ẩn cột ID — đừng sửa cột này.
   Đã chạy `caiDat` từ bản trước thì không cần chạy lại.
6. **Deploy > Manage deployments > ✏️ Edit > Version: New version > Deploy**. URL giữ nguyên nên không phải sửa app.

> Cột được tìm theo **tên tiêu đề ở dòng 1**, không theo vị trí: bạn có thể chèn thêm cột tự nhập ở bất kỳ đâu, kéo đổi thứ tự cột. Chỉ cần **giữ nguyên chữ** 6 tiêu đề gốc (không đổi tên, không xoá) — thiếu tiêu đề nào app sẽ báo lỗi chứ không ghi lệch cột.

## 2. Cài app trên Samsung S24 Ultra

1. Chép `KhoAnDam.apk` sang điện thoại (Zalo, Drive, cáp USB…).
2. Mở file → cho phép **cài ứng dụng không rõ nguồn gốc**.
3. Lần đầu quét mã, cho phép dùng camera.

## 3. iPhone 15 Pro Max

Xem `BUILD_IOS.md` (cần máy Mac có Xcode).

## 4. Dùng app

- **GHI**: quét mã → (mã mới: nhập tên + giá) → chọn date + số lượng, bấm **Thêm date khác** nếu cùng sản phẩm có nhiều date → **Lưu**. Trùng date đã có → app hỏi cộng dồn.
- **Hàng không mã vạch**: màn chính → **Ghi hàng không mã vạch** → gõ tên (hoặc chọn sản phẩm không mã đã có).
- **ĐỌC**: quét mã, hoặc gõ tên gần đúng ở ô tìm (không cần dấu). Mỗi date có nút **−5 −1 +1 +5**, chạm vào số để gõ thẳng. Menu ⋮ trên mỗi date: sửa date, xoá date. Nút ✏️ trên cùng: sửa tên / giá (áp dụng mọi date).
