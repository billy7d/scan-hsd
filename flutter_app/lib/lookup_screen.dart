// ĐỌC — tra cứu: SearchScreen (tìm theo tên gần đúng / mã, lọc HSD) và ProductScreen
// (một sản phẩm + mọi date, sửa số lượng nhanh bằng −/+).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'date_parser.dart';
import 'entry_screen.dart';
import 'inventory_cache.dart';
import 'invoice.dart';
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
        '${s.summaryText} · ${s.rows.length} date',
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

  Future<void> _editProduct(ProductSummary s) async {
    final p = s.product;
    final out = await showDialog<(Product, int?)>(context: context, builder: (_) => _ProductEditDialog(summary: s));
    if (out == null || !mounted) return;
    final (updated, priceLe) = out;
    try {
      final res = await runWithProgress(context, 'Đang lưu…', () => Api.updateProduct(p, updated, priceLe: priceLe));
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
                IconButton(tooltip: 'Sửa tên / giá', icon: const Icon(Icons.edit), onPressed: () => _editProduct(s)),
            ],
          ),
          body: s == null ? _empty() : _detail(s),
          bottomNavigationBar: s == null
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                          icon: const Icon(Icons.add),
                          label: const Text('Ghi thêm lốc'),
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EntryScreen(preset: s.product))),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                          icon: const Icon(Icons.add),
                          label: const Text('Ghi thêm lẻ'),
                          onPressed: () =>
                              Navigator.push(context, MaterialPageRoute(builder: (_) => EntryScreen(preset: s.product, le: true))),
                        ),
                      ),
                    ]),
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
          // Lệch một số so với sản phẩm đã có → nhiều khả năng camera đọc nhầm.
          for (final p in _barcode.isEmpty ? const <ProductSummary>[] : _cache.similarBarcodes(_barcode)) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.swap_horiz),
              label: Text('Có phải: ${p.product.name}\n${p.product.barcode}', textAlign: TextAlign.center),
              onPressed: () {
                setState(() => _key = p.key);
                _revalidate();
              },
            ),
          ],
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
              if (!s.hasLe)
                Row(children: [
                  Expanded(child: _Stat(label: 'Giá bán', value: formatPrice(p.price))),
                  Expanded(child: _Stat(label: 'Tổng số lượng', value: '${s.totalQty}')),
                  Expanded(child: _Stat(label: 'Số date', value: '${s.rows.length}')),
                ])
              else ...[
                Row(children: [
                  Expanded(child: _Stat(label: 'Giá lốc', value: formatPrice(p.price))),
                  Expanded(child: _Stat(label: 'Tổng lốc', value: '${s.totalQty}')),
                  Expanded(child: _Stat(label: 'Date lốc', value: '${s.lotRows.length}')),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _Stat(label: 'Giá lẻ', value: formatPrice(s.priceLe))),
                  Expanded(child: _Stat(label: 'Tổng lẻ', value: '${s.totalLe}')),
                  Expanded(child: _Stat(label: 'Date lẻ', value: '${s.leRows.length}')),
                ]),
              ],
              const SizedBox(height: 6),
              Text(p.barcode.isEmpty ? 'Không có mã vạch' : 'Mã vạch: ${p.barcode}', style: t.bodySmall),
            ]),
          ),
        ),
        if (s.lotRows.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(s.hasLe ? 'Nguyên lốc (gần hết hạn nhất trước)' : 'Các date (gần hết hạn nhất trước)', style: t.titleMedium),
          const SizedBox(height: 4),
          for (final r in s.lotRows) LotCard(key: ValueKey(r.id), row: r, now: now, onConflict: onConflict),
        ],
        if (s.hasLe) ...[
          const SizedBox(height: 12),
          Text('Hàng lẻ (gần hết hạn nhất trước)', style: t.titleMedium),
          const SizedBox(height: 4),
          for (final r in s.leRows) LotCard(key: ValueKey(r.id), row: r, now: now, onConflict: onConflict),
        ],
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
    final v = await askNumber(context, 'Số lượng${r.le ? ' lẻ' : ''} date ${formatIsoVn(r.hsd)}', _shown);
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
      InvoiceStore.instance.recordAdjust(row, delta); // bán → vào hoá đơn tạm
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
    final message = _deleteMessage('Date ${formatIsoVn(r.hsd)} còn 0. Xoá dòng này khỏi sheet?',
        keepHint: '\n\nChọn "Giữ lại" để vẫn hiện trong danh sách với số lượng 0.');
    final del = await confirmDialog(context, 'Hết date này', message, confirm: 'Xoá', cancel: 'Giữ lại');
    if (del && mounted) await _delete(ask: false);
  }

  /// Câu hỏi xoá, thêm cảnh báo nếu [r] là date cuối cùng của sản phẩm hoặc của loại (lốc / lẻ).
  String _deleteMessage(String question, {String keepHint = ''}) {
    final warning = _cache.byKey(r.product.key)?.lastDateWarning(r);
    return warning == null ? question : '$question\n\n$warning$keepHint';
  }

  Future<void> _delete({bool ask = true}) async {
    if (ask && !await confirmDialog(context, 'Xoá date', _deleteMessage('Xoá date ${formatIsoVn(r.hsd)} (${r.qty}) khỏi sheet?'), confirm: 'Xoá')) {
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

  /// Mở lốc: trừ lốc, cộng hàng lẻ cùng date.
  Future<void> _openPack() async {
    if (_pending != 0 || _sending != 0) return showSnack(context, 'Đợi lưu xong số lượng rồi mở lốc');
    final s = _cache.byKey(r.product.key);
    final remembered = await PackSizes.instance.get(r.product.key);
    if (!mounted) return;
    final input = await showDialog<_OpenPackInput>(
      context: context,
      builder: (_) => _OpenPackDialog(row: r, perPack: remembered, priceLe: s?.priceLe ?? 0),
    );
    if (input == null || !mounted) return;
    final expect = Expect(r.product.barcode, r.hsd, r.qty);
    try {
      final res = await runWithProgress(context, 'Đang mở lốc…',
          () => Api.openPack(r.id, expect, perPack: input.perPack, count: input.count, priceLe: input.priceLe));
      PackSizes.instance.set(r.product.key, input.perPack);
      _cache.patchRow(r.id, (x) => x.copyWith(qty: res.newQty));
      if (_cache.rows.any((x) => x.id == res.leId)) {
        _cache.patchRow(res.leId!, (x) => x.copyWith(qty: res.leQty));
      } else {
        final priceLe = input.priceLe > 0 ? input.priceLe : s?.priceLe ?? 0;
        _cache.addRows([
          InventoryRow(
            id: res.leId!,
            product: Product(barcode: r.product.barcode, name: r.product.name, price: priceLe),
            hsd: r.hsd,
            qty: res.leQty!,
            le: true,
          ),
        ]);
      }
      if (mounted) showSnack(context, 'Đã mở ${input.count} lốc → +${input.count * input.perPack} lẻ (date ${formatIsoVn(r.hsd)})');
      _cache.refresh().catchError((_) {});
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
                Text('${r.le ? 'Lẻ · ' : ''}Date ${formatIsoVn(r.hsd)}', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
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
              onSelected: (v) => switch (v) { 'open' => _openPack(), 'date' => _editDate(), _ => _delete() },
              itemBuilder: (_) => [
                if (!r.le && _shown > 0) const PopupMenuItem(value: 'open', child: Text('Mở lốc → bán lẻ')),
                const PopupMenuItem(value: 'date', child: Text('Sửa date')),
                const PopupMenuItem(value: 'delete', child: Text('Xoá date này')),
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

/// Trả (sản phẩm mới, giá lẻ mới — null nếu sản phẩm chưa có hàng lẻ).
class _ProductEditDialog extends StatefulWidget {
  final ProductSummary summary;
  const _ProductEditDialog({required this.summary});
  @override
  State<_ProductEditDialog> createState() => _ProductEditDialogState();
}

String _priceText(int p) => p > 0 ? formatPrice(p).replaceAll(' ₫', '') : '';

class _ProductEditDialogState extends State<_ProductEditDialog> {
  Product get _p => widget.summary.product;
  bool get _hasLe => widget.summary.hasLe;
  late final _name = TextEditingController(text: _p.name);
  late final _price = TextEditingController(text: _priceText(_p.price));
  late final _priceLe = TextEditingController(text: _priceText(widget.summary.priceLe));

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _priceLe.dispose();
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
            decoration: InputDecoration(labelText: _hasLe ? 'Giá bán lốc' : 'Giá bán', suffixText: '₫'),
          ),
          if (_hasLe) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _priceLe,
              keyboardType: TextInputType.number,
              inputFormatters: [PriceInputFormatter()],
              decoration: const InputDecoration(labelText: 'Giá bán lẻ (1 hộp)', suffixText: '₫'),
            ),
          ],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
          FilledButton(
            onPressed: () {
              if (_name.text.trim().isEmpty) return;
              Navigator.pop(context, (
                Product(barcode: _p.barcode, name: _name.text.trim(), price: parsePrice(_price.text)),
                _hasLe ? parsePrice(_priceLe.text) : null,
              ));
            },
            child: const Text('Lưu'),
          ),
        ],
      );
}

// ================================================================ Mở lốc

class _OpenPackInput {
  final int count;
  final int perPack;
  final int priceLe;
  const _OpenPackInput(this.count, this.perPack, this.priceLe);
}

/// Hỏi số lốc mở, số hộp mỗi lốc (điền sẵn số lần trước) và giá lẻ (điền sẵn giá đang lưu).
class _OpenPackDialog extends StatefulWidget {
  final InventoryRow row;
  final int? perPack;
  final int priceLe;
  const _OpenPackDialog({required this.row, required this.perPack, required this.priceLe});
  @override
  State<_OpenPackDialog> createState() => _OpenPackDialogState();
}

class _OpenPackDialogState extends State<_OpenPackDialog> {
  int _count = 1;
  late final _perPack = TextEditingController(text: widget.perPack?.toString() ?? '');
  late final _priceLe = TextEditingController(text: _priceText(widget.priceLe));
  bool _tried = false;

  int? get _per {
    final n = int.tryParse(_perPack.text.trim());
    return n != null && n >= 1 && n <= 1000 ? n : null;
  }

  @override
  void dispose() {
    _perPack.dispose();
    _priceLe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final per = _per;
    return AlertDialog(
      title: const Text('Mở lốc → bán lẻ'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Date ${formatIsoVn(r.hsd)} · đang có ${r.qty} lốc'),
          const SizedBox(height: 12),
          Row(children: [
            const Expanded(child: Text('Số lốc mở')),
            QtyStepper(value: _count, onChanged: (v) => setState(() => _count = v.clamp(1, r.qty))),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _perPack,
            autofocus: widget.perPack == null,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: '1 lốc = mấy hộp?',
              errorText: _tried && per == null ? 'Nhập số hộp (1–1000)' : null,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _priceLe,
            keyboardType: TextInputType.number,
            inputFormatters: [PriceInputFormatter()],
            decoration: InputDecoration(
              labelText: 'Giá bán lẻ (1 hộp)',
              suffixText: '₫',
              helperText: widget.priceLe > 0 ? 'Đổi giá → áp dụng mọi date hàng lẻ' : 'Chưa có giá lẻ — nhập một lần',
            ),
          ),
          if (per != null) ...[
            const SizedBox(height: 12),
            Text('Lốc: ${r.qty} → ${r.qty - _count}  ·  Lẻ: +${_count * per}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
        FilledButton(
          onPressed: () {
            if (per == null) return setState(() => _tried = true);
            Navigator.pop(context, _OpenPackInput(_count, per, parsePrice(_priceLe.text)));
          },
          child: const Text('Mở lốc'),
        ),
      ],
    );
  }
}
