// Màn quét mã vạch (EAN/UPC/Code128) — chạy trên Android và iPhone (mobile_scanner), đèn flash,
// nhập mã tay, công tắc Ghi / Đọc. Mã chỉ được nhận sau khi qua kiểm tra số kiểm tra và
// đọc trùng nhiều khung hình liên tiếp (xem barcode_check.dart).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'barcode_check.dart';
import 'entry_screen.dart';
import 'lookup_screen.dart';

enum ScanMode { write, read }

class ScanResult {
  final String code;
  final ScanMode mode;
  const ScanResult(this.code, this.mode);
}

/// Vòng lặp quét liên tục: quét → ghi / đọc → quay lại camera, tới khi người dùng thoát màn quét.
Future<void> scanLoop(BuildContext context, ScanMode mode) async {
  var m = mode;
  for (;;) {
    if (!context.mounted) return;
    final r = await Navigator.push<ScanResult>(context, MaterialPageRoute(builder: (_) => ScannerScreen(initialMode: m)));
    if (r == null || !context.mounted) return;
    m = r.mode;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => m == ScanMode.write ? EntryScreen(barcode: r.code) : ProductScreen(barcode: r.code)),
    );
  }
}

class ScannerScreen extends StatefulWidget {
  final ScanMode initialMode;
  const ScannerScreen({super.key, this.initialMode = ScanMode.write});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.upcA, BarcodeFormat.upcE, BarcodeFormat.code128],
    // Quét dày hơn mặc định (250 ms) để đủ phiếu xác nhận nhanh.
    detectionTimeoutMs: 100,
  );
  final _voter = ScanVoter();
  int _progress = 0;
  Timer? _idle;
  late ScanMode _mode = widget.initialMode;
  bool _done = false;
  bool _torch = false;

  @override
  void dispose() {
    _idle?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _finish(String code) {
    if (_done) return;
    _done = true;
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);
    Navigator.pop(context, ScanResult(code, _mode));
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final codes = [
      for (final b in capture.barcodes)
        if (b.rawValue?.trim() case final v? when isPlausibleScan(v, b.format)) v,
    ];
    final hit = _voter.add(codes);
    if (hit != null) return _finish(hit);
    if (_voter.progress != _progress) setState(() => _progress = _voter.progress);
    // Camera không còn thấy mã một lúc → bỏ phiếu cũ, khung về màu thường.
    _idle?.cancel();
    _idle = Timer(const Duration(milliseconds: 800), () {
      _voter.reset();
      if (mounted) setState(() => _progress = 0);
    });
  }

  Future<void> _manual() async {
    final c = TextEditingController();
    String? error;
    final code = await showDialog<String>(
      context: context,
      builder: (d) => StatefulBuilder(builder: (d, setDialog) {
        // Dãy 8/12/13 số là EAN/UPC → số cuối phải khớp số kiểm tra, tránh gõ nhầm một số.
        void submit() {
          final v = c.text.replaceAll(RegExp(r'\s+'), '');
          if (RegExp(r'^(\d{8}|\d{12}|\d{13})$').hasMatch(v) && !isValidGtin(v)) {
            return setDialog(() => error = 'Sai số kiểm tra — xem lại từng số');
          }
          Navigator.pop(d, v);
        }

        return AlertDialog(
          title: const Text('Nhập mã vạch'),
          content: TextField(
            controller: c,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(hintText: 'Dãy số dưới mã vạch', errorText: error),
            onChanged: (_) {
              if (error != null) setDialog(() => error = null);
            },
            onSubmitted: (_) => submit(),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Huỷ')),
            FilledButton(onPressed: submit, child: const Text('OK')),
          ],
        );
      }),
    );
    if (code != null && code.isNotEmpty && mounted) _finish(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_mode == ScanMode.write ? 'Quét để GHI' : 'Quét để ĐỌC'),
        actions: [
          IconButton(
            tooltip: 'Đèn',
            icon: Icon(_torch ? Icons.flash_on : Icons.flash_off),
            onPressed: () async {
              await _controller.toggleTorch();
              setState(() => _torch = !_torch);
            },
          ),
        ],
      ),
      body: Stack(children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                error.errorCode == MobileScannerErrorCode.permissionDenied
                    ? 'Chưa có quyền dùng camera. Hãy cấp quyền camera cho app trong Cài đặt.'
                    : 'Không mở được camera: ${error.errorDetails?.message ?? error.errorCode.name}',
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        Center(
          child: Container(
            width: 280,
            height: 160,
            decoration: BoxDecoration(
              // Vàng = đang xác nhận mã (đọc trùng nhiều lần mới nhận).
              border: Border.all(
                color: _progress > 0 ? Colors.amberAccent : (_mode == ScanMode.write ? Colors.greenAccent : Colors.lightBlueAccent),
                width: 3,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: SegmentedButton<ScanMode>(
            style: SegmentedButton.styleFrom(
              backgroundColor: Colors.white70,
              selectedBackgroundColor: Theme.of(context).colorScheme.primaryContainer,
            ),
            segments: const [
              ButtonSegment(value: ScanMode.write, icon: Icon(Icons.add_box), label: Text('Ghi')),
              ButtonSegment(value: ScanMode.read, icon: Icon(Icons.search), label: Text('Đọc')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
        ),
        Positioned(
          bottom: 32,
          left: 24,
          right: 24,
          child: SafeArea(
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              icon: const Icon(Icons.keyboard),
              label: const Text('Nhập mã tay'),
              onPressed: _manual,
            ),
          ),
        ),
      ]),
    );
  }
}
