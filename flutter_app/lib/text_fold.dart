// Bỏ dấu để tìm kiếm / so khớp: tiếng Việt (kể cả đ), Đức, Pháp, Hà Lan.

const _groups = <String, String>{
  'a': 'àáạảãâầấậẩẫăằắặẳẵäåā',
  'e': 'èéẹẻẽêềếệểễëē',
  'i': 'ìíịỉĩîïī',
  'o': 'òóọỏõôồốộổỗơờớợởỡöøō',
  'u': 'ùúụủũưừứựửữüûū',
  'y': 'ỳýỵỷỹÿ',
  'd': 'đ',
  'c': 'ç',
  'n': 'ñ',
  'ss': 'ß',
  'oe': 'œ',
  'ae': 'æ',
};

final Map<int, String> _map = () {
  final m = <int, String>{};
  _groups.forEach((base, chars) {
    for (final r in chars.runes) {
      m[r] = base;
    }
  });
  return m;
}();

/// Chữ thường, bỏ dấu, gộp khoảng trắng. `Bột ăn dặm vị Đào` → `bot an dam vi dao`.
String foldText(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    if (r >= 0x0300 && r <= 0x036F) continue; // dấu dạng tổ hợp (chuỗi chưa chuẩn hoá NFC)
    b.write(_map[r] ?? String.fromCharCode(r));
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// So sánh khoá trùng như server: không phân biệt hoa thường, bỏ khoảng trắng thừa (giữ dấu).
String normKey(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
