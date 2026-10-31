import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kho_an_dam_app/inventory_cache.dart';
import 'package:kho_an_dam_app/models.dart';
import 'package:kho_an_dam_app/text_fold.dart';

InventoryRow row(String id, String barcode, String name, String hsd, int qty, [int price = 100000]) => InventoryRow(
      id: id,
      product: Product(barcode: barcode, name: name, price: price),
      hsd: hsd,
      qty: qty,
    );

void main() {
  final now = DateTime(2026, 10, 19);
  late InventoryCache cache;
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('cache_test');
    cache = InventoryCache(
      fileProvider: () async => File('${tmp.path}/snapshot.json'),
      fetcher: () async => [row('a1', '8901234564567', "Bánh Ella's dâu chuối", '2027-03-15', 2)],
    );
    cache.setRows([
      row('a1', '8901234564567', "Bánh Ella's dâu chuối", '2027-03-15', 2),
      row('a2', '8901234564567', "Bánh Ella's dâu chuối", '2026-12-30', 1), // còn 72 ngày
      row('b1', '0012345678905', 'Sữa chua Kiddylicious', '2026-10-01', 3), // đã hết hạn
      row('c1', '', 'Bánh gạo chuối', '2027-08-31', 5),
      row('d1', '4000000000017', 'Bánh quy táo Organix', '2026-12-01', 0), // hết hàng → không tính
    ], now);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('cùng mã nhiều date → một sản phẩm, date gần hết hạn trước', () {
    final s = cache.byBarcode('8901234564567')!;
    expect(s.totalQty, 3);
    expect(s.rows.map((r) => r.hsd), ['2026-12-30', '2027-03-15']);
    expect(cache.products, hasLength(4));
  });

  test('đọc bằng mã: phải trùng khớp; UPC 12 số = EAN-13', () {
    expect(cache.byBarcode('012345678905')!.product.name, 'Sữa chua Kiddylicious');
    expect(cache.byBarcode('890123456456'), isNull);
    expect(cache.byBarcode(''), isNull);
  });

  test('tìm tên gần đúng: không dấu, sai chữ, gõ đầu chữ', () {
    expect(cache.search('banh ella dau').single.product.name, "Bánh Ella's dâu chuối");
    expect(cache.search('kidylicious').single.product.name, 'Sữa chua Kiddylicious'); // thiếu 1 chữ
    expect(cache.search('sua chua kid').single.product.name, 'Sữa chua Kiddylicious'); // gõ đầu chữ
    expect(cache.search('orgnix').single.product.name, 'Bánh quy táo Organix');
    expect(cache.search('BÁNH').length, 3);
    expect(cache.search('xyz'), isEmpty);
  });

  test('tìm theo 4 số cuối mã', () => expect(cache.search('4567').single.product.barcode, '8901234564567'));

  test('lọc ≤ 90 ngày / đã hết hạn chỉ tính date còn hàng', () {
    expect(cache.nearExpiry(now: now).map((s) => s.product.name), ["Bánh Ella's dâu chuối"]);
    expect(cache.expired(now: now).map((s) => s.product.name), ['Sữa chua Kiddylicious']);
  });

  test('hàng không mã vạch', () => expect(cache.withoutBarcode.single.product.name, 'Bánh gạo chuối'));

  test('applyLookup thay đúng các date của mã đó', () {
    final res = LookupResult(
      found: true,
      product: const Product(barcode: '8901234564567', name: "Bánh Ella's dâu chuối", price: 100000),
      lots: const [Lot(id: 'a1', hsd: '2027-03-15', qty: 7)],
    );
    expect(cache.applyLookup('8901234564567', res), isTrue);
    expect(cache.byBarcode('8901234564567')!.totalQty, 7);
    expect(cache.applyLookup('8901234564567', res), isFalse);
  });

  test('refresh ghi file, load đọc lại', () async {
    await cache.refresh();
    final again = InventoryCache(fileProvider: () async => File('${tmp.path}/snapshot.json'), fetcher: () async => []);
    await again.load();
    expect(again.rows.single.id, 'a1');
    expect(again.rows.single.product.price, 100000);
  });

  test('foldText', () => expect(foldText('Bột ăn dặm vị Đào'), 'bot an dam vi dao'));

  test('nameMatchScore: khớp trùng > đầu chữ > lệch chữ', () {
    expect(nameMatchScore('chuoi', 'Bánh chuối'), greaterThan(nameMatchScore('chuo', 'Bánh chuối')));
    expect(nameMatchScore('chuo', 'Bánh chuối'), greaterThan(nameMatchScore('chuoj', 'Bánh chuối')));
    expect(nameMatchScore('chuoj', 'Bánh chuối'), greaterThan(0));
    expect(nameMatchScore('tao', 'Bánh chuối'), 0);
  });

  test('mã lệch đúng một số với sản phẩm đã có → gợi ý sản phẩm đó', () {
    expect(cache.similarBarcodes('9901234564567').map((p) => p.product.name), ["Bánh Ella's dâu chuối"]);
    expect(cache.similarBarcodes('8901234564567'), isEmpty); // trùng hẳn: không phải "gần giống"
    expect(cache.similarBarcodes('9901234564568'), isEmpty); // lệch 2 số
    expect(cache.similarBarcodes('012345678904').map((p) => p.product.name), ['Sữa chua Kiddylicious']); // UPC-A 12 số
  });
}
