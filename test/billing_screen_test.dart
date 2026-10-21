import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/screens/billing_screen.dart';

Map<String, dynamic> fixture({bool lifetime = false}) => {
  'checkout_enabled': true,
  'subscriptions': [],
  'prices': [],
  'checkouts': [],
  'grants': lifetime
      ? [
          {'id': 'g', 'tier_code': 'PRO', 'active': true},
        ]
      : [],
  'offers': [
    {'id': 'y', 'tier_code': 'PRO', 'interval': 'year', 'amount_cents': 9900},
    {'id': 'm', 'tier_code': 'PRO', 'interval': 'month', 'amount_cents': 1000},
  ],
};
void main() {
  testWidgets(
    'plans display both intervals and require consent before checkout',
    (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: BillingScreen(
            request: (action, args) async {
              calls.add(action);
              return action == 'status' ? fixture() : {};
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('\$99.00/year'), findsOneWidget);
      await tester.tap(find.text('Monthly'));
      await tester.pumpAndSettle();
      expect(find.text('\$10.00/month'), findsOneWidget);
      await tester.ensureVisible(find.text('Choose plan'));
      await tester.tap(find.text('Choose plan'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm membership'), findsOneWidget);
      expect(calls, isNot(contains('checkout')));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(calls, contains('checkout'));
    },
  );
  testWidgets(
    'lifetime access is visible and prevents a new recurring purchase',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: BillingScreen(
            request: (action, args) async =>
                action == 'status' ? fixture(lifetime: true) : {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Professional Breeder · Lifetime'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Choose plan'),
      );
      expect(button.onPressed, isNull);
    },
  );
  testWidgets('billing fits a narrow phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: BillingScreen(
          request: (action, args) async => action == 'status' ? fixture() : {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
