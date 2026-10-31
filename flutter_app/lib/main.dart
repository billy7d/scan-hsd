import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'config.dart';
import 'entry_screen.dart';
import 'inventory_cache.dart';
import 'lookup_screen.dart';
import 'scanner_screen.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cache = InventoryCache.instance;
  await cache.load(); // hiện ngay dữ liệu đã lưu trên máy
  cache.refresh().catchError((_) {}); // rồi tải bản mới từ sheet ở phía sau
  runApp(const KhoAnDamApp());
}

class KhoAnDamApp extends StatelessWidget {
  const KhoAnDamApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    );
    return MaterialApp(
      title: 'Kho ăn dặm',
      debugShowCheckedModeBanner: false,
      // Màu date (đỏ nhạt / vàng) giống sheet nên giữ giao diện sáng.
      themeMode: ThemeMode.light,
      theme: base.copyWith(textTheme: base.textTheme.apply(fontSizeFactor: 1.08)),
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _cache = InventoryCache.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _cache.refreshIfStale().catchError((_) {});
  }

  void _open(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final notConfigured = Config.scriptUrl.contains('DIEN_ID_VAO_DAY');
    return Scaffold(
      appBar: AppBar(title: const Text('Kho ăn dặm'), actions: const [SyncStatus()]),
      body: ListenableBuilder(
        listenable: _cache,
        builder: (context, _) {
          final near = _cache.nearExpiry().length;
          final expired = _cache.expired().length;
          return ListView(padding: const EdgeInsets.all(16), children: [
            if (notConfigured)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Chưa cấu hình URL Apps Script và key trong lib/config.dart — app chưa đọc/ghi được sheet.'),
                ),
              ),
            Row(children: [
              Expanded(
                child: _BigButton(
                  icon: Icons.add_box,
                  label: 'GHI',
                  sub: 'Quét mã nhập hàng',
                  onTap: () => scanLoop(context, ScanMode.write),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BigButton(
                  icon: Icons.qr_code_scanner,
                  label: 'ĐỌC',
                  sub: 'Quét mã tra cứu',
                  color: Theme.of(context).colorScheme.tertiary,
                  onTap: () => scanLoop(context, ScanMode.read),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            InkWell(
              borderRadius: BorderRadius.circular(28),
              onTap: () => _open(const SearchScreen(autofocus: true)),
              child: const IgnorePointer(
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Đọc theo tên sản phẩm (gần đúng)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(28))),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: _CountCard(
                  color: nearColor,
                  count: near,
                  label: 'Sắp hết hạn\n(≤ ${Config.nearExpiryDays} ngày)',
                  onTap: () => _open(const SearchScreen(initialFilter: ExpiryFilter.near)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _CountCard(
                  color: expiredColor,
                  count: expired,
                  label: 'Đã hết hạn\n(còn hàng)',
                  onTap: () => _open(const SearchScreen(initialFilter: ExpiryFilter.expired)),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              icon: const Icon(Icons.edit_note),
              label: const Text('Ghi hàng không mã vạch'),
              onPressed: () => _open(const EntryScreen()),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              icon: const Icon(Icons.list),
              label: Text('Tất cả sản phẩm (${_cache.products.length})'),
              onPressed: () => _open(const SearchScreen()),
            ),
          ]);
        },
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sub;
  final Color? color;
  final VoidCallback onTap;
  const _BigButton({required this.icon, required this.label, required this.sub, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) => FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          minimumSize: const Size.fromHeight(140),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        onPressed: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 46),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          Text(sub, style: const TextStyle(fontSize: 13)),
        ]),
      );
}

class _CountCard extends StatelessWidget {
  final Color color;
  final int count;
  final String label;
  final VoidCallback onTap;
  const _CountCard({required this.color, required this.count, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Card(
        color: color,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$count', style: Theme.of(context).textTheme.headlineMedium),
              Text(label),
            ]),
          ),
        ),
      );
}
