import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kho_an_dam_app/main.dart';

void main() {
  testWidgets('app dựng được với giao diện thật, kể cả ở chế độ Debug', (tester) async {
    await tester.pumpWidget(const KhoAnDamApp());

    expect(tester.takeException(), isNull);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Kho ăn dặm'), findsOneWidget);
  });

  testWidgets('giao diện có cỡ chữ đầy đủ sau khi dựng', (tester) async {
    await tester.pumpWidget(const KhoAnDamApp());

    final context = tester.element(find.byType(HomeScreen));
    expect(Theme.of(context).textTheme.bodyMedium?.fontSize, isNotNull);
  });
}
