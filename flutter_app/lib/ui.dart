// Thành phần giao diện dùng chung.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'date_parser.dart';
import 'inventory_cache.dart';
import 'models.dart';

const expiredColor = Color(0xFFF4C7C3); // giống màu trong sheet
const nearColor = Color(0xFFFCE8B2);

Color? expiryColor(ExpiryStatus s) => switch (s) {
      ExpiryStatus.expired => expiredColor,
      ExpiryStatus.near => nearColor,
      _ => null,
    };

/// "còn 12 ngày" / "đã hết hạn 3 ngày" / "hết hạn hôm nay".
String daysLeftText(String hsd, DateTime now) {
  final n = daysLeft(hsd, now);
  if (n == null) return '';
  if (n < 0) return 'đã hết hạn ${-n} ngày';
  if (n == 0) return 'hết hạn hôm nay';
  return 'còn $n ngày';
}

String hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

void showSnack(BuildContext context, String msg, {bool error = false}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    behavior: SnackBarBehavior.floating,
  ));
}

Future<bool> confirmDialog(BuildContext context, String title, String message,
        {String confirm = 'Đồng ý', String cancel = 'Huỷ'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(cancel)),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(confirm)),
        ],
      ),
    ) ??
    false;

Future<T> runWithProgress<T>(BuildContext context, String label, Future<T> Function() fn) async {
  final nav = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [const CircularProgressIndicator(), const SizedBox(width: 20), Expanded(child: Text(label))]),
      ),
    ),
  );
  try {
    return await fn();
  } finally {
    nav.pop();
  }
}

Future<DateTime?> pickHsd(BuildContext context, DateTime? initial) {
  final now = DateTime.now();
  return showDatePicker(
    context: context,
    initialDate: initial ?? now,
    firstDate: DateTime(now.year - 3),
    lastDate: DateTime(now.year + 10, 12, 31),
    helpText: 'Chọn date (hạn sử dụng)',
    locale: const Locale('vi'),
  );
}

Future<int?> askNumber(BuildContext context, String title, int initial) {
  final c = TextEditingController(text: '$initial')..selection = TextSelection(baseOffset: 0, extentOffset: '$initial'.length);
  return showDialog<int>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(fontSize: 28),
        textAlign: TextAlign.center,
        onSubmitted: (v) => Navigator.pop(d, int.tryParse(v)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Huỷ')),
        FilledButton(onPressed: () => Navigator.pop(d, int.tryParse(c.text)), child: const Text('OK')),
      ],
    ),
  );
}

/// Nút − số + to, bấm được bằng ngón cái.
class QtyStepper extends StatelessWidget {
  final int value;
  final int min;
  final ValueChanged<int> onChanged;
  const QtyStepper({super.key, required this.value, required this.onChanged, this.min = 1});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton.filledTonal(iconSize: 26, onPressed: value > min ? () => onChanged(value - 1) : null, icon: const Icon(Icons.remove)),
        InkWell(
          onTap: () async {
            final v = await askNumber(context, 'Số lượng', value);
            if (v != null && v >= min) onChanged(v);
          },
          child: Container(
            width: 56,
            alignment: Alignment.center,
            child: Text('$value', style: Theme.of(context).textTheme.headlineSmall),
          ),
        ),
        IconButton.filledTonal(iconSize: 26, onPressed: () => onChanged(value + 1), icon: const Icon(Icons.add)),
      ]);
}

/// Ô nhập giá: chỉ số, tự thêm dấu chấm hàng nghìn khi gõ (140000 → 140.000); vượt [maxPrice] → không nhận phím đó.
class PriceInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '').replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (digits.isEmpty) return const TextEditingValue(text: '');
    final n = int.tryParse(digits);
    if (n == null || n > maxPrice) return oldValue;
    final text = formatPrice(n).replaceAll(' ₫', '');
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

int parsePrice(String s) => priceValue(s) ?? 0;

/// "Dữ liệu lúc 14:05" + nút tải lại.
class SyncStatus extends StatelessWidget {
  const SyncStatus({super.key});

  @override
  Widget build(BuildContext context) {
    final cache = InventoryCache.instance;
    return ListenableBuilder(
      listenable: cache,
      builder: (context, _) {
        final at = cache.fetchedAt;
        return Row(mainAxisSize: MainAxisSize.min, children: [
          if (cache.lastError != null && !cache.refreshing)
            Tooltip(message: cache.lastError!, child: const Icon(Icons.cloud_off, size: 18)),
          const SizedBox(width: 4),
          Text(at == null ? 'Chưa có dữ liệu' : 'Dữ liệu lúc ${hhmm(at)}', style: Theme.of(context).textTheme.bodySmall),
          cache.refreshing
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(
                  tooltip: 'Tải lại từ sheet',
                  icon: const Icon(Icons.refresh),
                  onPressed: () => cache.refresh().catchError((Object e) {
                    if (context.mounted) showSnack(context, e.toString(), error: true);
                  }),
                ),
        ]);
      },
    );
  }
}

/// Bảng chọn sản phẩm có sẵn, có ô tìm gần đúng.
Future<ProductSummary?> pickProduct(BuildContext context, List<ProductSummary> items, {String title = 'Chọn sản phẩm'}) =>
    showModalBottomSheet<ProductSummary>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => _ProductPicker(items: items, title: title),
    );

class _ProductPicker extends StatefulWidget {
  final List<ProductSummary> items;
  final String title;
  const _ProductPicker({required this.items, required this.title});
  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = _q.trim().isEmpty ? widget.items : widget.items.where((p) => nameMatchScore(_q, p.product.name) > 0).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: Text(widget.title, style: Theme.of(context).textTheme.titleLarge)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Gõ tên (không cần dấu)'),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('Không có sản phẩm phù hợp'))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (c, i) => ListTile(
                      title: Text(list[i].product.name),
                      subtitle: Text(list[i].summaryText),
                      onTap: () => Navigator.pop(context, list[i]),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }
}
