// Hoá đơn tạm tính: lưu trên máy (invoices.json), không đụng tới sheet / số lượng trong kho.
// Hoá đơn tự tạo gom các lần trừ số lượng ở màn ĐỌC; 30 phút không trừ / sửa thêm → tự xoá.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

class InvoiceItem {
  String name;
  int price;
  int qty;

  /// Khoá sản phẩm + loại (lốc / lẻ) — hoá đơn tự tạo gom các lần trừ cùng khoá vào một dòng.
  /// null = dòng nhập tay.
  final String? key;

  InvoiceItem({required this.name, required this.price, required this.qty, this.key});

  int get total => price * qty;

  Map<String, dynamic> toJson() => {'name': name, 'price': price, 'qty': qty, 'key': key};

  factory InvoiceItem.fromJson(Map<String, dynamic> j) => InvoiceItem(
        name: j['name']?.toString() ?? '',
        price: (j['price'] as num?)?.toInt() ?? 0,
        qty: (j['qty'] as num?)?.toInt() ?? 0,
        key: j['key']?.toString(),
      );
}

class Invoice {
  final String id;

  /// true = tự tạo từ các lần trừ số lượng; false = tạo thủ công.
  final bool auto;
  final DateTime createdAt;

  /// Lần trừ / sửa cuối — hoá đơn tự tạo hết hạn sau [InvoiceStore.ttl] kể từ đây.
  DateTime touchedAt;
  String customer;
  int shipFee;
  final List<InvoiceItem> items;

  Invoice({
    required this.id,
    required this.auto,
    required this.createdAt,
    required this.touchedAt,
    this.customer = '',
    this.shipFee = 0,
    List<InvoiceItem>? items,
  }) : items = items ?? [];

  int get totalQty => items.fold(0, (s, i) => s + i.qty);
  int get subtotal => items.fold(0, (s, i) => s + i.total);
  int get total => subtotal + shipFee;
  DateTime? get expiresAt => auto ? touchedAt.add(InvoiceStore.ttl) : null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'auto': auto,
        'createdAt': createdAt.toIso8601String(),
        'touchedAt': touchedAt.toIso8601String(),
        'customer': customer,
        'shipFee': shipFee,
        'items': [for (final i in items) i.toJson()],
      };

  factory Invoice.fromJson(Map<String, dynamic> j) => Invoice(
        id: j['id'].toString(),
        auto: j['auto'] == true,
        createdAt: DateTime.parse(j['createdAt'] as String),
        touchedAt: DateTime.parse(j['touchedAt'] as String),
        customer: j['customer']?.toString() ?? '',
        shipFee: (j['shipFee'] as num?)?.toInt() ?? 0,
        items: [for (final i in j['items'] as List) InvoiceItem.fromJson(Map<String, dynamic>.from(i as Map))],
      );
}

/// Tên dòng hoá đơn của một date trong kho: hàng lẻ thêm "(lẻ)".
String invoiceItemName(InventoryRow r) => r.le ? '${r.product.name} (lẻ)' : r.product.name;

class InvoiceStore extends ChangeNotifier {
  static const ttl = Duration(minutes: 30);
  static final InvoiceStore instance = InvoiceStore();

  InvoiceStore({Future<File> Function()? fileProvider, DateTime Function()? clock})
      : _fileProvider = fileProvider ?? _defaultFile,
        _clock = clock ?? DateTime.now;

  final Future<File> Function() _fileProvider;
  final DateTime Function() _clock;
  List<Invoice> _list = [];
  final Set<String> _held = {};
  Timer? _timer;
  int _seq = 0;

  static Future<File> _defaultFile() async => File('${(await getApplicationDocumentsDirectory()).path}/invoices.json');

  /// Còn hiệu lực: thủ công, đang mở, hoặc tự tạo chưa quá [ttl]. Getter chỉ lọc (gọi được trong build);
  /// xoá hẳn ở [purgeExpired].
  bool _alive(Invoice i, DateTime now) => !i.auto || _held.contains(i.id) || now.isBefore(i.expiresAt!);

  /// Hoá đơn tự tạo trước, rồi hoá đơn thủ công mới nhất trước.
  List<Invoice> get invoices {
    final now = _clock();
    return _list.where((i) => _alive(i, now)).toList()
      ..sort((a, b) => a.auto != b.auto ? (a.auto ? -1 : 1) : b.createdAt.compareTo(a.createdAt));
  }

  Invoice? byId(String id) => _list.where((i) => i.id == id).firstOrNull;

  /// Hoá đơn tự tạo còn hạn (lần trừ tiếp theo sẽ gom vào đây).
  Invoice? get activeAuto {
    final now = _clock();
    return _list.where((i) => i.auto && _alive(i, now)).firstOrNull;
  }

  Future<void> load() async {
    try {
      final f = await _fileProvider();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as List;
        _list = [for (final i in j) Invoice.fromJson(Map<String, dynamic>.from(i as Map))];
      }
    } catch (_) {
      _list = []; // file hỏng → bỏ
    }
    purgeExpired();
    notifyListeners();
  }

  /// Kiểm tra hết hạn mỗi phút khi app đang mở.
  void startAutoPurge() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => purgeExpired());
  }

  /// Xoá hoá đơn tự tạo quá [ttl] kể từ lần trừ / sửa cuối (trừ hoá đơn đang mở để sửa / xem trước).
  void purgeExpired() {
    final now = _clock();
    final before = _list.length;
    _list.removeWhere((i) => !_alive(i, now));
    if (_list.length != before) {
      _save();
      notifyListeners();
    }
  }

  /// Số lượng trong kho vừa đổi [delta] (âm = bán). Bán → cộng vào hoá đơn tự tạo (chưa có thì tạo);
  /// cộng lại kho → giảm dòng tương ứng (về 0 thì bỏ dòng). Không đụng hoá đơn thủ công.
  void recordAdjust(InventoryRow row, int delta) {
    if (delta == 0) return;
    purgeExpired();
    final key = '${row.product.key}${row.le ? '|le' : ''}';
    var inv = activeAuto;
    if (delta > 0) {
      final item = inv?.items.where((i) => i.key == key).firstOrNull;
      if (inv == null || item == null) return;
      item.qty -= delta;
      if (item.qty <= 0) inv.items.remove(item);
    } else {
      if (inv == null) {
        final now = _clock();
        inv = Invoice(id: _newId(now), auto: true, createdAt: now, touchedAt: now);
        _list.add(inv);
      }
      final item = inv.items.where((i) => i.key == key).firstOrNull;
      if (item == null) {
        inv.items.add(InvoiceItem(name: invoiceItemName(row), price: row.product.price, qty: -delta, key: key));
      } else {
        item.qty -= delta;
      }
    }
    changed(inv);
  }

  Invoice createManual() {
    final now = _clock();
    final inv = Invoice(id: _newId(now), auto: false, createdAt: now, touchedAt: now);
    _list.add(inv);
    changed(inv);
    return inv;
  }

  /// Gọi sau mỗi lần sửa hoá đơn: lưu lại, tính lại 30 phút cho hoá đơn tự tạo.
  void changed(Invoice inv) {
    inv.touchedAt = _clock();
    _save();
    notifyListeners();
  }

  void remove(Invoice inv) {
    _list.removeWhere((i) => i.id == inv.id);
    _held.remove(inv.id);
    _save();
    notifyListeners();
  }

  /// Đang mở hoá đơn để sửa / xem trước → không tự xoá; [release] khi đóng (tính lại 30 phút từ lúc đó).
  void hold(Invoice inv) => _held.add(inv.id);

  void release(Invoice inv) {
    _held.remove(inv.id);
    if (byId(inv.id) != null) changed(inv);
  }

  String _newId(DateTime now) => '${now.microsecondsSinceEpoch}-${_seq++}';

  Future<void> _save() async {
    try {
      await (await _fileProvider()).writeAsString(jsonEncode([for (final i in _list) i.toJson()]));
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
