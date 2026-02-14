import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enthrix_messenger/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const EnthrixApp());
    expect(find.text('Enthrix'), findsOneWidget);
  });
}
