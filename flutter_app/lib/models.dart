import 'config.dart';
import 'date_parser.dart';
import 'text_fold.dart';

/// Sản phẩm: mã vạch (có thể trống), tên, giá bán (theo sản phẩm — mọi date cùng giá).
class Product {
  final String barcode;
  final String name;
  final int price;

  const Product({this.barcode = '', required this.name, this.price = 0});

  factory Product.fromJson(Map<String, dynamic> j) =>
      Product(barcode: _s(j['barcode']), name: _s(j['name']), price: priceValue(j['price']) ?? 0);

  /// Khoá sản phẩm giống server: mã vạch nếu có, không thì tên.
  String get key => productKey(barcode, name);
}

/// UPC-A 12 số = EAN-13 có số 0 đầu.
String normBarcode(String s) {
  final b = s.replaceAll(RegExp(r'\s+'), '');
  return RegExp(r'^\d{12}$').hasMatch(b) ? '0$b' : b;
}

String productKey(String barcode, String name) {
  final b = normBarcode(barcode);
  return b.isNotEmpty ? 'b:$b' : 'n:${normKey(name)}';
}

class Lot {
  final String id;
  final String hsd; // yyyy-MM-dd
  final int qty;
  final bool le;
  const Lot({required this.id, required this.hsd, required this.qty, this.le = false});

  factory Lot.fromJson(Map<String, dynamic> j) =>
      Lot(id: _s(j['id']), hsd: _s(j['hsd']), qty: _i(j['qty']), le: _b(j['le']));
}

/// Một dòng của sheet `TonKho`: một date của một sản phẩm, hàng lốc hoặc hàng lẻ ([le]).
/// `product.price` là giá của đúng loại đó (giá lốc / giá lẻ).
class InventoryRow {
  final String id;
  final Product product;
  final String hsd;
  final int qty;
  final bool le;

  const InventoryRow({required this.id, required this.product, required this.hsd, required this.qty, this.le = false});

  /// Dạng mảng của `snapshot`: [id, barcode, name, hsd, qty, price, le (0/1)].
  factory InventoryRow.fromList(List<dynamic> r) => InventoryRow(
        id: _s(r[0]),
        product: Product(barcode: _s(r[1]), name: _s(r[2]), price: r.length > 5 ? priceValue(r[5]) ?? 0 : 0),
        hsd: _s(r[3]),
        qty: _i(r[4]),
        le: r.length > 6 && _b(r[6]),
      );

  List<dynamic> toList() => [id, product.barcode, product.name, hsd, qty, product.price, le ? 1 : 0];

  InventoryRow copyWith({Product? product, String? hsd, int? qty}) =>
      InventoryRow(id: id, product: product ?? this.product, hsd: hsd ?? this.hsd, qty: qty ?? this.qty, le: le);
}

class LookupResult {
  final bool found;

  /// `product.price` = giá lốc; [priceLe] = giá lẻ.
  final Product? product;
  final int priceLe;
  final List<Lot> lots;
  const LookupResult({required this.found, this.product, this.priceLe = 0, this.lots = const []});
}

/// Giá trị app đã thấy, gửi kèm lệnh sửa để server phát hiện xung đột.
class Expect {
  final String barcode;
  final String hsd;
  final int qty;
  const Expect(this.barcode, this.hsd, this.qty);
  Map<String, dynamic> toJson() => {'barcode': barcode, 'hsd': hsd, 'qty': qty};
}

enum ExpiryStatus { expired, near, ok, unknown }

/// Số ngày còn lại theo ngày lịch (âm = đã hết hạn).
int? daysLeft(String hsd, DateTime now) {
  final d = parseIso(hsd);
  if (d == null) return null;
  return DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;
}

/// Đỏ = đã hết hạn, vàng = còn ≤ 90 ngày (Config.nearExpiryDays).
ExpiryStatus expiryStatus(String hsd, DateTime now) {
  final n = daysLeft(hsd, now);
  if (n == null) return ExpiryStatus.unknown;
  if (n < 0) return ExpiryStatus.expired;
  if (n <= Config.nearExpiryDays) return ExpiryStatus.near;
  return ExpiryStatus.ok;
}

String _s(dynamic v) => v == null ? '' : v.toString().trim();
bool _b(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';
int _i(dynamic v) => v is num ? v.toInt() : int.tryParse(_s(v).replaceAll(RegExp(r'[^\d-]'), '')) ?? 0;
