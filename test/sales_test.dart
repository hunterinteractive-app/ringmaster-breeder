import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/models/sale_record.dart';
import 'package:ringmaster_breeder/widgets/bulk_sale_dialog.dart';
import 'package:ringmaster_breeder/screens/sales_dashboard_screen.dart';

void main() {
  test('historical prices do not fabricate unpaid balances or receipts', () {
    const sale = SaleRecord({
      'id': 'historic',
      'status': 'sold',
      'sale_cents': 300,
      'import_source': 'global_pedigree',
      'payment_history_complete': false,
    });
    expect(sale.price, 300);
    expect(sale.balance, isNull);
    expect(sale.paymentStatus, 'Payment history not recorded');
    expect(sale.imported, isTrue);
    expect(sale.paid, 0);
  });
  test(
    'money parsing is exact and rejects extra precision or negative amounts',
    () {
      expect(parseSaleMoney('19.99'), 1999);
      expect(parseSaleMoney('0.01'), 1);
      expect(parseSaleMoney('12.3'), 1230);
      expect(parseSaleMoney(''), isNull);
      for (final v in ['1.001', '-1', 'NaN', 'Infinity', '1e4', '1,000']) {
        expect(() => parseSaleMoney(v), throwsFormatException);
      }
    },
  );
  test(
    'deposits count once toward balance and refunds reduce money received',
    () {
      final sale = SaleRecord(
        {
          'id': 's',
          'status': 'sold',
          'asking_cents': 15000,
          'sale_cents': 12000,
        },
        [
          {'kind': 'deposit', 'amount_cents': 3000},
          {'kind': 'payment', 'amount_cents': 5000},
          {'kind': 'refund', 'amount_cents': 1000},
        ],
      );
      expect(sale.paid, 7000);
      expect(sale.balance, 5000);
      expect(sale.deposits, 3000);
      expect(sale.paymentStatus, 'Part paid');
    },
  );
  test('unpriced and zero-price animals are distinct', () {
    expect(const SaleRecord({'id': 'a', 'status': 'for_sale'}).balance, isNull);
    expect(
      const SaleRecord({'id': 'a', 'status': 'for_sale'}).paymentStatus,
      'Price not set',
    );
    expect(
      const SaleRecord({
        'id': 'a',
        'status': 'for_sale',
        'asking_cents': 0,
      }).paymentStatus,
      'Paid in full',
    );
  });
  for (final width in [360.0, 1200.0]) {
    testWidgets('bulk sale selects eligible animals at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      List<Map<String, dynamic>>? written;
      int? price;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<int>(
                  context: context,
                  builder: (_) => BulkSaleDialog(
                    animals: const [
                      {
                        'id': 'a',
                        'ring_id': 'r',
                        'name': 'Eligible',
                        'tattoo': 'ONE',
                        'breed': 'Dutch',
                        'status': 'active',
                      },
                      {
                        'id': 'b',
                        'ring_id': 'r',
                        'name': 'Sold animal',
                        'status': 'sold',
                      },
                      {
                        'id': 'c',
                        'ring_id': 'r',
                        'name': 'Listed animal',
                        'status': 'active',
                        'sale_status': 'for_sale',
                      },
                    ],
                    writer: (rows, cents) async {
                      written = rows;
                      price = cents;
                    },
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Eligible'), findsOneWidget);
      expect(find.text('Sold animal'), findsNothing);
      expect(find.text('Listed animal'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextField, 'Asking price per animal (USD)'),
        '125.50',
      );
      await tester.tap(find.text('Select all matching animals'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('List 1 animals'));
      await tester.pumpAndSettle();
      expect(written?.single['id'], 'a');
      expect(price, 12550);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('bulk listing failure preserves selection for retry', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BulkSaleDialog(
            animals: const [
              {
                'id': 'a',
                'ring_id': 'r',
                'name': 'Eligible',
                'status': 'active',
              },
            ],
            writer: (_, __) async {
              throw StateError('Please retry');
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Select all matching animals'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('List 1 animals'));
    await tester.pumpAndSettle();
    expect(find.text('Please retry'), findsOneWidget);
    expect(find.text('List 1 animals'), findsOneWidget);
  });
  for (final width in [360.0, 1200.0]) {
    testWidgets('dashboard shows financial totals without overflow at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sale = SaleRecord(
        {
          'id': 's',
          'animal_id': 'a',
          'animal_name': 'Midnight - ZH24',
          'status': 'reserved',
          'buyer_name': 'Jane Buyer',
          'asking_cents': 15000,
          'sale_cents': 12000,
          'created_at': '2026-10-13T14:00:00Z',
        },
        [
          {'kind': 'deposit', 'amount_cents': 3000},
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SalesDashboardScreen(
            ownerId: 'owner',
            loadSales: () async => [sale],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Midnight - ZH24'), findsOneWidget);
      expect(find.text('Buyer: Jane Buyer'), findsOneWidget);
      expect(find.text('Balance: \$90.00'), findsOneWidget);
      expect(find.text('Net paid: \$30.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
