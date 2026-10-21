import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/screens/global_billing_settings_screen.dart';

void main() {
  testWidgets('admin schedules a future price with automatic notices', (
    tester,
  ) async {
    final calls = <Map<String, dynamic>>[];
    final status = <String, dynamic>{
      'offers': [
        {'tier_code': 'HOBBY', 'interval': 'year', 'amount_cents': 4900},
      ],
      'rules': <dynamic>[],
      'changes': <dynamic>[],
      'notices': <dynamic>[],
    };
    await tester.pumpWidget(
      MaterialApp(
        home: GlobalBillingSettingsScreen(
          request: (action, args) async {
            calls.add({'action': action, ...args});
            return action == 'admin-global-status'
                ? status
                : {'scheduled': true};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Current price: \$49.00/year USD'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('In 60 days'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('In 60 days'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'New recurring price (USD)'),
      '59.00',
    );
    await tester.ensureVisible(
      find.text('Schedule price change & notify members'),
    );
    await tester.tap(find.text('Schedule price change & notify members'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('old price, new price and exact renewal date'),
      findsOneWidget,
    );
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    final saved = calls.singleWhere(
      (c) => c['action'] == 'admin-publish-price',
    );
    expect(saved['amount_cents'], 5900);
    expect(saved['tier'], 'HOBBY');
    expect(saved['interval'], 'year');
    final days = DateTime.parse(
      saved['starts_at'] as String,
    ).difference(DateTime.now()).inDays;
    expect(days, inInclusiveRange(59, 60));
    expect(saved.containsKey('confirm_notice'), isFalse);
  });
}
