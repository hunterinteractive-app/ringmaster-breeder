import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/models/sale_record.dart';
import 'package:ringmaster_breeder/screens/animal_detail_screen.dart';
import 'package:ringmaster_breeder/screens/herd_calendar_screen.dart';
import 'package:ringmaster_breeder/screens/sales_dashboard_screen.dart';
import 'package:ringmaster_breeder/screens/weight_history_screen.dart';
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

  Future<void> mount(
    WidgetTester tester,
    Widget child,
    Size size,
    double scale,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
        home: child,
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final (size, scale) in [
    (const Size(360, 520), 1.0),
    (const Size(320, 568), 1.5),
    (const Size(844, 390), 1.0),
    (const Size(1280, 900), 1.0),
  ]) {
    testWidgets(
      'Animal details adapt at $size / $scale with every action reachable',
      (tester) async {
        var edits = 0;
        var photos = 0;
        await mount(
          tester,
          RingMasterPageShell(
            title: 'Animal Details',
            body: AnimalDetailContent(
              animal: const {
                'name': 'A long animal name for a small phone',
                'tattoo': 'BARN-42',
                'species': 'rabbit',
                'breed': 'Dutch',
                'variety': 'Chocolate',
                'sex': 'Doe',
                'registration_number': 'REG-123',
                'legs': 13,
                'leg_details': 'Best of breed at the county show',
              },
              weightText: '4.25 lb',
              onPhoto: () => photos++,
              parents: const [
                AnimalDetailRow(
                  title: 'Sire',
                  value: 'A long sire name • SIRE-42',
                ),
              ],
              actions: [
                ElevatedButton(
                  onPressed: () => edits++,
                  child: const Text('Edit Animal'),
                ),
                for (final label in [
                  'View Weight History',
                  'Health & Vaccine Records',
                  'Show history & reports',
                  'View Pedigree Tree',
                  'Export Pedigree PDF',
                ])
                  OutlinedButton(onPressed: () {}, child: Text(label)),
              ],
            ),
          ),
          size,
          scale,
        );
        expect(tester.takeException(), isNull);
        final compact = size.width < 600 || size.height < 500;
        if (compact) {
          expect(find.text('Edit Animal').hitTestable(), findsOneWidget);
          await tester.tap(find.byTooltip('Upload photo'));
          expect(photos, 1);
          await tester.tap(find.text('Edit Animal'));
          expect(edits, 1);
          await tester.scrollUntilVisible(
            find.text('Registration & show details'),
            120,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.text('Registration & show details'));
          await tester.pumpAndSettle();
          expect(find.text('REG-123'), findsOneWidget);
        } else {
          expect(find.text('REG-123'), findsOneWidget);
        }
        await tester.scrollUntilVisible(
          find.text('Export Pedigree PDF').hitTestable(),
          150,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 40,
        );
        expect(find.text('Export Pedigree PDF').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Phone weight records are immediately visible and the chart scrolls away',
    (tester) async {
      final weights = List.generate(
        100,
        (i) => <String, dynamic>{
          'id': '$i',
          'weight': 5.0 - i / 100,
          'recorded_at': DateTime(
            2026,
            10,
            17,
          ).subtract(Duration(days: i)).toIso8601String(),
        },
      );
      String? edited;
      await mount(
        tester,
        RingMasterPageShell(
          title: 'Weight History',
          body: WeightHistoryView(
            weights: weights,
            locked: false,
            onEdit: (w) => edited = w['id'],
          ),
        ),
        const Size(320, 480),
        1.5,
      );
      expect(find.text('5.00 lb').hitTestable(), findsOneWidget);
      expect(find.byType(ListTile).evaluate().length, lessThan(20));
      await tester.tap(find.text('5.00 lb'));
      expect(edited, '0');
      await tester.tap(find.text('Growth chart'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('4.95 lb').hitTestable(),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('4.95 lb').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Locked weight records keep their notice and cannot be edited', (
    tester,
  ) async {
    var edits = 0;
    await mount(
      tester,
      RingMasterPageShell(
        title: 'Weight History',
        body: WeightHistoryView(
          weights: const [
            {'id': 'w', 'weight': 4.0, 'recorded_at': '2026-10-17'},
          ],
          locked: true,
          onEdit: (_) => edits++,
        ),
      ),
      const Size(360, 520),
      1,
    );
    expect(find.textContaining('Weights cannot be added'), findsOneWidget);
    await tester.tap(find.text('4.00 lb'));
    expect(edits, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Sales summary expands on a phone and search survives desktop resize',
    (tester) async {
      await mount(
        tester,
        SalesDashboardScreen(
          ownerId: 'owner',
          loadSales: () async => <SaleRecord>[],
        ),
        const Size(320, 568),
        1.5,
      );
      expect(find.text('Sales overview'), findsOneWidget);
      await tester.tap(find.text('Sales overview'));
      await tester.pumpAndSettle();
      expect(find.text('Net received'), findsOneWidget);
      await tester.tap(find.text('Sales overview'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Keep my search');
      tester.view.physicalSize = const Size(1280, 900);
      await tester.pumpAndSettle();
      expect(find.text('Keep my search'), findsOneWidget);
      expect(find.text('Sales overview'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Phone calendar replaces the filter stack with an accessible picker',
    (tester) async {
      await mount(
        tester,
        HerdCalendarScreen(ringId: 'r', loader: () async => []),
        const Size(320, 568),
        1.5,
      );
      final picker = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Health').last);
      await tester.pumpAndSettle();
      expect(find.text('Health'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byTooltip('Next month').hitTestable(),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
