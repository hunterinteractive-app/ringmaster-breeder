import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/models/sale_record.dart';
import 'package:ringmaster_breeder/screens/sales_dashboard_screen.dart';
import 'package:ringmaster_breeder/theme/app_theme.dart';
import 'package:ringmaster_breeder/widgets/app_shell.dart';
import 'package:ringmaster_breeder/widgets/ringmaster_page_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('BreederSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    await font.load();
  });

  Future<void> mount(WidgetTester tester, Widget home, double scale) async {
    tester.view.physicalSize = const Size(592, 280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(
          textTheme: AppTheme.light.textTheme.apply(fontFamily: 'BreederSans'),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: AppShell(child: child!),
        ),
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fits(WidgetTester tester, Finder target) async {
    await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
    await tester.pumpAndSettle();
    final rect = tester.getRect(target);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(80));
    expect(target.hitTestable(), findsOneWidget);
  }

  for (final scale in [1.0, 1.3]) {
    testWidgets(
      'Landscape form fits 80px with text scale $scale and retains draft',
      (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await mount(
          tester,
          RingMasterPageShell(
            title: 'Edit Animal',
            body: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 200),
                FilledButton(
                  onPressed: () {},
                  child: const Text('Save changes'),
                ),
              ],
            ),
          ),
          scale,
        );
        await tester.tap(find.byType(TextField));
        await tester.enterText(find.byType(TextField), 'Retain this draft');
        tester.view.viewInsets = const FakeViewPadding(bottom: 200);
        await tester.pumpAndSettle();
        await fits(tester, find.byType(TextField));
        expect(find.byTooltip('Page menu').hitTestable(), findsNothing);
        final save = find.widgetWithText(FilledButton, 'Save changes');
        await tester.scrollUntilVisible(
          save,
          50,
          scrollable: find.byType(Scrollable).first,
        );
        await fits(tester, save);
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        expect(controller.text, 'Retain this draft');
        expect(find.byTooltip('Page menu').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    for (final payment in [false, true]) {
      testWidgets(
        'Landscape ${payment ? 'payment' : 'sale'} fields/actions fit with text scale $scale',
        (tester) async {
          const sale = SaleRecord({
            'id': 'sample',
            'animal_id': 'sample-animal',
            'status': 'for_sale',
            'animal_name': 'Willow',
          });
          await mount(
            tester,
            Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => payment
                        ? const SalePaymentDialog(sale: sale)
                        : const SaleEditDialog(sale: sale),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
            scale,
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          final label = payment ? 'Notes' : 'Private notes';
          final field = find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == label,
          );
          await tester.ensureVisible(field);
          await tester.tap(field);
          await tester.enterText(field, 'Keep the notes');
          final controller = tester.widget<TextField>(field).controller!;
          tester.view.viewInsets = const FakeViewPadding(bottom: 200);
          await tester.pumpAndSettle();
          await fits(tester, field);
          final viewport = tester.getRect(
            find.byType(SingleChildScrollView).first,
          );
          expect(
            tester.getRect(field).height,
            lessThanOrEqualTo(viewport.height),
          );
          await fits(
            tester,
            find.widgetWithText(
              FilledButton,
              payment ? 'Save record' : 'Save sale',
            ),
          );
          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
          expect(
            identical(tester.widget<TextField>(field).controller, controller),
            isTrue,
          );
          expect(controller.text, 'Keep the notes');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
