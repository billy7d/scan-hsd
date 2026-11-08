import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kho_an_dam_app/inventory_cache.dart';
import 'package:kho_an_dam_app/main.dart';
import 'package:kho_an_dam_app/models.dart';
import 'package:kho_an_dam_app/stock_list_screen.dart';

InventoryRow row(String id, String barcode, String name, int qty, {String hsd = '2027-03-15', bool le = false}) =>
    InventoryRow(id: id, product: Product(barcode: barcode, name: name), hsd: hsd, qty: qty, le: le);

/// Bỏ qua ghi file (ghi file thật không chạy xong được trong đồng hồ giả của testWidgets).
InventoryCache cacheWith(List<InventoryRow> rows, {Future<List<InventoryRow>> Function()? fetcher}) => InventoryCache(
      fileProvider: () async => throw const FileSystemException('không ghi file trong test'),
      fetcher: fetcher ?? () async => rows,
    )..setRows(rows, DateTime(2026, 11, 8));

List<String> labels(InventoryCache c) => [for (final l in c.stockList()) '${l.label}=${l.qty}'];

/// Mọi ô chữ trong bảng, theo thứ tự hiển thị từ trên xuống.
List<String?> cells(WidgetTester tester) =>
    [for (final t in tester.widgetList<Text>(find.descendant(of: find.byType(ListView), matching: find.byType(Text)))) t.data];

void main() {
  test('sắp xếp: hết hàng → ít → nhiều', () {
    final c = cacheWith([
      row('1', '111', 'Nhiều', 20),
      row('2', '222', 'Hết hàng', 0),
      row('3', '333', 'Ít', 2),
    ]);
    expect(labels(c), ['Hết hàng=0', 'Ít=2', 'Nhiều=20']);
  });

  test('cùng số lượng: theo alphabet, không phân biệt dấu và hoa thường', () {
    final c = cacheWith([
      row('1', '111', 'Organix bánh', 5),
      row('2', '222', 'ella bánh', 5),
      row('3', '333', 'Đậu hà lan', 5),
      row('4', '444', 'Ăn dặm Heinz', 5),
      row('5', '555', 'Zebra', 0),
      row('6', '666', 'Apple', 0),
    ]);
    expect(labels(c), ['Apple=0', 'Zebra=0', 'Ăn dặm Heinz=5', 'Đậu hà lan=5', 'ella bánh=5', 'Organix bánh=5']);
  });

  test('số lượng là tổng mọi date; mọi date về 0 thì sản phẩm vẫn còn với số 0', () {
    final c = cacheWith([
      row('1', '111', 'Nhiều date', 3, hsd: '2027-01-01'),
      row('2', '111', 'Nhiều date', 4, hsd: '2027-06-01'),
      row('3', '222', 'Đã bán hết', 0, hsd: '2027-01-01'),
      row('4', '222', 'Đã bán hết', 0, hsd: '2027-06-01'),
    ]);
    expect(labels(c), ['Đã bán hết=0', 'Nhiều date=7']);
  });

  test('hàng lốc và hàng lẻ là hai dòng riêng, cùng số lượng thì lốc trước', () {
    final c = cacheWith([
      row('1', '111', 'Sữa chua', 4),
      row('2', '111', 'Sữa chua', 4, le: true),
      row('3', '222', 'Váng sữa', 0),
      row('4', '222', 'Váng sữa', 8, le: true),
      row('5', '333', 'Chỉ có lẻ', 1, le: true),
    ]);
    expect(labels(c), ['Váng sữa=0', 'Chỉ có lẻ (Lẻ)=1', 'Sữa chua=4', 'Sữa chua (Lẻ)=4', 'Váng sữa (Lẻ)=8']);
  });

  test('hàng không mã vạch vẫn có; dòng chưa có tên thì hiện mã', () {
    final c = cacheWith([
      row('1', '', 'Bánh tự làm', 3),
      row('2', '999', '', 3),
    ]);
    expect(labels(c), ['Bánh tự làm=3', 'Mã 999=3']);
  });

  testWidgets('màn hình: tiêu đề, đúng 3 cột, STT tăng dần theo thứ tự sắp xếp', (tester) async {
    final c = cacheWith([row('1', '111', 'Nhiều', 20), row('2', '222', 'Hết hàng', 0), row('3', '333', 'Ít', 2)]);
    await tester.pumpWidget(MaterialApp(home: StockListScreen(cache: c)));
    await tester.pump();

    expect(find.text('Dsach tồn kho'), findsOneWidget);
    for (final h in ['STT', 'Tên sản phẩm', 'Số lượng']) {
      expect(find.text(h), findsOneWidget);
    }
    expect(cells(tester), ['1', 'Hết hàng', '0', '2', 'Ít', '2', '3', 'Nhiều', '20']);
  });

  testWidgets('màn hình: mở lên tải số lượng mới nhất từ sheet và sắp xếp lại', (tester) async {
    final c = cacheWith(
      [row('1', '111', 'A', 1), row('2', '222', 'B', 5)],
      fetcher: () async => [row('1', '111', 'A', 9), row('2', '222', 'B', 0)],
    );
    await tester.pumpWidget(MaterialApp(home: StockListScreen(cache: c)));
    await tester.pump();

    expect(cells(tester), ['1', 'B', '0', '2', 'A', '9']);
  });

  testWidgets('màn hình: cỡ iPhone 15 Pro Max (430×932), tên dài và số lớn không bị tràn', (tester) async {
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    const longName = 'Naturnes Sữa chua phô mai mini vị Tự nhiên Bánh quy Lúa mì Chuối Xoài Đào 12 tháng tuổi trở lên';
    final c = cacheWith([row('1', '111', longName, 12345), row('2', '111', longName, 67, le: true)]);
    await tester.pumpWidget(MaterialApp(home: StockListScreen(cache: c)));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(cells(tester), ['1', '$longName (Lẻ)', '67', '2', longName, '12345']);
  });

  testWidgets('màn hình: sheet trống thì báo chưa có sản phẩm', (tester) async {
    await tester.pumpWidget(MaterialApp(home: StockListScreen(cache: cacheWith(const []))));
    await tester.pump();

    expect(find.text('Chưa có sản phẩm'), findsOneWidget);
  });

  testWidgets('menu chính có nút "Dsach tồn kho", bấm vào mở đúng màn hình', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    expect(find.widgetWithText(OutlinedButton, 'Dsach tồn kho'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Dsach tồn kho'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(StockListScreen), findsOneWidget);
    expect(find.text('Tên sản phẩm'), findsOneWidget);

    // Lệnh tải sheet của bản thật gặp HTTP giả trong test: đợi cho hết hẹn giờ (không gọi sheet thật).
    await tester.pump(const Duration(minutes: 5));
  });
}
