import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:enthrix_messenger/main.dart';
import 'package:enthrix_messenger/services/settings_service.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    final settingsService = SettingsService();
    await settingsService.initialize();
    await tester.pumpWidget(EnthrixApp(settingsService: settingsService));
    expect(find.text('Enthrix'), findsOneWidget);
  });
}
