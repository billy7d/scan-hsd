// GHI — nhập hàng: một sản phẩm (mã vạch hoặc không mã) với một hoặc nhiều date trong một lần lưu.
// Trả `true` qua Navigator.pop khi lưu thành công để vòng lặp quét tiếp.

import 'package:flutter/material.dart';

import 'api.dart';
import 'date_parser.dart';
import 'inventory_cache.dart';
import 'models.dart';
import 'text_fold.dart';
import 'ui.dart';

class _DateRow {
  DateTime? hsd;
  int qty = 1;
}

class EntryScreen extends StatefulWidget {
  final String? barcode;

  /// Sản phẩm chọn sẵn (từ màn tra cứu, "Ghi thêm date").
  final Product? preset;
  const EntryScreen({super.key, this.barcode, this.preset});

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  final _cache = InventoryCache.instance;
  final _name = TextEditingController();
  final _price = TextEditingController();
  final List<_DateRow> _dates = [_DateRow()];

  /// Sản phẩm đã có trong kho (để hiện các date đang có và biết đổi tên/giá).
  Product? _known;
  bool _loading = false;
  bool _saving = false;
  bool _tried = false;

  String get _barcode => (widget.barcode ?? widget.preset?.barcode ?? '').trim();

  @override
  void initState() {
    super.initState();
    final p = widget.preset ?? (_barcode.isNotEmpty ? _cache.byBarcode(_barcode)?.product : null);
    if (p != null) _fill(p);
    if (_barcode.isNotEmpty) _revalidate();
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  void _fill(Product p) {
    _known = p;
    _name.text = p.name;
    _price.text = p.price > 0 ? formatPrice(p.price).replaceAll(' ₫', '') : '';
  }

  /// Hỏi sheet về đúng mã này (dữ liệu trên máy có thể cũ).
  Future<void> _revalidate() async {
    setState(() => _loading = _known == null);
    try {
      final res = await Api.lookup(_barcode);
      if (!mounted) return;
      _cache.applyLookup(_barcode, res);
      if (res.found && _known == null) _fill(_cache.byBarcode(_barcode)?.product ?? res.product!);
    } on ApiException catch (e) {
      if (mounted && _known == null) showSnack(context, 'Không kiểm tra được với sheet: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Hàng không mã: gõ đúng tên một sản phẩm không mã đã có → coi là sản phẩm đó.
  void _onNameChanged(String v) {
    if (_barcode.isNotEmpty) return setState(() {});
    final hit = _cache.byKey(productKey('', v));
    setState(() {
      _known = hit?.product;
      if (hit != null && _price.text.trim().isEmpty && hit.product.price > 0) {
        _price.text = formatPrice(hit.product.price).replaceAll(' ₫', '');
      }
    });
  }

  Future<void> _pickNoBarcode() async {
    final p = await pickProduct(context, _cache.withoutBarcode, title: 'Chọn sản phẩm không mã vạch');
    if (p != null) setState(() => _fill(p.product));
  }

  List<InventoryRow> get _existing => _known == null ? const [] : (_cache.byKey(_known!.key)?.rows ?? const []);

  // ------------------------------------------------------------ Lưu

  Future<void> _save() async {
    setState(() => _tried = true);
    final name = _name.text.trim();
    if (name.isEmpty) return showSnack(context, 'Hãy nhập tên sản phẩm', error: true);
    if (_dates.any((d) => d.hsd == null)) return showSnack(context, 'Còn dòng chưa chọn date', error: true);

    // Gộp các dòng trùng date trong form.
    final byDate = <String, int>{};
    for (final d in _dates) {
      byDate[isoDate(d.hsd!)] = (byDate[isoDate(d.hsd!)] ?? 0) + d.qty;
    }
    final lots = [for (final e in byDate.entries) NewLot(e.key, e.value)];
    final price = parsePrice(_price.text);
    final key = productKey(_barcode, name);
    final existing = _cache.byKey(key)?.rows ?? const <InventoryRow>[];

    // Date đã có → hỏi cộng dồn trước khi gửi.
    final dups = [for (final l in lots) if (existing.any((r) => r.hsd == l.hsd)) l];
    var merge = false;
    if (dups.isNotEmpty) {
      merge = await confirmDialog(
        context,
        'Date đã có trong kho',
        dups.map((l) => '• ${formatIsoVn(l.hsd)}: đang có ${existing.firstWhere((r) => r.hsd == l.hsd).qty} → cộng thêm ${l.qty}').join('\n'),
        confirm: 'Cộng dồn',
      );
      if (!merge || !mounted) return;
    }

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      var results = await Api.add(barcode: _barcode, name: name, price: price, lots: lots, confirmMerge: merge);
      // Sheet có date trùng mà máy chưa biết (dữ liệu cũ) → hỏi rồi gửi lại riêng các date đó.
      final late = [for (var i = 0; i < results.length; i++) if (results[i].status == 'duplicate') i];
      if (late.isNotEmpty && mounted) {
        final ok = await confirmDialog(
          context,
          'Date đã có trong kho',
          late.map((i) => '• ${formatIsoVn(lots[i].hsd)}: đang có ${results[i].currentQty} → cộng thêm ${lots[i].qty}').join('\n'),
          confirm: 'Cộng dồn',
        );
        if (ok) {
          final again = await Api.add(
              barcode: _barcode, name: name, price: price, lots: [for (final i in late) lots[i]], confirmMerge: true);
          results = [...results.where((r) => r.status != 'duplicate'), ...again];
        }
      }
      final saved = results.where((r) => r.status == 'created' || r.status == 'merged').length;
      messenger.showSnackBar(SnackBar(behavior: SnackBarBehavior.floating, content: Text('Đã lưu $saved date — $name')));
      _cache.refresh().catchError((_) {});
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, e.toString(), error: true);
      }
    }
  }

  // ------------------------------------------------------------ Giao diện

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final changedProduct = _known != null &&
        (normKey(_name.text) != normKey(_known!.name) || parsePrice(_price.text) != _known!.price) &&
        _existing.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text(_barcode.isEmpty ? 'Ghi hàng không mã vạch' : 'Ghi · $_barcode')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 120), children: [
              _banner(),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                onChanged: _onNameChanged,
                style: t.titleMedium,
                decoration: InputDecoration(
                  labelText: 'Tên sản phẩm *',
                  errorText: _tried && _name.text.trim().isEmpty ? 'Bắt buộc' : null,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _price,
                keyboardType: TextInputType.number,
                inputFormatters: [PriceInputFormatter()],
                onChanged: (_) => setState(() {}),
                style: t.titleMedium,
                decoration: const InputDecoration(labelText: 'Giá bán', suffixText: '₫'),
              ),
              if (changedProduct)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Tên/giá mới sẽ áp dụng cho mọi date của sản phẩm này.',
                      style: t.bodySmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
                ),
              if (_existing.isNotEmpty) ...[const SizedBox(height: 16), _existingCard()],
              const SizedBox(height: 20),
              Text('Date nhập lần này', style: t.titleMedium),
              const SizedBox(height: 8),
              for (var i = 0; i < _dates.length; i++) _dateRow(i),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                icon: const Icon(Icons.add),
                label: const Text('Thêm date khác'),
                onPressed: () => setState(() => _dates.add(_DateRow())),
              ),
            ]),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  icon: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: Text(_saving ? 'Đang lưu…' : 'Lưu (${_dates.length} date)'),
                  onPressed: _saving ? null : _save,
                ),
              ),
            ),
    );
  }

  Widget _banner() {
    Widget box(Color color, IconData icon, String text) => Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [Icon(icon), const SizedBox(width: 10), Expanded(child: Text(text))]),
        );
    if (_known != null) return box(Colors.green.shade100, Icons.check_circle, 'Sản phẩm đã có — tên và giá đã điền sẵn');
    if (_barcode.isNotEmpty) return box(Colors.amber.shade100, Icons.fiber_new, 'Mã vạch mới — nhập tên và giá một lần');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      box(Theme.of(context).colorScheme.surfaceContainerHighest, Icons.inventory_2, 'Hàng không mã vạch — nhận diện theo tên'),
      if (_cache.withoutBarcode.isNotEmpty) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(icon: const Icon(Icons.list), label: const Text('Chọn sản phẩm không mã đã có'), onPressed: _pickNoBarcode),
      ],
    ]);
  }

  Widget _existingCard() {
    final now = DateTime.now();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Đang có trong kho', style: Theme.of(context).textTheme.titleSmall),
          for (final r in _existing)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: expiryColor(expiryStatus(r.hsd, now)),
              child: Text('${formatIsoVn(r.hsd)} — ${r.qty} · ${daysLeftText(r.hsd, now)}'),
            ),
        ]),
      ),
    );
  }

  Widget _dateRow(int i) {
    final d = _dates[i];
    final dup = d.hsd != null && _existing.any((r) => r.hsd == isoDate(d.hsd!));
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(children: [
          Expanded(
            child: InkWell(
              onTap: () async {
                final v = await pickHsd(context, d.hsd);
                if (v != null) setState(() => d.hsd = v);
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Date *',
                  isDense: true,
                  errorText: _tried && d.hsd == null ? 'Chọn date' : null,
                  helperText: dup ? 'Đã có — sẽ hỏi cộng dồn' : null,
                ),
                child: Text(d.hsd == null ? 'Chạm để chọn' : formatVnDate(d.hsd!), style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
          ),
          const SizedBox(width: 8),
          QtyStepper(value: d.qty, onChanged: (v) => setState(() => d.qty = v)),
          if (_dates.length > 1)
            IconButton(tooltip: 'Bỏ dòng này', icon: const Icon(Icons.close), onPressed: () => setState(() => _dates.removeAt(i))),
        ]),
      ),
    );
  }
}
