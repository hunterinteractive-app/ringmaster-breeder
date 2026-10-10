import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/screens/animal_list_screen.dart';

void main() {
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
