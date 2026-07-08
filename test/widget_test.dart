import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dlg_q/main.dart';

void main() {
  testWidgets('App launches smoke test with ProviderScope', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: DIYDuolingoApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    // Don't pumpAndSettle — async DB calls will hang in test env
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
