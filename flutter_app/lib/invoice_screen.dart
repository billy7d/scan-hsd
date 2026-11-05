// HOÁ ĐƠN — danh sách hoá đơn tạm (tự tạo từ các lần trừ số lượng + tạo thủ công), sửa, xem trước, lưu ảnh.
// Hoá đơn chỉ lưu trên máy; sửa / xoá dòng không đổi số lượng trong kho.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';

import 'date_parser.dart';
import 'inventory_cache.dart';
import 'invoice.dart';
import 'invoice_view.dart';
import 'ui.dart';

const _listRoute = 'invoices';

/// Mở danh sách hoá đơn (đặt tên route để quay về sau khi lưu ảnh).
Future<void> openInvoices(BuildContext context) => Navigator.push(
    context, MaterialPageRoute(settings: const RouteSettings(name: _listRoute), builder: (_) => const InvoiceListScreen()));

String _title(Invoice inv) {
  if (inv.customer.trim().isNotEmpty) return inv.customer.trim();
  return inv.auto ? 'Hoá đơn tự tạo' : 'Hoá đơn thủ công';
}

/// "tự xoá lúc 18:25 (còn 12 phút)".
String autoExpiryText(Invoice inv, DateTime now) {
  final at = inv.expiresAt!;
  final mins = (at.difference(now).inSeconds / 60).ceil().clamp(0, 999);
  return 'tự xoá lúc ${hhmm(at)} (còn $mins phút)';
}

// ================================================================ Danh sách

class InvoiceListScreen extends StatefulWidget {
  const InvoiceListScreen({super.key});
  @override
  State<InvoiceListScreen> createState() => _InvoiceListScreenState();
}

class _InvoiceListScreenState extends State<InvoiceListScreen> {
  final _store = InvoiceStore.instance;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _store.purgeExpired();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => setState(_store.purgeExpired));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _delete(Invoice inv) async {
    if (await confirmDialog(context, 'Xoá hoá đơn', 'Xoá "${_title(inv)}" (${inv.totalQty} SP)?', confirm: 'Xoá')) {
      _store.remove(inv);
    }
  }

  void _edit(Invoice inv) => Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceEditScreen(invoice: inv)));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Hoá đơn')),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: const Text('Tạo hoá đơn'),
          onPressed: () => _edit(_store.createManual()),
        ),
        body: ListenableBuilder(
          listenable: _store,
          builder: (context, _) {
            final list = _store.invoices;
            final now = DateTime.now();
            if (list.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Chưa có hoá đơn.\n\nTrừ số lượng ở màn ĐỌC (nút −1, −5…) → app tự tạo hoá đơn tạm, '
                    '30 phút không trừ thêm thì tự xoá.\nHoặc bấm "Tạo hoá đơn" để tự nhập.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (context, i) {
                final inv = list[i];
                return Card(
                  child: ListTile(
                    leading: Icon(inv.auto ? Icons.timer_outlined : Icons.receipt_long),
                    title: Text(_title(inv), style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text([
                      '${inv.totalQty} SP · ${formatPrice(inv.total)}',
                      if (inv.auto) autoExpiryText(inv, now),
                    ].join('\n')),
                    isThreeLine: inv.auto,
                    trailing: IconButton(tooltip: 'Xoá hoá đơn', icon: const Icon(Icons.delete_outline), onPressed: () => _delete(inv)),
                    onTap: () => _edit(inv),
                  ),
                );
              },
            );
          },
        ),
      );
}

// ================================================================ Sửa hoá đơn

class InvoiceEditScreen extends StatefulWidget {
  final Invoice invoice;
  const InvoiceEditScreen({super.key, required this.invoice});
  @override
  State<InvoiceEditScreen> createState() => _InvoiceEditScreenState();
}

class _InvoiceEditScreenState extends State<InvoiceEditScreen> {
  final _store = InvoiceStore.instance;
  Invoice get inv => widget.invoice;
  late final _customer = TextEditingController(text: inv.customer);
  late final _ship = TextEditingController(text: inv.shipFee > 0 ? formatNumber(inv.shipFee) : '');

  @override
  void initState() {
    super.initState();
    _store.hold(inv); // đang sửa → không tự xoá
  }

  @override
  void dispose() {
    _store.release(inv);
    _customer.dispose();
    _ship.dispose();
    super.dispose();
  }

  void _changed() {
    _store.changed(inv);
    setState(() {});
  }

  Future<void> _editItem([InvoiceItem? item]) async {
    final out = await showDialog<InvoiceItem>(context: context, builder: (_) => _ItemDialog(item: item));
    if (out == null) return;
    if (item == null) {
      inv.items.add(out);
    } else {
      item
        ..name = out.name
        ..price = out.price
        ..qty = out.qty;
    }
    _changed();
  }

  Future<void> _addFromStock() async {
    final s = await pickProduct(context, InventoryCache.instance.products, title: 'Chọn sản phẩm trong kho');
    if (s == null || !mounted) return;
    var le = false;
    if (s.hasLe && s.lotRows.isNotEmpty) {
      final pick = await showDialog<bool>(
        context: context,
        builder: (c) => SimpleDialog(title: Text(s.product.name), children: [
          SimpleDialogOption(
              onPressed: () => Navigator.pop(c, false), child: Text('Nguyên lốc · ${formatPrice(s.product.price)}')),
          SimpleDialogOption(onPressed: () => Navigator.pop(c, true), child: Text('Lẻ · ${formatPrice(s.priceLe)}')),
        ]),
      );
      if (pick == null) return;
      le = pick;
    } else if (s.hasLe) {
      le = true;
    }
    final key = '${s.key}${le ? '|le' : ''}';
    final have = inv.items.where((i) => i.key == key).firstOrNull;
    if (have != null) {
      have.qty++;
    } else {
      inv.items.add(InvoiceItem(name: le ? '${s.product.name} (lẻ)' : s.product.name, price: s.priceFor(le), qty: 1, key: key));
    }
    _changed();
  }

  Future<void> _deleteInvoice() async {
    if (await confirmDialog(context, 'Xoá hoá đơn', 'Xoá cả hoá đơn này?', confirm: 'Xoá')) {
      _store.remove(inv);
      if (mounted) Navigator.pop(context);
    }
  }

  void _export() {
    if (inv.items.isEmpty) return showSnack(context, 'Hoá đơn chưa có sản phẩm', error: true);
    FocusScope.of(context).unfocus();
    Navigator.push(context, MaterialPageRoute(builder: (_) => InvoicePreviewScreen(invoice: inv, at: DateTime.now())));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(inv.auto ? 'Hoá đơn tự tạo' : 'Hoá đơn'),
        actions: [IconButton(tooltip: 'Xoá hoá đơn', icon: const Icon(Icons.delete_outline), onPressed: _deleteInvoice)],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 120), children: [
        TextField(
          controller: _customer,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Khách hàng', prefixIcon: Icon(Icons.person)),
          onChanged: (v) {
            inv.customer = v;
            _changed();
          },
        ),
        const SizedBox(height: 16),
        Text('Sản phẩm (${inv.totalQty})', style: t.titleMedium),
        const SizedBox(height: 4),
        if (inv.items.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Chưa có sản phẩm — thêm từ kho hoặc nhập tay.')),
        for (final item in inv.items)
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _editItem(item),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(item.name, style: t.titleSmall),
                      Text('${formatPrice(item.price)} × ${item.qty} = ${formatPrice(item.total)}'),
                    ]),
                  ),
                  QtyStepper(
                    value: item.qty,
                    onChanged: (v) {
                      item.qty = v;
                      _changed();
                    },
                  ),
                  IconButton(
                    tooltip: 'Bỏ dòng này',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      inv.items.remove(item);
                      _changed();
                    },
                  ),
                ]),
              ),
            ),
          ),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                icon: const Icon(Icons.inventory_2),
                label: const Text('Thêm từ kho'),
                onPressed: _addFromStock),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                icon: const Icon(Icons.edit),
                label: const Text('Nhập tay'),
                onPressed: () => _editItem()),
          ),
        ]),
        const SizedBox(height: 16),
        TextField(
          controller: _ship,
          keyboardType: TextInputType.number,
          inputFormatters: [PriceInputFormatter()],
          decoration: const InputDecoration(labelText: 'Phí ship', suffixText: '₫', prefixIcon: Icon(Icons.local_shipping)),
          onChanged: (v) {
            inv.shipFee = parsePrice(v);
            _changed();
          },
        ),
        const SizedBox(height: 16),
        _sum('Tổng sản phẩm (${inv.totalQty} SP)', inv.subtotal),
        _sum('Phí ship', inv.shipFee),
        const Divider(),
        _sum('Tổng hoá đơn', inv.total, bold: true),
        if (inv.auto)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('Hoá đơn tự tạo: gom các lần trừ số lượng; 30 phút không trừ / sửa thêm thì tự xoá. '
                'Sửa ở đây không đổi số lượng trong kho.', style: t.bodySmall),
          ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            icon: const Icon(Icons.receipt_long),
            label: const Text('Xuất hoá đơn'),
            onPressed: _export,
          ),
        ),
      ),
    );
  }

  Widget _sum(String label, int value, {bool bold = false}) {
    final style = bold ? Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [Expanded(child: Text(label, style: style)), Text(formatPrice(value), style: style)]),
    );
  }
}

/// Thêm / sửa một dòng: tên, đơn giá, số lượng.
class _ItemDialog extends StatefulWidget {
  final InvoiceItem? item;
  const _ItemDialog({this.item});
  @override
  State<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<_ItemDialog> {
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _price = TextEditingController(text: (widget.item?.price ?? 0) > 0 ? formatNumber(widget.item!.price) : '');
  late int _qty = widget.item?.qty ?? 1;
  bool _tried = false;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.item == null ? 'Thêm sản phẩm' : 'Sửa dòng'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: _name,
              autofocus: widget.item == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: 'Tên sản phẩm', errorText: _tried && _name.text.trim().isEmpty ? 'Bắt buộc' : null),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _price,
              keyboardType: TextInputType.number,
              inputFormatters: [PriceInputFormatter()],
              decoration: const InputDecoration(labelText: 'Đơn giá', suffixText: '₫'),
            ),
            const SizedBox(height: 12),
            Row(children: [const Expanded(child: Text('Số lượng')), QtyStepper(value: _qty, onChanged: (v) => setState(() => _qty = v))]),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
          FilledButton(
            onPressed: () {
              if (_name.text.trim().isEmpty) return setState(() => _tried = true);
              Navigator.pop(
                context,
                InvoiceItem(name: _name.text.trim(), price: parsePrice(_price.text), qty: _qty, key: widget.item?.key),
              );
            },
            child: const Text('Lưu'),
          ),
        ],
      );
}

// ================================================================ Xem trước + lưu ảnh

class InvoicePreviewScreen extends StatefulWidget {
  final Invoice invoice;

  /// Lúc bấm "Xuất hoá đơn" — đặt tên file ảnh.
  final DateTime at;
  const InvoicePreviewScreen({super.key, required this.invoice, required this.at});
  @override
  State<InvoicePreviewScreen> createState() => _InvoicePreviewScreenState();
}

class _InvoicePreviewScreenState extends State<InvoicePreviewScreen> {
  final _boundary = GlobalKey();
  bool _saving = false;

  /// Chụp đúng phần hoá đơn (rộng 400, nét gấp 3) thành PNG.
  Future<Uint8List> _png() async {
    final ro = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await ro.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  static const _denied = 'Chưa có quyền lưu ảnh — vào Cài đặt > Kho ăn dặm > Ảnh, chọn "Chỉ thêm ảnh"';

  void _fail(String msg) {
    if (!mounted) return;
    setState(() => _saving = false);
    showSnack(context, msg, error: true);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      if (!await Gal.hasAccess() && !await Gal.requestAccess()) return _fail(_denied);
      final a = widget.at;
      final name = 'hoadon_${a.year}${_p2(a.month)}${_p2(a.day)}_${_p2(a.hour)}${_p2(a.minute)}${_p2(a.second)}';
      await Gal.putImageBytes(await _png(), name: name);
      InvoiceStore.instance.remove(widget.invoice); // đã lưu ảnh → xoá hoá đơn
      if (!mounted) return;
      showSnack(context, 'Đã lưu ảnh hoá đơn vào Thư viện ảnh');
      Navigator.popUntil(context, (r) => r.settings.name == _listRoute || r.isFirst);
    } on GalException catch (e) {
      _fail(e.type == GalExceptionType.accessDenied ? _denied : 'Không lưu được ảnh: ${e.type.message}');
    } catch (e) {
      _fail('Không lưu được ảnh: $e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.grey.shade300,
        appBar: AppBar(title: const Text('Xem trước hoá đơn')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Material(
                elevation: 2,
                child: RepaintBoundary(key: _boundary, child: InvoiceView(invoice: widget.invoice)),
              ),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  icon: const Icon(Icons.edit),
                  label: const Text('Chỉnh sửa'),
                  onPressed: _saving ? null : () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  icon: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.download),
                  label: Text(_saving ? 'Đang lưu…' : 'Lưu ảnh'),
                  onPressed: _saving ? null : _save,
                ),
              ),
            ]),
          ),
        ),
      );
}

String _p2(int n) => n.toString().padLeft(2, '0');
