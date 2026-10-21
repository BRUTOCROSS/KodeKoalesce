import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kode_koalesce/screens/settings_screen.dart';

void main() {
  testWidgets('settings opens privacy information', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));

    expect(find.text('Settings & privacy'), findsOneWidget);
    expect(find.text('Privacy information'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);

    await tester.tap(find.text('Privacy information'));
    await tester.pumpAndSettle();

    expect(find.text('Keep the community respectful'), findsOneWidget);
    expect(find.text('Your account and data'), findsOneWidget);
    expect(find.textContaining('false or misleading'), findsOneWidget);
  });
}
