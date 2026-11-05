import 'package:flutter_test/flutter_test.dart';
import 'package:kho_an_dam_app/date_parser.dart';
import 'package:kho_an_dam_app/models.dart';
import 'package:kho_an_dam_app/ui.dart';

TextEditingValue type(TextEditingValue old, String text) =>
    PriceInputFormatter().formatEditUpdate(old, TextEditingValue(text: text));

void main() {
  test('priceValue: số và chữ có dấu phân cách → đúng giá', () {
    expect(priceValue(140000), 140000);
    expect(priceValue(140000.0), 140000);
    expect(priceValue('140000'), 140000);
    expect(priceValue('140.000'), 140000);
    expect(priceValue('140,000 ₫'), 140000);
    expect(priceValue('1.250.000đ'), 1250000);
    expect(priceValue(0), 0);
  });

  test('priceValue: giá rác trong sheet (ID cũ, số quá lớn, số lẻ) → null', () {
    for (final v in ['9a0649ba', '26012e58', 59970494, 2.6012e58, -1, 1400.5, '14.00', '', null]) {
      expect(priceValue(v), isNull, reason: '$v');
    }
  });

  test('snapshot có ô giá rác → app hiện 0, không phải 906.498 ₫', () {
    final r = InventoryRow.fromList(['b8a39762', '9340156091974', 'Rf.G Váng sữa', '2027-08-29', 6, '9a0649ba']);
    expect(r.product.price, 0);
    expect(InventoryRow.fromList(['x', '1', 'A', '2027-01-01', 1, 59970494]).product.price, 0);
    expect(InventoryRow.fromList(['x', '1', 'A', '2027-01-01', 1, 90000]).product.price, 90000);
    expect(Product.fromJson({'name': 'A', 'price': 2.6012e58}).price, 0);
  });

  test('ô nhập giá: tự thêm dấu chấm, parsePrice ra đúng số gửi lên sheet', () {
    var v = const TextEditingValue();
    for (final ch in '140000'.split('')) {
      v = type(v, v.text + ch);
    }
    expect(v.text, '140.000');
    expect(parsePrice(v.text), 140000);
    expect(formatPrice(parsePrice(v.text)), '140.000 ₫');
  });

  test('ô nhập giá: không cho vượt 10.000.000 ₫, bỏ số 0 đầu, xoá hết → trống', () {
    final ten = type(const TextEditingValue(), '10000000');
    expect(ten.text, '10.000.000');
    expect(type(ten, '${ten.text}0').text, '10.000.000');
    expect(type(const TextEditingValue(), '0085000').text, '85.000');
    expect(type(const TextEditingValue(text: '5'), '').text, '');
    expect(parsePrice(''), 0);
  });
}
