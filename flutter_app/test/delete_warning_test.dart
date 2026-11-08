import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kho_an_dam_app/api.dart';
import 'package:kho_an_dam_app/inventory_cache.dart';
import 'package:kho_an_dam_app/lookup_screen.dart';
import 'package:kho_an_dam_app/models.dart';

const code = '5060107335882';
const product = Product(barcode: code, name: 'Ella sữa chua dâu 6M');

InventoryRow row(String id, String hsd, int qty, {bool le = false}) =>
    InventoryRow(id: id, product: product, hsd: hsd, qty: qty, le: le);

Future<void> pumpCard(WidgetTester tester, InventoryRow r, List<InventoryRow> all) async {
  InventoryCache.instance.setRows(all, DateTime(2026, 11, 8));
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: LotCard(row: r, now: DateTime(2026, 11, 8), onConflict: () async {})),
  ));
}

Future<void> openManualDelete(WidgetTester tester) async {
  await tester.tap(find.byType(PopupMenuButton<String>));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.tap(find.text('Xoá date này'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  final lot1 = row('a', '2027-01-01', 0);
  final lot2 = row('b', '2027-06-01', 3);
  final le1 = row('c', '2027-01-01', 2, le: true);

  group('lastDateWarning', () {
    test('date cuối cùng của sản phẩm: báo mất khỏi danh sách và phải nhập lại tên, giá', () {
      final w = ProductSummary(product, [lot1]).lastDateWarning(lot1);
      expect(w, allOf(contains('date cuối cùng của sản phẩm'), contains('Dsach tồn kho'), contains('nhập lại tên và giá')));
    });

    test('còn date khác cùng loại: không cảnh báo', () {
      expect(ProductSummary(product, [lot1, lot2]).lastDateWarning(lot1), isNull);
    });

    test('date lốc cuối cùng nhưng còn hàng lẻ: báo mất dòng hàng lốc', () {
      final w = ProductSummary(product, [lot1, le1]).lastDateWarning(lot1);
      expect(w, contains('dòng hàng lốc'));
      expect(w, isNot(contains('date cuối cùng của sản phẩm')));
    });

    test('date lẻ cuối cùng nhưng còn hàng lốc: báo mất dòng hàng lẻ', () {
      expect(ProductSummary(product, [lot1, le1]).lastDateWarning(le1), contains('dòng hàng lẻ'));
    });
  });

  group('hộp thoại khi bấm trừ về 0', () {
    late http.Client realClient;

    setUp(() {
      realClient = Api.client;
      // Client giả trả số lượng mới bằng 0, không gọi sheet thật.
      Api.client = MockClient((_) async => http.Response('{"ok":true,"status":"updated","newQty":0}', 200));
    });
    tearDown(() => Api.client = realClient);

    Future<void> minusToZero(WidgetTester tester) async {
      await tester.tap(find.text('-1'));
      await tester.pump(const Duration(milliseconds: 1300)); // hết thời gian gom lệnh
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('date cuối cùng: có cảnh báo và gợi ý Giữ lại', (tester) async {
      final r = row('a', '2027-01-01', 1);
      await pumpCard(tester, r, [r]);
      await minusToZero(tester);

      expect(find.text('Hết date này'), findsOneWidget);
      expect(find.textContaining('còn 0. Xoá dòng này khỏi sheet?'), findsOneWidget);
      expect(find.textContaining('date cuối cùng của sản phẩm'), findsOneWidget);
      expect(find.textContaining('vẫn hiện trong danh sách với số lượng 0'), findsOneWidget);
      expect(find.text('Giữ lại'), findsOneWidget);
    });

    testWidgets('còn date khác: chỉ hỏi xoá như cũ', (tester) async {
      final r = row('a', '2027-01-01', 1);
      await pumpCard(tester, r, [r, lot2]);
      await minusToZero(tester);

      expect(find.text('Hết date này'), findsOneWidget);
      expect(find.textContaining('Dsach tồn kho'), findsNothing);
    });
  });

  group('hộp thoại khi chọn "Xoá date này"', () {
    testWidgets('date cuối cùng: có cảnh báo', (tester) async {
      await pumpCard(tester, lot2, [lot2]);
      await openManualDelete(tester);

      expect(find.textContaining('date cuối cùng của sản phẩm'), findsOneWidget);
    });

    testWidgets('còn date khác: không cảnh báo', (tester) async {
      await pumpCard(tester, lot2, [lot1, lot2]);
      await openManualDelete(tester);

      expect(find.text('Xoá date'), findsOneWidget);
      expect(find.textContaining('Dsach tồn kho'), findsNothing);
    });
  });
}
