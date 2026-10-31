// Chống đọc nhầm mã vạch từ camera: kiểm tra số kiểm tra GTIN (EAN-13 / EAN-8 / UPC-A / UPC-E)
// và chỉ nhận mã khi nhiều khung hình liên tiếp đọc ra cùng một giá trị.
// iPhone (Apple Vision) đôi khi trả về mã lệch một số ở khung hình mờ, vd 5000157065759 → 9000157065759.

import 'package:mobile_scanner/mobile_scanner.dart';

final _digits = RegExp(r'^\d+$');

/// Số kiểm tra GTIN (mod 10, trọng số 3-1-3… tính từ phải) của dãy số chưa có số kiểm tra.
int gtinCheckDigit(String body) {
  var sum = 0;
  for (var i = 0; i < body.length; i++) {
    final d = body.codeUnitAt(body.length - 1 - i) - 48;
    sum += i.isEven ? d * 3 : d;
  }
  return (10 - sum % 10) % 10;
}

/// EAN-8 / UPC-A / EAN-13 / GTIN-14 có số kiểm tra đúng.
bool isValidGtin(String code) {
  if (!_digits.hasMatch(code) || ![8, 12, 13, 14].contains(code.length)) return false;
  return gtinCheckDigit(code.substring(0, code.length - 1)) == code.codeUnitAt(code.length - 1) - 48;
}

/// UPC-E 8 số (số hệ 0/1 + 6 số + số kiểm tra) → UPC-A 12 số; không phải UPC-E thì null.
String? upcEToUpcA(String e) {
  if (e.length != 8 || !_digits.hasMatch(e) || (e[0] != '0' && e[0] != '1')) return null;
  final d = e.substring(1, 7);
  final body = switch (d[5]) {
    '0' || '1' || '2' => '${d.substring(0, 2)}${d[5]}0000${d.substring(2, 5)}',
    '3' => '${d.substring(0, 3)}00000${d.substring(3, 5)}',
    '4' => '${d.substring(0, 4)}00000${d[4]}',
    _ => '${d.substring(0, 5)}0000${d[5]}',
  };
  return '${e[0]}$body${e[7]}';
}

/// Một lần đọc của camera có đáng tin không. Mã EAN/UPC sai số kiểm tra → bỏ khung hình đó.
bool isPlausibleScan(String code, BarcodeFormat format) {
  if (code.isEmpty) return false;
  switch (format) {
    case BarcodeFormat.ean13:
    case BarcodeFormat.upcA:
      return (code.length == 12 || code.length == 13) && isValidGtin(code);
    case BarcodeFormat.ean8:
      return code.length == 8 && isValidGtin(code);
    case BarcodeFormat.upcE:
      if (code.length == 8) return isValidGtin(upcEToUpcA(code) ?? '');
      return _digits.hasMatch(code) && code.length >= 6 && code.length <= 7;
    case BarcodeFormat.code128:
      return true;
    default:
      // Định dạng không rõ nhưng trông như EAN/UPC → vẫn kiểm tra số kiểm tra.
      return !_digits.hasMatch(code) || ![8, 12, 13].contains(code.length) || isValidGtin(code);
  }
}

/// Nhận mã khi cùng một giá trị xuất hiện ở [needed] khung hình liên tiếp có đọc được mã.
/// Khung hình chỉ có mã sai số kiểm tra không tính, cũng không xoá phiếu đang có.
class ScanVoter {
  final int needed;
  ScanVoter({this.needed = 3});

  Map<String, int> _streak = {};

  /// Trạng thái hiện tại: mã đang dẫn đầu và số phiếu của nó (để vẽ tiến độ).
  int get progress => _streak.values.fold(0, (m, v) => v > m ? v : m);

  /// [codes]: các mã hợp lệ trong một khung hình. Trả mã đã đủ phiếu, chưa đủ thì null.
  String? add(Iterable<String> codes) {
    final seen = codes.toSet();
    if (seen.isEmpty) return null;
    _streak = {for (final c in seen) c: (_streak[c] ?? 0) + 1};
    for (final e in _streak.entries) {
      if (e.value >= needed) return e.key;
    }
    return null;
  }

  void reset() => _streak = {};
}
