// Bản sao sheet trên máy: tra cứu / tìm kiếm tức thì, dùng được khi sóng yếu.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'config.dart';
import 'models.dart';
import 'text_fold.dart';

/// Một sản phẩm và mọi date của nó, date gần hết hạn nhất trước.
class ProductSummary {
  final Product product;
  final List<InventoryRow> rows;
  ProductSummary(this.product, List<InventoryRow> rows)
      : rows = (rows.toList()..sort((a, b) => (a.hsd.isEmpty ? '9999' : a.hsd).compareTo(b.hsd.isEmpty ? '9999' : b.hsd)));

  String get key => product.key;
  int get totalQty => rows.fold(0, (s, r) => s + r.qty);

  /// Date còn hàng gần hết hạn nhất (không có thì date đầu tiên).
  InventoryRow? get nearest => rows.where((r) => r.qty > 0).firstOrNull ?? rows.firstOrNull;
}

enum ExpiryFilter { all, near, expired }

class InventoryCache extends ChangeNotifier {
  static final InventoryCache instance = InventoryCache();

  InventoryCache({Future<File> Function()? fileProvider, Future<List<InventoryRow>> Function()? fetcher})
      : _fileProvider = fileProvider ?? _defaultFile,
        _fetcher = fetcher ?? Api.snapshot;

  final Future<File> Function() _fileProvider;
  final Future<List<InventoryRow>> Function() _fetcher;

  List<InventoryRow> _rows = [];
  List<ProductSummary> _products = [];
  DateTime? fetchedAt;
  bool refreshing = false;
  String? lastError;
  Future<void>? _inflight;

  List<InventoryRow> get rows => _rows;
  List<ProductSummary> get products => _products;
  bool get isStale => fetchedAt == null || DateTime.now().difference(fetchedAt!) > Config.snapshotMaxAge;

  static Future<File> _defaultFile() async => File('${(await getApplicationDocumentsDirectory()).path}/snapshot_v2.json');

  void setRows(List<InventoryRow> rows, DateTime at) {
    _rows = rows;
    fetchedAt = at;
    _rebuild();
  }

  void _rebuild() {
    final groups = <String, List<InventoryRow>>{};
    for (final r in _rows) {
      groups.putIfAbsent(r.product.key, () => []).add(r);
    }
    _products = [
      for (final g in groups.values)
        ProductSummary(
          Product(
            barcode: g.first.product.barcode,
            name: g.map((r) => r.product.name).firstWhere((n) => n.isNotEmpty, orElse: () => ''),
            price: g.map((r) => r.product.price).firstWhere((p) => p > 0, orElse: () => 0),
          ),
          g,
        ),
    ];
    notifyListeners();
  }

  Future<void> load() async {
    try {
      final f = await _fileProvider();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      setRows([for (final r in j['rows'] as List) InventoryRow.fromList(r as List)], DateTime.parse(j['fetchedAt'] as String));
    } catch (_) {
      // File hỏng → bỏ qua, sẽ tải lại từ sheet.
    }
  }

  /// Tải toàn bộ sheet. Gọi trùng lúc đang tải thì dùng chung một lần tải.
  Future<void> refresh() => _inflight ??= _doRefresh().whenComplete(() => _inflight = null);

  Future<void> refreshIfStale() => isStale ? refresh() : Future.value();

  Future<void> _doRefresh() async {
    refreshing = true;
    notifyListeners();
    try {
      final rows = await _fetcher();
      lastError = null;
      setRows(rows, DateTime.now());
      try {
        await (await _fileProvider())
            .writeAsString(jsonEncode({'fetchedAt': fetchedAt!.toIso8601String(), 'rows': [for (final r in rows) r.toList()]}));
      } catch (_) {}
    } catch (e) {
      lastError = e.toString();
      rethrow;
    } finally {
      refreshing = false;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------ Cập nhật cục bộ sau khi ghi thành công

  void patchRow(String id, InventoryRow Function(InventoryRow r) f) {
    _rows = [for (final r in _rows) r.id == id ? f(r) : r];
    _rebuild();
  }

  void removeRow(String id) {
    _rows = _rows.where((r) => r.id != id).toList();
    _rebuild();
  }

  void addRows(List<InventoryRow> rows) {
    _rows = [..._rows, ...rows];
    _rebuild();
  }

  /// Thay mọi date của một mã vạch bằng kết quả `lookup` mới nhất. Trả true nếu có khác biệt.
  bool applyLookup(String barcode, LookupResult res) {
    final code = normBarcode(barcode);
    bool mine(InventoryRow r) => normBarcode(r.product.barcode) == code;
    final old = _rows.where(mine).toList();
    final fresh = res.found
        ? [for (final l in res.lots) InventoryRow(id: l.id, product: res.product!, hsd: l.hsd, qty: l.qty)]
        : <InventoryRow>[];
    String sig(List<InventoryRow> rs) =>
        (rs.map((r) => '${r.id}|${r.hsd}|${r.qty}|${r.product.name}|${r.product.price}').toList()..sort()).join(';');
    if (sig(old) == sig(fresh)) return false;
    _rows = [..._rows.where((r) => !mine(r)), ...fresh];
    _rebuild();
    return true;
  }

  // ------------------------------------------------------------ Tra cứu

  ProductSummary? byKey(String key) => _products.where((p) => p.key == key).firstOrNull;

  /// Mã vạch phải trùng khớp (UPC 12 số = EAN-13 số 0 đầu).
  ProductSummary? byBarcode(String code) => code.trim().isEmpty ? null : byKey(productKey(code, ''));

  /// Tìm theo tên gần đúng (không dấu, sai 1–2 chữ cái, gõ đầu chữ) hoặc theo mã / đuôi mã (≥ 4 số).
  List<ProductSummary> search(String query, {int limit = 30, ExpiryFilter filter = ExpiryFilter.all, DateTime? now}) {
    now ??= DateTime.now();
    final pool = filter == ExpiryFilter.all ? _products : _filtered(filter, now);
    final q = query.trim();
    if (q.isEmpty) return _sortedByName(pool).take(limit).toList();

    final digits = q.replaceAll(RegExp(r'\s'), '');
    if (RegExp(r'^\d{4,}$').hasMatch(digits)) {
      final code = normBarcode(digits);
      final hits = [
        ...pool.where((p) => normBarcode(p.product.barcode) == code),
        ...pool.where((p) => normBarcode(p.product.barcode) != code && p.product.barcode.endsWith(digits)),
      ];
      if (hits.isNotEmpty) return hits.take(limit).toList();
    }

    final scored = <({ProductSummary p, double score})>[];
    for (final p in pool) {
      final s = nameMatchScore(q, p.product.name);
      if (s > 0) scored.add((p: p, score: s));
    }
    scored.sort((a, b) => a.score != b.score ? b.score.compareTo(a.score) : foldText(a.p.product.name).compareTo(foldText(b.p.product.name)));
    return scored.take(limit).map((x) => x.p).toList();
  }

  List<ProductSummary> _sortedByName(Iterable<ProductSummary> ps) =>
      ps.toList()..sort((a, b) => foldText(a.product.name).compareTo(foldText(b.product.name)));

  List<ProductSummary> _filtered(ExpiryFilter filter, DateTime now) {
    bool match(InventoryRow r) {
      if (r.qty <= 0) return false;
      final n = daysLeft(r.hsd, now);
      if (n == null) return false;
      return filter == ExpiryFilter.expired ? n < 0 : n >= 0 && n <= Config.nearExpiryDays;
    }

    final out = _products.where((p) => p.rows.any(match)).toList();
    out.sort((a, b) => a.rows.firstWhere(match).hsd.compareTo(b.rows.firstWhere(match).hsd));
    return out;
  }

  List<ProductSummary> nearExpiry({DateTime? now}) => _filtered(ExpiryFilter.near, now ?? DateTime.now());
  List<ProductSummary> expired({DateTime? now}) => _filtered(ExpiryFilter.expired, now ?? DateTime.now());

  /// Sản phẩm không có mã vạch — để chọn khi nhập hàng không mã.
  List<ProductSummary> get withoutBarcode => _sortedByName(_products.where((p) => p.product.barcode.isEmpty));
}

// ---------------------------------------------------------------- Tìm tên gần đúng

/// Điểm khớp giữa chữ gõ và tên sản phẩm (0 = không khớp). Mỗi từ gõ phải khớp một từ trong tên:
/// trùng (3 điểm) > là đầu của từ (2) > lệch 1 chữ cái, hoặc 2 nếu từ dài ≥ 7 (1). Bỏ dấu, không phân biệt hoa thường.
double nameMatchScore(String query, String name) {
  final qWords = foldText(query).split(RegExp(r'[^a-z0-9]+')).where((w) => w.isNotEmpty).toList();
  final nWords = foldText(name).split(RegExp(r'[^a-z0-9]+')).where((w) => w.isNotEmpty).toList();
  if (qWords.isEmpty || nWords.isEmpty) return 0;
  var total = 0.0;
  for (final q in qWords) {
    var best = 0.0;
    for (final n in nWords) {
      double s = 0;
      if (n == q) {
        s = 3;
      } else if (n.startsWith(q)) {
        s = 2;
      } else if (q.length >= 3) {
        final max = q.length >= 7 ? 2 : 1;
        if (_editDistance(q, n, max) <= max || (n.length > q.length && _editDistance(q, n.substring(0, q.length), 1) <= 1 && q.length >= 4)) {
          s = 1;
        }
      }
      if (s > best) best = s;
    }
    if (best == 0) return 0;
    total += best;
  }
  return total / qWords.length;
}

int _editDistance(String a, String b, int max) {
  if ((a.length - b.length).abs() > max) return max + 1;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    var rowMin = i;
    for (var j = 1; j <= b.length; j++) {
      final c = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var v = prev[j] + 1;
      if (cur[j - 1] + 1 < v) v = cur[j - 1] + 1;
      if (prev[j - 1] + c < v) v = prev[j - 1] + c;
      cur[j] = v;
      if (v < rowMin) rowMin = v;
    }
    if (rowMin > max) return max + 1;
    prev = cur;
  }
  return prev[b.length];
}
