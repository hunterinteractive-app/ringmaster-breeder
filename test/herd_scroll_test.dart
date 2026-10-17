import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/screens/animal_list_screen.dart';
import 'package:ringmaster_breeder/theme/app_theme.dart';
import 'package:ringmaster_breeder/widgets/app_shell.dart';
import 'package:ringmaster_breeder/widgets/ringmaster_page_shell.dart';

void main() {
  for (final (size, textScale) in [
    (const Size(360, 520), 1.0),
    (const Size(640, 360), 1.0),
    (const Size(320, 640), 1.5),
  ]) {
    testWidgets(
      'Herd controls and animal rows scroll at $size with text scale $textScale',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? opened;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: AppShell(
              child: RingMasterPageShell(
                title: 'Test Herd',
                onRefresh: () {},
                actions: [
                  TextButton(onPressed: () {}, child: const Text('Sync')),
                ],
                body: AnimalBrowser(
                  animals: List.generate(
                    24,
                    (i) => {
                      'id': '$i',
                      'name': 'Animal $i',
                      'tattoo': 'TAG$i',
                      'species': 'rabbit',
                      'breed': 'Dutch',
                      'variety': 'Black',
                      'sex': 'Doe',
                      'status': 'active',
                      'dob': '2025-04-03',
                    },
                  ),
                  onAdd: () {},
                  onRefresh: () {},
                  onOpen: (animal) => opened = animal['id'] as String,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final scrollable = find
            .descendant(
              of: find.byType(AnimalBrowser),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.text('Animal 23 • TAG23'),
          350,
          scrollable: scrollable,
          maxScrolls: 80,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Animal 23 • TAG23'));
        expect(opened, '23');
        await tester.scrollUntilVisible(
          find.byType(TextField),
          -350,
          scrollable: scrollable,
          maxScrolls: 80,
        );
        await tester.enterText(find.byType(TextField), 'no matching animal');
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('No animals match your filters.'),
          200,
          scrollable: scrollable,
        );
        await tester.scrollUntilVisible(
          find.byType(TextField),
          -350,
          scrollable: scrollable,
        );
        await tester.enterText(find.byType(TextField), '');
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byTooltip('List view').hitTestable(),
          150,
          scrollable: scrollable,
        );
        await tester.tap(find.byTooltip('List view'));
        await tester.pumpAndSettle();
        expect(find.byType(AnimalRecordCard), findsNothing);
        await tester.scrollUntilVisible(
          find.text('Animal 23 • TAG23'),
          350,
          scrollable: scrollable,
          maxScrolls: 80,
        );
        await tester.pumpAndSettle();
        opened = null;
        await tester.tap(find.text('Animal 23 • TAG23'));
        expect(opened, '23');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
