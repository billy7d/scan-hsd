// ĐỌC — tra cứu: SearchScreen (tìm theo tên gần đúng / mã, lọc HSD) và ProductScreen
// (một sản phẩm + mọi date, sửa số lượng nhanh bằng −/+).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'date_parser.dart';
import 'entry_screen.dart';
import 'inventory_cache.dart';
import 'models.dart';
import 'scanner_screen.dart';
import 'ui.dart';

// ================================================================ Tìm kiếm

class SearchScreen extends StatefulWidget {
  final ExpiryFilter initialFilter;
  final bool autofocus;
  const SearchScreen({super.key, this.initialFilter = ExpiryFilter.all, this.autofocus = false});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _cache = InventoryCache.instance;
  final _q = TextEditingController();
  late ExpiryFilter _filter = widget.initialFilter;

  @override
  void initState() {
    super.initState();
    _cache.refreshIfStale().catchError((_) {});
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _q,
          autofocus: widget.autofocus,
          decoration: const InputDecoration(hintText: 'Tên sản phẩm (gần đúng) hoặc mã', border: InputBorder.none),
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          if (_q.text.isNotEmpty) IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(_q.clear)),
          IconButton(
            tooltip: 'Quét mã để đọc',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => scanLoop(context, ScanMode.read),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _cache,
        builder: (context, _) {
          final now = DateTime.now();
          final results = _cache.search(_q.text, filter: _filter, limit: _q.text.trim().isEmpty ? 1000 : 30, now: now);
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: SegmentedButton<ExpiryFilter>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ExpiryFilter.all, label: Text('Tất cả')),
                  ButtonSegment(value: ExpiryFilter.near, label: Text('≤ 90 ngày')),
                  ButtonSegment(value: ExpiryFilter.expired, label: Text('Hết hạn')),
                ],
                selected: {_filter},
                onSelectionChanged: (s) => setState(() => _filter = s.first),
              ),
            ),
            const Align(alignment: Alignment.centerRight, child: SyncStatus()),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _cache.refresh().catchError((Object e) {
                  if (context.mounted) showSnack(context, e.toString(), error: true);
                }),
                child: results.isEmpty
                    ? ListView(children: const [SizedBox(height: 48), Center(child: Text('Không tìm thấy sản phẩm'))])
                    : ListView.separated(
                        itemCount: results.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) => _SummaryTile(results[i], now),
                      ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final ProductSummary s;
  final DateTime now;
  const _SummaryTile(this.s, this.now);

  @override
  Widget build(BuildContext context) {
    final n = s.nearest;
    return ListTile(
      tileColor: n != null && n.qty > 0 ? expiryColor(expiryStatus(n.hsd, now)) : null,
      title: Text(s.product.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text([
        '${formatPrice(s.product.price)} · tổng ${s.totalQty} · ${s.rows.length} date',
        if (n != null) 'Gần nhất ${formatIsoVn(n.hsd)} (${daysLeftText(n.hsd, now)})',
      ].join('\n')),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductScreen(productKey: s.key))),
    );
  }
}

// ================================================================ Một sản phẩm

class ProductScreen extends StatefulWidget {
  final String? barcode;
  final String? productKey;
  const ProductScreen({super.key, this.barcode, this.productKey}) : assert(barcode != null || productKey != null);

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  final _cache = InventoryCache.instance;
  late String _key = widget.productKey ?? productKey(widget.barcode!, '');
  bool _checking = false;
  String? _error;

  String get _barcode => _key.startsWith('b:') ? _key.substring(2) : '';

  @override
  void initState() {
    super.initState();
    if (_barcode.isNotEmpty) {
      _revalidate(announce: true);
    } else {
      _cache.refreshIfStale().catchError((_) {});
    }
  }

  /// Hiện dữ liệu trên máy ngay, rồi hỏi sheet về đúng mã này.
  Future<void> _revalidate({bool announce = false}) async {
    final hadCache = _cache.byKey(_key) != null;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final res = await Api.lookup(_barcode);
      if (!mounted) return;
      final changed = _cache.applyLookup(_barcode, res);
      if (announce && changed && hadCache && res.found) showSnack(context, 'Đã cập nhật từ sheet');
    } on ApiException catch (e) {
      if (!mounted) return;
      if (hadCache) {
        showSnack(context, 'Không kiểm tra được với sheet — đang hiện dữ liệu trên máy');
      } else {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> onConflict() async {
    showSnack(context, 'Dữ liệu vừa thay đổi, hãy kiểm tra lại', error: true);
    await _cache.refresh().catchError((_) {});
    if (mounted && _barcode.isNotEmpty) await _revalidate();
  }

  Future<void> _editProduct(Product p) async {
    final updated = await showDialog<Product>(context: context, builder: (_) => _ProductEditDialog(product: p));
    if (updated == null || !mounted) return;
    try {
      final res = await runWithProgress(context, 'Đang lưu…', () => Api.updateProduct(p, updated));
      if (res.status == 'notFound') throw ConflictException('notFound');
      if (p.barcode.isEmpty) setState(() => _key = updated.key);
      await _cache.refresh();
      if (mounted) showSnack(context, 'Đã sửa ${res.rowsChanged} date');
    } on ConflictException {
      if (mounted) await onConflict();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _cache,
      builder: (context, _) {
        final s = _cache.byKey(_key);
        return Scaffold(
          appBar: AppBar(
            title: Text(s == null ? (_barcode.isEmpty ? 'Sản phẩm' : _barcode) : 'Đọc dữ liệu'),
            actions: [
              if (_checking)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              if (s != null)
                IconButton(tooltip: 'Sửa tên / giá', icon: const Icon(Icons.edit), onPressed: () => _editProduct(s.product)),
            ],
          ),
          body: s == null ? _empty() : _detail(s),
          bottomNavigationBar: s == null
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      icon: const Icon(Icons.add),
                      label: const Text('Ghi thêm date'),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EntryScreen(preset: s.product))),
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _empty() {
    if (_checking) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _revalidate, child: const Text('Thử lại')),
          ]),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.search_off, size: 56),
          const SizedBox(height: 8),
          Text('Chưa có trong kho', style: Theme.of(context).textTheme.titleLarge),
          if (_barcode.isNotEmpty) Text('Mã $_barcode'),
          const SizedBox(height: 16),
          if (_barcode.isNotEmpty)
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Ghi sản phẩm này'),
              onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => EntryScreen(barcode: _barcode))),
            ),
        ]),
      ),
    );
  }

  Widget _detail(ProductSummary s) {
    final p = s.product;
    final now = DateTime.now();
    final t = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: () async {
        await _cache.refresh().catchError((_) {});
        if (_barcode.isNotEmpty) await _revalidate();
      },
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _Stat(label: 'Giá bán', value: formatPrice(p.price))),
                Expanded(child: _Stat(label: 'Tổng số lượng', value: '${s.totalQty}')),
                Expanded(child: _Stat(label: 'Số date', value: '${s.rows.length}')),
              ]),
              const SizedBox(height: 6),
              Text(p.barcode.isEmpty ? 'Không có mã vạch' : 'Mã vạch: ${p.barcode}', style: t.bodySmall),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Text('Các date (gần hết hạn nhất trước)', style: t.titleMedium),
        const SizedBox(height: 4),
        for (final r in s.rows) LotCard(key: ValueKey(r.id), row: r, now: now, onConflict: onConflict),
        const Align(alignment: Alignment.centerRight, child: SyncStatus()),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      ]);
}

// ================================================================ Thẻ một date: sửa số lượng nhanh

/// Bấm −/+ liên tục: số trên màn hình đổi ngay; các lần bấm trong ~1,2 giây được gom thành một lệnh
/// gửi lên sheet (mỗi lệnh mất 2–4 giây). Lỗi → số quay về giá trị cũ.
class LotCard extends StatefulWidget {
  final InventoryRow row;
  final DateTime now;
  final Future<void> Function() onConflict;
  const LotCard({super.key, required this.row, required this.now, required this.onConflict});

  @override
  State<LotCard> createState() => _LotCardState();
}

class _LotCardState extends State<LotCard> {
  static const _debounce = Duration(milliseconds: 1200);
  final _cache = InventoryCache.instance;
  int _pending = 0; // chưa gửi
  int _sending = 0; // đang gửi
  Timer? _timer;

  InventoryRow get r => widget.row;
  int get _shown => r.qty + _sending + _pending;

  @override
  void dispose() {
    _timer?.cancel();
    // Rời màn hình khi còn thay đổi chưa gửi → vẫn gửi nốt.
    if (_pending != 0) _send(r, _pending, silent: true);
    super.dispose();
  }

  void _change(int delta) {
    final target = (_shown + delta).clamp(0, 1 << 30);
    final d = target - _shown;
    if (d == 0) return;
    HapticFeedback.selectionClick();
    setState(() => _pending += d);
    _timer?.cancel();
    _timer = Timer(_debounce, _flush);
  }

  Future<void> _setExact() async {
    final v = await askNumber(context, 'Số lượng date ${formatIsoVn(r.hsd)}', _shown);
    if (v != null) _change(v - _shown);
  }

  void _flush() {
    if (_pending == 0 || _sending != 0) return;
    final d = _pending;
    setState(() {
      _sending = d;
      _pending = 0;
    });
    _send(r, d);
  }

  Future<void> _send(InventoryRow row, int delta, {bool silent = false}) async {
    try {
      final res = await Api.adjust(row.id, Expect(row.product.barcode, row.hsd, row.qty), delta);
      _cache.patchRow(row.id, (x) => x.copyWith(qty: res.newQty));
      if (silent || !mounted) return;
      setState(() => _sending = 0);
      if (_pending != 0) {
        _timer?.cancel();
        _timer = Timer(const Duration(milliseconds: 300), _flush);
      } else if (res.newQty == 0) {
        _askDeleteEmpty();
      }
    } on ConflictException {
      if (silent || !mounted) return;
      setState(() {
        _sending = 0;
        _pending = 0;
      });
      await widget.onConflict();
    } on ApiException catch (e) {
      if (silent || !mounted) return;
      setState(() => _sending = 0); // quay về số đã lưu
      showSnack(context, 'Chưa lưu được số lượng: $e', error: true);
    }
  }

  Future<void> _askDeleteEmpty() async {
    final del = await confirmDialog(context, 'Hết date này', 'Date ${formatIsoVn(r.hsd)} còn 0. Xoá dòng này khỏi sheet?',
        confirm: 'Xoá', cancel: 'Giữ lại');
    if (del && mounted) await _delete(ask: false);
  }

  Future<void> _delete({bool ask = true}) async {
    if (ask && !await confirmDialog(context, 'Xoá date', 'Xoá date ${formatIsoVn(r.hsd)} (${r.qty}) khỏi sheet?', confirm: 'Xoá')) {
      return;
    }
    try {
      await Api.deleteLot(r.id, Expect(r.product.barcode, r.hsd, r.qty));
      _cache.removeRow(r.id);
    } on ConflictException {
      if (mounted) await widget.onConflict();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    }
  }

  Future<void> _editDate() async {
    final d = await pickHsd(context, parseIso(r.hsd));
    if (d == null || !mounted || isoDate(d) == r.hsd) return;
    final expect = Expect(r.product.barcode, r.hsd, r.qty);
    try {
      var res = await Api.updateLot(r.id, expect, hsd: isoDate(d));
      if (res.status == 'duplicate') {
        if (!mounted) return;
        final ok = await confirmDialog(context, 'Trùng date',
            'Đã có date ${formatVnDate(d)} (${res.currentQty}). Cộng ${r.qty} vào date đó?', confirm: 'Cộng dồn');
        if (!ok) return;
        res = await Api.updateLot(r.id, expect, hsd: isoDate(d), confirmMerge: true);
      }
      if (res.status == 'merged') {
        _cache.removeRow(r.id);
        _cache.patchRow(res.id!, (x) => x.copyWith(qty: res.newQty));
      } else {
        _cache.patchRow(r.id, (x) => x.copyWith(hsd: isoDate(d)));
      }
      _cache.refresh().catchError((_) {});
    } on ConflictException {
      if (mounted) await widget.onConflict();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final busy = _pending != 0 || _sending != 0;
    Widget quick(int d) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 46), padding: EdgeInsets.zero),
              onPressed: d < 0 && _shown == 0 ? null : () => _change(d),
              child: Text(d > 0 ? '+$d' : '$d', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
          ),
        );
    return Card(
      color: expiryColor(expiryStatus(r.hsd, widget.now)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Date ${formatIsoVn(r.hsd)}', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text(daysLeftText(r.hsd, widget.now)),
              ]),
            ),
            InkWell(
              onTap: _setExact,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Column(children: [
                  Text('$_shown', style: t.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
                  Text(busy ? 'đang lưu…' : 'chạm để gõ', style: t.labelSmall),
                ]),
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) => v == 'date' ? _editDate() : _delete(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'date', child: Text('Sửa date')),
                PopupMenuItem(value: 'delete', child: Text('Xoá date này')),
              ],
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [quick(-5), quick(-1), quick(1), quick(5)]),
        ]),
      ),
    );
  }
}

// ================================================================ Sửa tên / giá

class _ProductEditDialog extends StatefulWidget {
  final Product product;
  const _ProductEditDialog({required this.product});
  @override
  State<_ProductEditDialog> createState() => _ProductEditDialogState();
}

class _ProductEditDialogState extends State<_ProductEditDialog> {
  late final _name = TextEditingController(text: widget.product.name);
  late final _price =
      TextEditingController(text: widget.product.price > 0 ? formatPrice(widget.product.price).replaceAll(' ₫', '') : '');

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Sửa sản phẩm'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Áp dụng cho mọi date của sản phẩm này.'),
          const SizedBox(height: 12),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Tên sản phẩm')),
          const SizedBox(height: 12),
          TextField(
            controller: _price,
            keyboardType: TextInputType.number,
            inputFormatters: [PriceInputFormatter()],
            decoration: const InputDecoration(labelText: 'Giá bán', suffixText: '₫'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
          FilledButton(
            onPressed: () {
              if (_name.text.trim().isEmpty) return;
              Navigator.pop(
                context,
                Product(barcode: widget.product.barcode, name: _name.text.trim(), price: parsePrice(_price.text)),
              );
            },
            child: const Text('Lưu'),
          ),
        ],
      );
}
