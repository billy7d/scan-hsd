import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kho_an_dam_app/inventory_cache.dart';
import 'package:kho_an_dam_app/lookup_screen.dart';
import 'package:kho_an_dam_app/models.dart';
import 'package:kho_an_dam_app/ui.dart';

String iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
final today = DateTime.now();
final nearHsd = iso(today.add(const Duration(days: 30)));
final farHsd = iso(today.add(const Duration(days: 400)));
final expiredHsd = iso(today.subtract(const Duration(days: 10)));

InventoryRow row(String id, String code, String name, int qty, String hsd, {bool le = false}) =>
    InventoryRow(id: id, product: Product(barcode: code, name: name, price: 100000), hsd: hsd, qty: qty, le: le);

/// Kho mẫu: 2 sản phẩm hết hàng, 1 hết lốc nhưng còn lẻ, 1 còn ≤ 90 ngày, 1 hết hạn còn hàng, 1 bình thường.
List<InventoryRow> sample() => [
      row('1', '111', 'Organix bánh', 0, nearHsd),
      row('2', '111', 'Organix bánh', 0, farHsd),
      row('3', '222', 'Ella sữa chua', 0, expiredHsd),
      row('4', '333', 'Heinz bột', 0, farHsd),
      row('5', '333', 'Heinz bột', 4, farHsd, le: true),
      row('6', '444', 'Kiddy bánh quy', 3, nearHsd),
      row('7', '555', 'Bell váng sữa', 2, expiredHsd),
      row('8', '666', 'Cerelac bột', 9, farHsd),
    ];

List<String> names(Iterable<ProductSummary> ps) => [for (final p in ps) p.product.name];

ListTile tileOf(WidgetTester tester, String name) =>
    tester.widget<ListTile>(find.ancestor(of: find.text(name), matching: find.byType(ListTile)));

/// Màu chữ thực tế của mọi dòng chữ trong ô (tên + dòng phụ).
Set<Color?> textColorsOf(WidgetTester tester, String name) => {
      for (final t in tester.widgetList<RichText>(
          find.descendant(of: find.ancestor(of: find.text(name), matching: find.byType(ListTile)), matching: find.byType(RichText))))
        t.text.style?.color,
    };

Future<void> pumpSearch(WidgetTester tester) async {
  // Dữ liệu vừa tải → màn tìm kiếm không gọi sheet thật.
  InventoryCache.instance.setRows(sample(), DateTime.now());
  await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
  await tester.pump();
}

void main() {
  late Directory tmp;
  late InventoryCache cache;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('out_of_stock_test');
    cache = InventoryCache(fileProvider: () async => File('${tmp.path}/snapshot.json'), fetcher: () async => [])
      ..setRows(sample(), DateTime.now());
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('hết hàng = mọi date (cả lốc và lẻ) có số lượng 0', () {
    bool out(String name) => cache.products.firstWhere((p) => p.product.name == name).isOutOfStock;
    expect(out('Organix bánh'), isTrue);
    expect(out('Ella sữa chua'), isTrue);
    expect(out('Heinz bột'), isFalse, reason: 'hết lốc nhưng còn 4 lẻ');
    expect(out('Kiddy bánh quy'), isFalse);
  });

  test('lọc SL = 0: chỉ sản phẩm hết hàng, theo tên; gõ tên thì tìm trong nhóm này', () {
    expect(names(cache.search('', filter: ExpiryFilter.outOfStock)), ['Ella sữa chua', 'Organix bánh']);
    expect(names(cache.search('organix', filter: ExpiryFilter.outOfStock)), ['Organix bánh']);
    expect(names(cache.search('kiddy', filter: ExpiryFilter.outOfStock)), isEmpty);
  });

  test('lọc ≤ 90 ngày / hết hạn vẫn như cũ, không lẫn sản phẩm hết hàng', () {
    expect(names(cache.search('', filter: ExpiryFilter.near)), ['Kiddy bánh quy']);
    expect(names(cache.search('', filter: ExpiryFilter.expired)), ['Bell váng sữa']);
  });

  testWidgets('màn tìm kiếm: có nút SL = 0, bấm vào chỉ còn hàng hết, mọi dòng xanh đậm chữ trắng', (tester) async {
    await pumpSearch(tester);
    for (final label in ['Tất cả', '≤ 90 ngày', 'Hết hạn', 'SL = 0']) {
      expect(find.text(label), findsOneWidget);
    }

    await tester.tap(find.text('SL = 0'));
    await tester.pump();

    expect(find.byType(ListTile), findsNWidgets(2));
    for (final name in ['Ella sữa chua', 'Organix bánh']) {
      expect(tileOf(tester, name).tileColor, outOfStockColor);
      expect(textColorsOf(tester, name), {Colors.white});
    }
  });

  testWidgets('màn tìm kiếm "Tất cả": hết hàng xanh đậm, các màu HSD giữ nguyên', (tester) async {
    tester.view.physicalSize = const Size(800, 2000); // đủ cao để dựng cả 6 dòng
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpSearch(tester);

    expect(tileOf(tester, 'Organix bánh').tileColor, outOfStockColor);
    expect(tileOf(tester, 'Ella sữa chua').tileColor, outOfStockColor);
    expect(tileOf(tester, 'Kiddy bánh quy').tileColor, nearColor);
    expect(tileOf(tester, 'Bell váng sữa').tileColor, expiredColor);
    expect(tileOf(tester, 'Heinz bột').tileColor, isNot(outOfStockColor));
    expect(tileOf(tester, 'Cerelac bột').tileColor, isNull);
    expect(textColorsOf(tester, 'Cerelac bột'), isNot(contains(Colors.white)));
  });

  testWidgets('màn tìm kiếm: cỡ iPhone 15 Pro Max (430×932), 4 nút lọc không bị tràn', (tester) async {
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await pumpSearch(tester);
    await tester.tap(find.text('SL = 0'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(ListTile), findsNWidgets(2));
  });
}
