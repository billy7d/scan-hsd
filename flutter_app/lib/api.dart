// Gọi Google Apps Script Web App (apps_script/Code.gs).

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'models.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

/// Date đã bị người khác sửa (`conflict`) hoặc không còn (`notFound`) — app cần tải lại.
class ConflictException extends ApiException {
  final String status;
  ConflictException(this.status) : super('Dữ liệu vừa thay đổi, hãy kiểm tra lại');
}

/// Kết quả lệnh ghi: created | updated | duplicate | merged | deleted | notFound …
class WriteResult {
  final String status;
  final String? id;
  final String? hsd;
  final int? currentQty;
  final int? newQty;
  final int? rowsChanged;

  WriteResult.fromJson(Map<String, dynamic> j)
      : status = j['status']?.toString() ?? '',
        id = j['id']?.toString(),
        hsd = j['hsd']?.toString(),
        currentQty = (j['currentQty'] as num?)?.toInt(),
        newQty = (j['newQty'] as num?)?.toInt(),
        rowsChanged = (j['rowsChanged'] as num?)?.toInt();
}

/// Một date cần ghi.
class NewLot {
  final String hsd; // yyyy-MM-dd
  final int qty;
  const NewLot(this.hsd, this.qty);
  Map<String, dynamic> toJson() => {'hsd': hsd, 'qty': qty};
}

class Api {
  static http.Client client = http.Client();
  static const _timeout = Duration(seconds: 30);

  static Uri get _base => Uri.parse(Config.scriptUrl);

  static Future<Map<String, dynamic>> _get(Map<String, String> params) async {
    final uri = _base.replace(queryParameters: {...params, 'key': Config.apiKey});
    return _decode(await _send(() => client.get(uri)));
  }

  /// Apps Script trả 302 sau POST; phải tự theo redirect bằng GET để lấy kết quả.
  static Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final res = await _send(() async {
      final req = http.Request('POST', _base)
        ..followRedirects = false
        ..headers['Content-Type'] = 'text/plain;charset=utf-8'
        ..body = jsonEncode({...body, 'key': Config.apiKey});
      final first = await http.Response.fromStream(await client.send(req));
      final location = first.headers['location'];
      if ((first.statusCode == 302 || first.statusCode == 303) && location != null) {
        return client.get(Uri.parse(location));
      }
      return first;
    });
    return _decode(res);
  }

  static Future<http.Response> _send(Future<http.Response> Function() fn) async {
    if (Config.scriptUrl.contains('DIEN_ID_VAO_DAY')) {
      throw ApiException('Chưa cấu hình URL Apps Script trong lib/config.dart');
    }
    try {
      return await fn().timeout(_timeout);
    } catch (_) {
      throw ApiException('Không kết nối được Google Sheet — kiểm tra mạng rồi thử lại');
    }
  }

  static Map<String, dynamic> _decode(http.Response res) {
    if (res.statusCode != 200) throw ApiException('Lỗi máy chủ (${res.statusCode})');
    final Map<String, dynamic> j;
    try {
      j = Map<String, dynamic>.from(jsonDecode(utf8.decode(res.bodyBytes)) as Map);
    } catch (_) {
      throw ApiException('Phản hồi không hợp lệ — kiểm tra URL và quyền truy cập Web App');
    }
    if (j['ok'] != true) throw ApiException(j['error']?.toString() ?? 'Lỗi không rõ');
    return j;
  }

  static Map<String, dynamic> _checked(Map<String, dynamic> j) {
    final s = j['status'];
    if (s == 'conflict' || s == 'notFound') throw ConflictException(s as String);
    return j;
  }

  // ------------------------------------------------------------ Đọc

  static Future<LookupResult> lookup(String barcode) async {
    final j = await _get({'action': 'lookup', 'barcode': barcode});
    if (j['found'] != true) return const LookupResult(found: false);
    return LookupResult(
      found: true,
      product: Product.fromJson(Map<String, dynamic>.from(j['product'] as Map)),
      lots: [for (final l in j['lots'] as List) Lot.fromJson(Map<String, dynamic>.from(l as Map))],
    );
  }

  static Future<List<InventoryRow>> snapshot() async {
    final j = await _get({'action': 'snapshot'});
    return [for (final r in j['rows'] as List) InventoryRow.fromList(r as List)];
  }

  // ------------------------------------------------------------ Ghi

  /// Ghi một sản phẩm với nhiều date trong một lệnh. Kết quả theo thứ tự `lots`.
  static Future<List<WriteResult>> add({
    required String barcode,
    required String name,
    required int price,
    required List<NewLot> lots,
    bool confirmMerge = false,
  }) async {
    final j = await _post({
      'action': 'add', 'barcode': barcode, 'name': name, 'price': price,
      'lots': [for (final l in lots) l.toJson()], 'confirmMerge': confirmMerge,
    });
    return [for (final r in j['results'] as List) WriteResult.fromJson(Map<String, dynamic>.from(r as Map))];
  }

  static Future<WriteResult> adjust(String id, Expect expect, int delta) async => WriteResult.fromJson(
      _checked(await _post({'action': 'adjust', 'id': id, 'expect': expect.toJson(), 'delta': delta})));

  static Future<WriteResult> updateLot(String id, Expect expect, {String? hsd, int? qty, bool confirmMerge = false}) async =>
      WriteResult.fromJson(_checked(await _post({
        'action': 'updateLot', 'id': id, 'expect': expect.toJson(),
        'hsd': ?hsd, 'qty': ?qty, 'confirmMerge': confirmMerge,
      })));

  static Future<WriteResult> deleteLot(String id, Expect expect) async =>
      WriteResult.fromJson(_checked(await _post({'action': 'deleteLot', 'id': id, 'expect': expect.toJson()})));

  /// Sửa tên / giá cho mọi date. Có mã vạch thì theo mã; không có thì theo tên cũ.
  static Future<WriteResult> updateProduct(Product old, Product updated) async => WriteResult.fromJson(await _post({
        'action': 'updateProduct', 'barcode': old.barcode, 'oldName': old.name,
        'name': updated.name, 'price': updated.price,
      }));
}
