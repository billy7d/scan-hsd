// Mẫu ảnh "HOÁ ĐƠN TẠM TÍNH": nền trắng, rộng cố định [invoiceWidth] để ảnh xuất ra giống nhau trên mọi máy.

import 'package:flutter/material.dart';

import 'date_parser.dart';
import 'invoice.dart';

const shopName = 'Đồ ăn dặm -  Trà Phương 🍼';
const shopPhone = '0816 950 666';
const invoiceWidth = 400.0;

const _ink = Color(0xFF111111);

class InvoiceView extends StatelessWidget {
  final Invoice invoice;
  const InvoiceView({super.key, required this.invoice});

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(color: _ink, fontSize: 15, height: 1.35);
    final inv = invoice;
    return DefaultTextStyle.merge(
      style: base,
      child: Container(
        width: invoiceWidth,
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(10, 20, 10, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text(shopName,
              textAlign: TextAlign.center, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, fontStyle: FontStyle.italic)),
          const SizedBox(height: 4),
          const Text(shopPhone, textAlign: TextAlign.center, style: TextStyle(fontSize: 17)),
          const SizedBox(height: 10),
          const Divider(color: _ink, thickness: 1, height: 1),
          const SizedBox(height: 10),
          const Text('HOÁ ĐƠN TẠM TÍNH', textAlign: TextAlign.center, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          const SizedBox(height: 29), // giữ khoảng cách cũ (trước đây có dòng giờ ở đây)
          Text.rich(TextSpan(children: [
            const TextSpan(text: 'Khách hàng: '),
            TextSpan(text: inv.customer.trim(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ])),
          const SizedBox(height: 6),
          _table(inv),
          const SizedBox(height: 10),
          _totalRow('Tổng', '${formatNumber(inv.subtotal)} đ',
              labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              valueStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          _totalRow('Phí ship', '${formatNumber(inv.shipFee)} đ'),
          const SizedBox(height: 8),
          const Divider(color: _ink, thickness: 1, height: 1),
          const SizedBox(height: 8),
          _totalRow('Tổng hoá đơn', '${formatNumber(inv.total)} đ',
              labelStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              valueStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }

  Widget _totalRow(String label, String value, {TextStyle? labelStyle, TextStyle? valueStyle}) =>
      Row(children: [Expanded(child: Text(label, style: labelStyle)), Text(value, style: valueStyle)]);

  // Bảng: viền và mọi đường kẻ nét liền. Cột: Sản phẩm | SL | Đơn giá | T.tiền.
  static const _flex = [15, 4, 9, 10];
  static const _vLine = SizedBox(width: 1, child: ColoredBox(color: _ink));
  static const _hLine = SizedBox(height: 1, width: double.infinity, child: ColoredBox(color: _ink));

  Widget _table(Invoice inv) {
    Widget row(List<String> cells, {bool header = false}) {
      final style = header ? const TextStyle(fontWeight: FontWeight.w700) : null;
      Widget cell(int i) => Expanded(
            flex: _flex[i],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 7),
              child: Text(cells[i],
                  style: style,
                  textAlign: i == 0 ? TextAlign.left : (i == 1 ? TextAlign.center : TextAlign.right)),
            ),
          );
      return IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          cell(0),
          _vLine,
          cell(1),
          _vLine,
          cell(2),
          _vLine,
          cell(3),
        ]),
      );
    }

    return Container(
      decoration: BoxDecoration(border: Border.all(color: _ink, width: 1)),
      child: Column(children: [
        row(['Sản phẩm', 'SL', 'Đơn giá', 'T.tiền'], header: true),
        for (final i in inv.items) ...[
          _hLine,
          row([i.name, '${i.qty}', formatNumber(i.price), formatNumber(i.total)]),
        ],
      ]),
    );
  }
}
