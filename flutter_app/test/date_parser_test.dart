import 'package:flutter_test/flutter_test.dart';
import 'package:kho_an_dam_app/date_parser.dart';
import 'package:kho_an_dam_app/models.dart';

void main() {
  test('định dạng ngày', () {
    expect(formatVnDate(DateTime(2027, 3, 5)), '05/03/2027');
    expect(isoDate(DateTime(2027, 3, 5)), '2027-03-05');
    expect(formatIsoVn('2027-03-05'), '05/03/2027');
    expect(parseIso('2027-02-30'), isNull);
  });

  test('định dạng giá', () {
    expect(formatPrice(140000), '140.000 ₫');
    expect(formatPrice(0), '0 ₫');
    expect(formatPrice(1250000), '1.250.000 ₫');
  });

  test('tô màu: đỏ = hết hạn, vàng = còn ≤ 90 ngày', () {
    final now = DateTime(2026, 10, 23);
    expect(expiryStatus('2026-10-22', now), ExpiryStatus.expired);
    expect(expiryStatus('2026-10-23', now), ExpiryStatus.near);
    expect(expiryStatus('2027-01-21', now), ExpiryStatus.near); // còn 90 ngày
    expect(expiryStatus('2027-01-22', now), ExpiryStatus.ok); // còn 91 ngày
  });

  test('mã vạch: UPC 12 số = EAN-13 có số 0 đầu; hàng không mã khoá theo tên', () {
    expect(productKey('012345678905', 'x'), productKey('0012345678905', 'y'));
    expect(productKey('', ' Bánh  gạo '), productKey('', 'bánh gạo'));
  });
}
