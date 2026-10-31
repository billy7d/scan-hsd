import 'package:flutter_test/flutter_test.dart';
import 'package:kho_an_dam_app/barcode_check.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

void main() {
  test('số kiểm tra EAN-13: mã thật đúng, mã iPhone đọc lệch số đầu bị loại', () {
    expect(isValidGtin('5000157065759'), isTrue);
    expect(isValidGtin('9000157065759'), isFalse);
    expect(isPlausibleScan('5000157065759', BarcodeFormat.ean13), isTrue);
    expect(isPlausibleScan('9000157065759', BarcodeFormat.ean13), isFalse);
  });

  test('EAN-8, UPC-A (12 và 13 số)', () {
    expect(isPlausibleScan('96385074', BarcodeFormat.ean8), isTrue);
    expect(isPlausibleScan('96385075', BarcodeFormat.ean8), isFalse);
    expect(isPlausibleScan('012345678905', BarcodeFormat.upcA), isTrue);
    expect(isPlausibleScan('0012345678905', BarcodeFormat.ean13), isTrue);
    expect(isPlausibleScan('012345678906', BarcodeFormat.upcA), isFalse);
  });

  test('UPC-E mở rộng sang UPC-A để kiểm tra', () {
    expect(upcEToUpcA('04252614'), '042100005264');
    expect(isPlausibleScan('04252614', BarcodeFormat.upcE), isTrue);
    expect(isPlausibleScan('04252615', BarcodeFormat.upcE), isFalse);
  });

  test('Code128 không có số kiểm tra trong dữ liệu → nhận', () {
    expect(isPlausibleScan('KHO-001', BarcodeFormat.code128), isTrue);
    expect(isPlausibleScan('', BarcodeFormat.code128), isFalse);
  });

  test('chỉ nhận khi 3 khung hình liên tiếp cùng mã', () {
    final v = ScanVoter();
    expect(v.add(['5000157065759']), isNull);
    expect(v.add(['5000157065759']), isNull);
    expect(v.add(['5000157065759']), '5000157065759');
  });

  test('một khung hình đọc khác mã → đếm lại; khung hình rỗng (mã sai bị lọc) không xoá phiếu', () {
    final v = ScanVoter();
    v.add(['5000157065759']);
    v.add(['5000157065759']);
    expect(v.add(['5000157065742']), isNull);
    expect(v.progress, 1);
    expect(v.add([]), isNull);
    expect(v.add(['5000157065742']), isNull);
    expect(v.add(['5000157065742']), '5000157065742');
  });
}
