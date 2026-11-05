import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kho_an_dam_app/inventory_cache.dart';
import 'package:kho_an_dam_app/models.dart';

const code = '5060107335882';
const name = 'Ella sữa chua dâu 6M';

InventoryRow row(String id, String hsd, int qty, int price, {bool le = false}) =>
    InventoryRow(id: id, product: Product(barcode: code, name: name, price: price), hsd: hsd, qty: qty, le: le);

void main() {
  late Directory tmp;
  late InventoryCache cache;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('le_test');
    cache = InventoryCache(fileProvider: () async => File('${tmp.path}/snapshot.json'), fetcher: () async => []);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('snapshot: cột thứ 7 = lẻ; bản sao cũ 6 cột → lốc; toList giữ nguyên', () {
    final le = InventoryRow.fromList(['a', code, name, '2027-03-15', 4, 40000, 1]);
    expect(le.le, isTrue);
    expect(InventoryRow.fromList(['a', code, name, '2027-03-15', 4, 40000, 0]).le, isFalse);
    expect(InventoryRow.fromList(['a', code, name, '2027-03-15', 4, 40000]).le, isFalse);
    expect(InventoryRow.fromList(le.toList()).le, isTrue);
    expect(le.copyWith(qty: 9).le, isTrue);
  });

  test('cùng mã: lốc và lẻ chung một sản phẩm, tách tổng và giá theo loại', () {
    cache.setRows([
      row('l1', '2027-03-15', 2, 140000),
      row('l2', '2027-06-30', 1, 140000),
      row('e1', '2027-03-15', 5, 40000, le: true),
    ], DateTime(2026, 11, 5));
    expect(cache.products, hasLength(1));
    final s = cache.byBarcode(code)!;
    expect(s.hasLe, isTrue);
    expect([s.product.price, s.priceLe], [140000, 40000]);
    expect([s.totalQty, s.totalLe], [3, 5]);
    expect(s.lotRows.map((r) => r.id), ['l1', 'l2']);
    expect(s.leRows.map((r) => r.id), ['e1']);
    expect(s.priceFor(true), 40000);
    expect(s.summaryText, 'Lốc 140.000 ₫ · 3 | Lẻ 40.000 ₫ · 5');
  });

  test('chỉ có lốc → tóm tắt như cũ; chỉ có lẻ → chỉ hiện phần lẻ', () {
    cache.setRows([row('l1', '2027-03-15', 2, 140000)], DateTime(2026, 11, 5));
    expect(cache.byBarcode(code)!.summaryText, '140.000 ₫ · tổng 2');
    cache.setRows([row('e1', '2027-03-15', 6, 40000, le: true)], DateTime(2026, 11, 5));
    final s = cache.byBarcode(code)!;
    expect([s.product.price, s.priceLe, s.totalQty], [0, 40000, 0]);
    expect(s.summaryText, 'Lẻ 40.000 ₫ · 6');
  });

  test('applyLookup: mỗi date lẻ nhận giá lẻ, date lốc nhận giá lốc', () {
    cache.setRows([row('l1', '2027-03-15', 2, 140000)], DateTime(2026, 11, 5));
    final changed = cache.applyLookup(
      code,
      const LookupResult(
        found: true,
        product: Product(barcode: code, name: name, price: 140000),
        priceLe: 40000,
        lots: [Lot(id: 'l1', hsd: '2027-03-15', qty: 1), Lot(id: 'e1', hsd: '2027-03-15', qty: 4, le: true)],
      ),
    );
    expect(changed, isTrue);
    final s = cache.byBarcode(code)!;
    expect(s.lotRows.single.product.price, 140000);
    expect(s.leRows.single.product.price, 40000);
    expect([s.totalQty, s.totalLe], [1, 4]);
  });

  test('applyLookup phát hiện đổi loại dù cùng id / số lượng', () {
    cache.setRows([row('x', '2027-03-15', 2, 140000)], DateTime(2026, 11, 5));
    expect(
      cache.applyLookup(code, const LookupResult(
        found: true,
        product: Product(barcode: code, name: name, price: 140000),
        priceLe: 140000,
        lots: [Lot(id: 'x', hsd: '2027-03-15', qty: 2, le: true)],
      )),
      isTrue,
    );
  });

  test('PackSizes: nhớ số hộp / lốc theo sản phẩm, đọc lại sau khi mở app', () async {
    final file = File('${tmp.path}/pack.json');
    final a = PackSizes(fileProvider: () async => file);
    expect(await a.get('b:$code'), isNull);
    await a.set('b:$code', 4);
    expect(await PackSizes(fileProvider: () async => file).get('b:$code'), 4);
  });
}
