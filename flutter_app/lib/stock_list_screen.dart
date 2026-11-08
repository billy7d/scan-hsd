// "Dsach tồn kho": bảng 3 cột STT, tên sản phẩm, số lượng — hết hàng đứng đầu, rồi ít đến nhiều.

import 'package:flutter/material.dart';

import 'inventory_cache.dart';
import 'ui.dart';

class StockListScreen extends StatefulWidget {
  final InventoryCache? cache;
  const StockListScreen({super.key, this.cache});

  @override
  State<StockListScreen> createState() => _StockListScreenState();
}

class _StockListScreenState extends State<StockListScreen> {
  late final InventoryCache _cache = widget.cache ?? InventoryCache.instance;

  @override
  void initState() {
    super.initState();
    // Hiện ngay bản sao trên máy, rồi tải số lượng mới nhất từ sheet. Đợi dựng xong khung hình đầu
    // vì refresh() báo cập nhật ngay cho các màn đang nghe, không được làm việc đó giữa lúc dựng.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _cache.refresh().catchError((_) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dsach tồn kho'), actions: const [SyncStatus()]),
      body: ListenableBuilder(
        listenable: _cache,
        builder: (context, _) {
          final lines = _cache.stockList();
          return Column(children: [
            ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const _StockRow(stt: 'STT', name: 'Tên sản phẩm', qty: 'Số lượng', header: true),
            ),
            const Divider(height: 1),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _cache.refresh().catchError((Object e) {
                  if (context.mounted) showSnack(context, e.toString(), error: true);
                }),
                child: lines.isEmpty
                    ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                        const SizedBox(height: 48),
                        Center(child: Text(_cache.refreshing ? 'Đang tải từ sheet…' : 'Chưa có sản phẩm')),
                      ])
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: lines.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) => _StockRow(stt: '${i + 1}', name: lines[i].label, qty: '${lines[i].qty}'),
                      ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _StockRow extends StatelessWidget {
  final String stt;
  final String name;
  final String qty;
  final bool header;
  const _StockRow({required this.stt, required this.name, required this.qty, this.header = false});

  @override
  Widget build(BuildContext context) {
    final style = header ? const TextStyle(fontWeight: FontWeight.w700) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 44, child: Text(stt, style: style)),
        const SizedBox(width: 8),
        Expanded(child: Text(name, style: style)),
        const SizedBox(width: 8),
        SizedBox(width: 76, child: Text(qty, style: style, textAlign: TextAlign.right)),
      ]),
    );
  }
}
