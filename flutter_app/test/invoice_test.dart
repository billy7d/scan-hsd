import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kho_an_dam_app/invoice.dart';
import 'package:kho_an_dam_app/invoice_view.dart';
import 'package:kho_an_dam_app/models.dart';

InventoryRow row(String code, String name, int price, {bool le = false, String id = 'x'}) =>
    InventoryRow(id: id, product: Product(barcode: code, name: name, price: price), hsd: '2027-03-15', qty: 10, le: le);

final vang = row('111', 'Váng sữa Nestle vị vani', 210000);
final suaChua = row('222', 'Sữa chua phomai Nestle', 230000);
final suaChuaLe = row('222', 'Sữa chua phomai Nestle', 60000, le: true);

void main() {
  late Directory tmp;
  late DateTime now;
  late InvoiceStore store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('invoice_test');
    now = DateTime(2026, 11, 5, 17, 0);
    store = InvoiceStore(fileProvider: () async => File('${tmp.path}/invoices.json'), clock: () => now);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('trừ số lượng → tự tạo một hoá đơn, gom theo sản phẩm + loại (lốc / lẻ riêng dòng)', () {
    store.recordAdjust(vang, -1);
    store.recordAdjust(suaChua, -2);
    store.recordAdjust(vang, -5);
    store.recordAdjust(suaChuaLe, -3);
    expect(store.invoices, hasLength(1));
    final inv = store.activeAuto!;
    expect(inv.items.map((i) => [i.name, i.price, i.qty]), [
      ['Váng sữa Nestle vị vani', 210000, 6],
      ['Sữa chua phomai Nestle', 230000, 2],
      ['Sữa chua phomai Nestle (lẻ)', 60000, 3],
    ]);
    expect(inv.totalQty, 11);
    expect(inv.subtotal, 210000 * 6 + 230000 * 2 + 60000 * 3);
  });

  test('cộng lại kho (+) → giảm dòng hoá đơn, về 0 thì bỏ; không có hoá đơn thì bỏ qua', () {
    store.recordAdjust(vang, 3);
    expect(store.invoices, isEmpty);
    store.recordAdjust(vang, -3);
    store.recordAdjust(suaChua, -1);
    store.recordAdjust(vang, 1);
    expect(store.activeAuto!.items.first.qty, 2);
    store.recordAdjust(vang, 5);
    expect(store.activeAuto!.items.map((i) => i.name), ['Sữa chua phomai Nestle']);
  });

  test('30 phút tính từ lần trừ cuối: còn trừ thì giữ, nghỉ 30 phút thì xoá; lần trừ sau mở hoá đơn mới', () {
    store.recordAdjust(vang, -1);
    final first = store.activeAuto!.id;
    now = now.add(const Duration(minutes: 25));
    store.recordAdjust(suaChua, -1);
    now = now.add(const Duration(minutes: 29));
    expect(store.activeAuto!.id, first);
    expect(store.activeAuto!.totalQty, 2);
    now = now.add(const Duration(minutes: 1));
    expect(store.invoices, isEmpty);
    store.recordAdjust(vang, -1);
    expect(store.activeAuto!.id, isNot(first));
    expect(store.activeAuto!.totalQty, 1);
  });

  test('sửa hoá đơn tự tạo cũng tính lại 30 phút; đang mở để sửa / xem trước thì không bị xoá', () {
    store.recordAdjust(vang, -1);
    final inv = store.activeAuto!;
    now = now.add(const Duration(minutes: 20));
    inv.customer = 'C Lan';
    store.changed(inv);
    now = now.add(const Duration(minutes: 20));
    expect(store.invoices, hasLength(1));
    store.hold(inv);
    now = now.add(const Duration(hours: 2));
    store.purgeExpired();
    expect(store.invoices, hasLength(1));
    store.release(inv);
    now = now.add(const Duration(minutes: 30));
    store.purgeExpired();
    expect(store.invoices, isEmpty);
  });

  test('hoá đơn thủ công không tự xoá, không nhận các lần trừ; xoá tay được', () {
    final m = store.createManual();
    m.items.add(InvoiceItem(name: 'Váng Mont gói lẻ', price: 50000, qty: 5));
    store.changed(m);
    store.recordAdjust(vang, -1);
    expect(m.items, hasLength(1));
    now = now.add(const Duration(days: 3));
    store.purgeExpired();
    expect(store.invoices, [m]);
    store.remove(m);
    expect(store.invoices, isEmpty);
  });

  test('lưu trên máy: mở lại app đọc đúng; hoá đơn tự tạo quá hạn bị bỏ khi mở', () async {
    store.recordAdjust(vang, -2);
    final m = store.createManual()
      ..customer = 'C Lan Phương Fb'
      ..shipFee = 30000;
    m.items.add(InvoiceItem(name: 'Váng Mont gói lẻ', price: 50000, qty: 5));
    store.changed(m);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final again = InvoiceStore(fileProvider: () async => File('${tmp.path}/invoices.json'), clock: () => now);
    await again.load();
    expect(again.invoices.map((i) => [i.auto, i.totalQty]), [[true, 2], [false, 5]]);
    expect(again.invoices.last.total, 50000 * 5 + 30000);
    expect(again.invoices.last.customer, 'C Lan Phương Fb');

    final later = InvoiceStore(
        fileProvider: () async => File('${tmp.path}/invoices.json'), clock: () => now.add(const Duration(minutes: 31)));
    await later.load();
    expect(later.invoices.map((i) => i.auto), [false]);
  });

  testWidgets('mẫu ảnh hoá đơn: shop, SĐT, tiêu đề (không có giờ), khách, bảng SL trước Đơn giá, Tổng, ship, tổng hoá đơn', (tester) async {
    final inv = Invoice(id: '1', auto: false, createdAt: now, touchedAt: now, customer: 'C Lan Phuong Fb', shipFee: 30000, items: [
      InvoiceItem(name: 'Váng Mont gói lẻ', price: 50000, qty: 5),
      InvoiceItem(name: 'Váng sữa Nestle vị vani', price: 210000, qty: 1),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: InvoiceView(invoice: inv))),
    ));
    for (final t in [
      'Đồ ăn dặm -  Trà Phương 🍼', '0816 950 666', 'HOÁ ĐƠN TẠM TÍNH', 'Khách hàng: C Lan Phuong Fb',
      'Sản phẩm', 'Đơn giá', 'SL', 'T.tiền', 'Váng Mont gói lẻ', '50.000', '250.000', '210.000',
      'Tổng', '460.000 đ', 'Phí ship', '30.000 đ', 'Tổng hoá đơn', '490.000 đ',
    ]) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.textContaining('/2026'), findsNothing);
    expect(find.textContaining('SP'), findsNothing);
    // Thứ tự cột: Sản phẩm | SL | Đơn giá | T.tiền.
    final xs = [for (final t in ['Sản phẩm', 'SL', 'Đơn giá', 'T.tiền']) tester.getTopLeft(find.text(t)).dx];
    expect(xs, [...xs]..sort());
    // Mọi chữ màu mực đen (không còn màu cam).
    for (final t in tester.widgetList<RichText>(find.byType(RichText))) {
      expect(t.text.style?.color ?? const Color(0xFF111111), const Color(0xFF111111), reason: t.text.toPlainText());
    }
    expect(tester.takeException(), isNull);
  });
}
