// Mẫu cấu hình. Chép thành `config.dart` rồi điền giá trị thật.
// `config.dart` nằm trong .gitignore — không đưa key thật lên git.

class Config {
  /// URL Web App sau khi Deploy Apps Script (kết thúc bằng /exec).
  static const scriptUrl = 'https://script.google.com/macros/s/DIEN_ID_VAO_DAY/exec';

  /// Phải trùng API_KEY trong Code.gs.
  static const apiKey = 'DOI_KEY_NAY';


  /// Tô vàng khi còn ≤ số ngày này (đỏ = đã hết hạn).
  static const nearExpiryDays = 90;

  /// Bản sao dữ liệu trên máy cũ hơn mức này thì tự tải lại.
  static const snapshotMaxAge = Duration(minutes: 10);
}
