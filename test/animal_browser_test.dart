import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/screens/animal_list_screen.dart';

void main() {
  for (final width in [320.0, 600.0, 800.0, 1200.0]) {
    testWidgets('Lazy cards reach the final row with wrapped text at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? opened;
      final data = List.generate(
        37,
        (i) => <String, dynamic>{
          'id': '$i',
          'tattoo': 'TAG$i',
          'status': 'active',
          'name': 'Animal $i with a long name that wraps across lines',
          'breed': 'A long breed description that wraps across lines',
          'variety': 'A long variety description that wraps across lines',
          'species': 'rabbit',
          'sex': 'Doe',
          'dob': '2025-04-03',
          'sale_status': 'reserved',
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: AnimalBrowser(
              animals: data,
              onAdd: () {},
              onRefresh: () {},
              onOpen: (animal) => opened = animal['id'] as String,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AnimalRecordCard).evaluate().length, lessThan(37));
      final last = find.byWidgetPredicate(
        (widget) => widget is AnimalRecordCard && widget.animal['id'] == '36',
      );
      await tester.scrollUntilVisible(
        last,
        1000,
        maxScrolls: 60,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      final details = find.descendant(
        of: last,
        matching: find.text('View details'),
      );
      await tester.ensureVisible(details);
      await tester.pumpAndSettle();
      await tester.tap(details);
      await tester.pumpAndSettle();
      expect(opened, '36');
      expect(tester.takeException(), isNull);
    });
  }
  for (final width in [320.0, 1200.0]) {
    testWidgets('Animal toolbar filters and switches view at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var added = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimalBrowser(
              animals: const [
                {
                  'id': 'a',
                  'name': 'Cookie',
                  'tattoo': 'ZC2',
                  'species': 'rabbit',
                  'breed': 'Dutch',
                  'variety': 'Chocolate',
                  'sex': 'Doe',
                  'status': 'active',
                  'dob': '2025-04-03',
                },
                {
                  'id': 'b',
                  'tattoo': 'OLD',
                  'species': 'cavy',
                  'breed': 'American',
                  'variety': 'Black',
                  'sex': 'Boar',
                  'status': 'sold',
                  'dob': '2024-01-01',
                },
              ],
              onAdd: () => added = true,
              onRefresh: () {},
              onOpen: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cookie • ZC2'), findsOneWidget);
      expect(find.text('OLD'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), '4/3/2025');
      await tester.pumpAndSettle();
      expect(find.text('Cookie • ZC2'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'missing');
      await tester.pumpAndSettle();
      expect(find.text('No animals match your filters.'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('List view'));
      await tester.pumpAndSettle();
      expect(find.byType(AnimalRecordCard), findsNothing);
      expect(find.text('Cookie • ZC2'), findsOneWidget);
      await tester.tap(find.text('Actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add animal'));
      await tester.pumpAndSettle();
      expect(added, true);
      expect(tester.takeException(), isNull);
    });
  }
}
