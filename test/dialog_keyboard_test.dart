import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/models/sale_record.dart';
import 'package:ringmaster_breeder/screens/sales_dashboard_screen.dart';
import 'package:ringmaster_breeder/theme/app_theme.dart';
import 'package:ringmaster_breeder/widgets/app_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('BreederSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    await font.load();
  });

  for (final payment in [false, true]) {
    testWidgets(
      '${payment ? 'Payment' : 'Sale'} fields have usable height with Android autofill and keyboard',
      (tester) async {
        tester.view.physicalSize = const Size(360, 512);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        const sale = SaleRecord({
          'id': 'test-sale',
          'animal_id': 'test-animal',
          'animal_name': 'Willow',
          'status': 'for_sale',
          'asking_cents': 10000,
          'buyer_name': '',
          'buyer_email': '',
          'buyer_phone': '',
          'buyer_address': '',
          'notes': '',
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light.copyWith(
              textTheme: AppTheme.light.textTheme.apply(
                fontFamily: 'BreederSans',
              ),
            ),
            builder: (_, child) => AppShell(child: child!),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => payment
                        ? const SalePaymentDialog(sale: sale)
                        : const SaleEditDialog(sale: sale),
                  ),
                  child: const Text('Open form'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open form'));
        await tester.pumpAndSettle();
        Finder field(String label) => find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == label,
        );
        final label = payment ? 'Method, e.g. cash or check' : 'Buyer name';
        await tester.ensureVisible(field(label));
        await tester.tap(field(label));
        await tester.enterText(field(label), 'Keep my draft');
        tester.view.viewInsets = const FakeViewPadding(bottom: 313);
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(
          tester.element(field(label)),
          alignment: 0.5,
        );
        await tester.pumpAndSettle();
        // Checking only against the screen would miss a field clipped to a thin
        // strip between a fixed dialog heading and its actions.
        final viewport = tester.getRect(
          find.byType(SingleChildScrollView).first,
        );
        final input = tester.getRect(field(label));
        expect(viewport.height, greaterThanOrEqualTo(input.height));
        expect(input.top, greaterThanOrEqualTo(viewport.top));
        expect(input.bottom, lessThanOrEqualTo(viewport.bottom + 1));
        final save = find.text(payment ? 'Save record' : 'Save sale');
        expect(tester.getRect(save).bottom, lessThanOrEqualTo(199));
        final controller = tester.widget<TextField>(field(label)).controller!;
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        expect(controller.text, 'Keep my draft');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
