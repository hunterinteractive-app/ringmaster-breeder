import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/widgets/account_billing_overview.dart';

Map<String, dynamic> details() => {
  'access': {
    'name': 'Professional Breeder',
    'source': 'stripe_subscription',
    'expires_at': '2027-01-01T12:00:00Z',
  },
  'subscriptions': [
    {
      'id': 's',
      'plan': {
        'name': 'Professional Breeder',
        'amount_cents': 9900,
        'currency': 'usd',
        'interval': 'year',
      },
      'status': 'active',
      'verified_live': true,
      'period_end': '2027-01-01T12:00:00Z',
      'paid_through': '2027-01-01T12:00:00Z',
      'cancel_at_period_end': false,
      'price_locked': false,
      'scheduled_plan': {
        'name': 'Top Tier',
        'amount_cents': 17900,
        'currency': 'usd',
        'interval': 'year',
        'effective_at': '2027-01-01T12:00:00Z',
      },
    },
  ],
  'transactions': [
    {
      'id': 'ch_example',
      'amount_cents': 9900,
      'refunded_cents': 2500,
      'currency': 'usd',
      'status': 'partially_refunded',
      'created_at': '2026-01-01T12:00:00Z',
      'description': 'Membership payment',
    },
  ],
  'invoices': [
    {
      'id': 'in_example',
      'number': 'RMB-1',
      'total_cents': 9900,
      'paid_cents': 9900,
      'remaining_cents': 0,
      'currency': 'usd',
      'status': 'paid',
      'created_at': '2026-01-01T12:00:00Z',
    },
  ],
  'transactions_available': true,
  'invoices_available': true,
  'warnings': [],
  'membership_activity': [],
};
void main() {
  testWidgets(
    'account overview shows current and scheduled renewal plans with actual refunds',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AccountBillingOverview(data: details()),
            ),
          ),
        ),
      );
      expect(find.text('Scheduled change: Top Tier'), findsOneWidget);
      expect(
        find.textContaining('Plan price: \$99.00 USD/year'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Transaction history'));
      await tester.tap(find.text('Transaction history'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Partially refunded'), findsOneWidget);
      expect(find.text('Refunded: \$25.00 USD'), findsOneWidget);
    },
  );
  testWidgets('a lifetime grant does not imply a paid transaction or renewal', (
    tester,
  ) async {
    final data = details()
      ..['access'] = {
        'name': 'Professional Breeder',
        'source': 'manual_lifetime',
      }
      ..['subscriptions'] = []
      ..['transactions'] = [];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AccountBillingOverview(data: data),
          ),
        ),
      ),
    );
    expect(
      find.textContaining('no membership renewal required'),
      findsOneWidget,
    );
    expect(
      find.text('No Stripe subscription recorded for this account.'),
      findsOneWidget,
    );
  });
  testWidgets(
    'narrow phone layout supports expanded payment and invoice history',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AccountBillingOverview(data: details()),
            ),
          ),
        ),
      );
      await tester.ensureVisible(find.text('Transaction history'));
      await tester.tap(find.text('Transaction history'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Invoices'));
      await tester.tap(find.text('Invoices'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
