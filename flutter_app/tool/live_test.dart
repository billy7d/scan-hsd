// ignore_for_file: avoid_print
// Thử ghi thật lên Google Sheet bằng chính code api.dart của app, rồi dọn sạch dòng thử.
// Chạy: dart run tool/live_test.dart   (cần lib/config.dart có URL + key thật, Code.gs bản 6 cột đã Deploy)

import 'package:kho_an_dam_app/api.dart';
import 'package:kho_an_dam_app/models.dart';

const code = '9990000000017';
const name = 'TEST - xoá được';
var failed = 0;

void check(String label, bool ok, [Object? detail]) {
  if (!ok) failed++;
  print('${ok ? '✓' : '✗'} $label${detail == null ? '' : '  ($detail)'}');
}

Future<T> timed<T>(String label, Future<T> Function() fn) async {
  final sw = Stopwatch()..start();
  final r = await fn();
  print('   $label: ${sw.elapsedMilliseconds} ms');
  return r;
}

Future<void> cleanup() async {
  final res = await Api.lookup(code);
  for (final l in res.lots) {
    await Api.deleteLot(l.id, Expect(code, l.hsd, l.qty));
  }
  final snap = await Api.snapshot();
  for (final r in snap.where((r) => r.product.barcode.isEmpty && r.product.name.startsWith('TEST - '))) {
    await Api.deleteLot(r.id, Expect('', r.hsd, r.qty));
  }
}

Future<void> main() async {
  try {
    await cleanup();

    final a = await timed('ghi 2 date một lần',
        () => Api.add(barcode: code, name: name, price: 140000, lots: const [NewLot('2027-03-15', 2), NewLot('2026-12-30', 5)]));
    check('ghi nhiều date → mỗi date một dòng', a.length == 2 && a.every((r) => r.status == 'created'));

    final d = await Api.add(barcode: code, name: name, price: 140000, lots: const [NewLot('2027-03-15', 3)]);
    check('cùng mã + cùng date → duplicate, chưa ghi', d.single.status == 'duplicate' && d.single.currentQty == 2);
    final m = await Api.add(barcode: code, name: name, price: 150000, lots: const [NewLot('2027-03-15', 3)], confirmMerge: true);
    check('đồng ý → cộng dồn thành 5', m.single.status == 'merged' && m.single.newQty == 5);

    final l = await timed('đọc theo mã', () => Api.lookup(code));
    check('đọc thấy đủ 2 date, gần hết hạn trước, giá mới cho mọi date',
        l.found && l.lots.map((x) => x.hsd).join(',') == '2026-12-30,2027-03-15' && l.product!.price == 150000);

    final id = a.first.id!;
    final adj = await timed('−/+ (gom 3 lần bấm)', () => Api.adjust(id, const Expect(code, '2027-03-15', 5), -3));
    check('bấm −3 → còn 2', adj.newQty == 2);
    try {
      await Api.adjust(id, const Expect(code, '2027-03-15', 5), -1);
      check('số cũ → conflict', false);
    } on ConflictException catch (e) {
      check('số cũ → conflict, không ghi đè', e.status == 'conflict');
    }

    final p = await Api.updateProduct(const Product(barcode: code, name: name), const Product(barcode: code, name: name, price: 99000));
    check('sửa giá → áp dụng cho mọi date', p.rowsChanged == 2);

    final nb = await Api.add(barcode: '', name: 'TEST - không mã', price: 50000, lots: const [NewLot('2027-01-31', 1)]);
    check('ghi hàng không mã vạch', nb.single.status == 'created');

    final snap = await timed('tải toàn bộ sheet', Api.snapshot);
    check('sheet có đủ dòng thử', snap.where((r) => r.product.name.startsWith('TEST - ')).length == 3);
  } catch (e) {
    failed++;
    print('✗ Lỗi: $e');
  } finally {
    await cleanup();
  }
  print(failed == 0 ? '\nTất cả đều qua.' : '\n$failed bước không qua.');
}
