// Định dạng ngày dùng chung: 'yyyy-MM-dd' (lưu trữ) ↔ 'dd/MM/yyyy' (hiển thị).

String _p2(int n) => n.toString().padLeft(2, '0');

String formatVnDate(DateTime d) => '${_p2(d.day)}/${_p2(d.month)}/${d.year}';

String isoDate(DateTime d) => '${d.year}-${_p2(d.month)}-${_p2(d.day)}';

/// 'yyyy-MM-dd' → DateTime (giờ địa phương, 00:00); sai → null.
DateTime? parseIso(String s) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s.trim());
  if (m == null) return null;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  if (mo < 1 || mo > 12 || d < 1 || d > DateTime(y, mo + 1, 0).day) return null;
  return DateTime(y, mo, d);
}

/// 'yyyy-MM-dd' → 'dd/MM/yyyy' (giữ nguyên nếu không đọc được).
String formatIsoVn(String iso) {
  final d = parseIso(iso);
  return d == null ? iso : formatVnDate(d);
}

/// 140000 → "140.000 ₫".
String formatPrice(int vnd) {
  final s = vnd.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '$b ₫';
}
