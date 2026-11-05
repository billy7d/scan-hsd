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
   - ẩn cột ID — đừng sửa cột này;
   - sửa cột **Giá bán**: ô đang chứa mã rác (ID cũ như `9a0649ba`, `2.6E+58 ₫`) → lấy giá date khác cùng sản phẩm, không có thì để trống để nhập lại; giá gõ tay dạng chữ "140.000" → đổi thành số.
   Không chạy `caiDat` cũng được: việc sửa cột giá tự chạy ở lần ghi / tải dữ liệu đầu tiên sau khi Deploy.
6. **Deploy > Manage deployments > ✏️ Edit > Version: New version > Deploy**. URL giữ nguyên nên không phải sửa app.

> Cột được tìm theo **tên tiêu đề ở dòng 1**, không theo vị trí: bạn có thể chèn thêm cột tự nhập ở bất kỳ đâu, kéo đổi thứ tự cột. Chỉ cần **giữ nguyên chữ** 6 tiêu đề gốc (không đổi tên, không xoá) — thiếu tiêu đề nào app sẽ báo lỗi chứ không ghi lệch cột.

**Cột "Loại"** (hàng lẻ): Apps Script tự thêm vào cuối sheet ở lần ghi / tải dữ liệu đầu tiên. Hàng lẻ ghi chữ **Lẻ**, ô trống = nguyên lốc. Đừng đổi tên tiêu đề "Loại"; nếu gõ tay thì ghi đúng chữ `Lẻ`.

**Giá bán**: số nguyên, tối đa 10.000.000 ₫. Ghi hàng mà để trống ô giá → giữ giá đang có (không bị về 0). Muốn đổi giá: nhập giá mới khi ghi, hoặc ĐỌC → ✏️ sửa tên / giá.

## 2. Cài app trên Samsung S24 Ultra

1. Chép `KhoAnDam.apk` sang điện thoại (Zalo, Drive, cáp USB…).
2. Mở file → cho phép **cài ứng dụng không rõ nguồn gốc**.
3. Lần đầu quét mã, cho phép dùng camera.

## 3. iPhone 15 Pro Max

Xem `BUILD_IOS.md` (cần máy Mac có Xcode).

## 4. Dùng app

- **GHI**: quét mã → (mã mới: nhập tên + giá) → chọn date + số lượng, bấm **Thêm date khác** nếu cùng sản phẩm có nhiều date → **Lưu**. Trùng date đã có → app hỏi cộng dồn.
- **Hàng lẻ (tách lốc)**: ở màn GHI chọn **Lẻ (tách lốc)** → nhập giá 1 hộp, date, số hộp. Hàng lẻ là dòng riêng trong sheet (date, số lượng, giá riêng), chung mã và tên với hàng lốc. Một mã có thể vừa có lốc vừa có lẻ.
- **Mở lốc**: ĐỌC → menu ⋮ trên một date lốc → **Mở lốc → bán lẻ** → chọn số lốc, "1 lốc = mấy hộp" (app nhớ cho lần sau), giá lẻ → lốc bị trừ, hàng lẻ cùng date được cộng.
- **HOÁ ĐƠN**: mỗi lần trừ số lượng ở ĐỌC (−1, −5, gõ số nhỏ hơn) app tự gom vào **hoá đơn tạm** (cùng sản phẩm cộng dồn; hàng lẻ ghi "(lẻ)"; bấm + lại thì giảm). 30 phút không trừ / sửa thêm → hoá đơn tạm tự xoá. Màn chính → **HOÁ ĐƠN**: mở hoá đơn để nhập tên khách, sửa / xoá dòng, **Thêm từ kho** hoặc **Nhập tay**, nhập **phí ship**; hoặc **Tạo hoá đơn** thủ công. Sửa hoá đơn **không** đổi số lượng trong kho. **Xuất hoá đơn** → xem trước ảnh → **Chỉnh sửa** để quay lại sửa, hoặc **Lưu ảnh** vào Thư viện ảnh; lưu xong hoá đơn bị xoá khỏi app. Lần đầu lưu ảnh, iPhone hỏi quyền thêm ảnh → cho phép.
- **Hàng không mã vạch**: màn chính → **Ghi hàng không mã vạch** → gõ tên (hoặc chọn sản phẩm không mã đã có).
- **ĐỌC**: quét mã, hoặc gõ tên gần đúng ở ô tìm (không cần dấu). Mỗi date có nút **−5 −1 +1 +5**, chạm vào số để gõ thẳng. Menu ⋮ trên mỗi date: sửa date, xoá date (date lốc có thêm Mở lốc). Mã có hàng lẻ → hiện 2 phần **Nguyên lốc** và **Hàng lẻ**, mỗi phần có giá và tổng riêng. Nút ✏️ trên cùng: sửa tên (cả lốc và lẻ), giá lốc, giá lẻ. Nút dưới cùng: **Ghi thêm lốc** / **Ghi thêm lẻ**.
