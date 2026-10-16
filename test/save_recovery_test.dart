import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/services/animal_service.dart';
import 'package:ringmaster_breeder/screens/edit_animal_screen.dart';
import 'package:ringmaster_breeder/widgets/bulk_records_dialog.dart';

void main() {
  testWidgets('conflicting animal edit retains draft until explicit reload', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var loads = 0;
    int? savedRevision;
    await tester.pumpWidget(
      MaterialApp(
        home: EditAnimalScreen(
          animalId: 'a',
          loader: (_) async => {
            'name': loads++ == 0 ? 'Original' : 'Latest family edit',
            'species': 'rabbit',
            'sex': 'Doe',
            'status': 'active',
            'breed': 'Dutch',
            'variety': 'Black',
            'revision': loads == 1 ? 3 : 4,
          },
          writer: (_, changes, revision) async {
            savedRevision = revision;
            throw AnimalEditConflict();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'My unsaved draft');
    await tester.ensureVisible(find.text('Save Changes'));
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();
    expect(savedRevision, 3);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'My unsaved draft',
    );
    expect(find.textContaining('Your edits are still shown'), findsOneWidget);
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Save Changes'),
          )
          .onPressed,
      isNull,
    );
    await tester.ensureVisible(find.text('Reload latest record'));
    await tester.tap(find.text('Reload latest record'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'Latest family edit',
    );
    expect(find.text('Reload latest record'), findsNothing);
    expect(
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Save Changes'),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
  for (final weights in [false, true]) {
    testWidgets(
      'bulk retry preserves record IDs and payload: weights=$weights',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 2200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final attempts = <List<Map<String, dynamic>>>[];
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BulkRecordsDialog(
                animals: const [
                  {'id': 'a', 'tattoo': 'A', 'status': 'active'},
                ],
                weights: weights,
                writer: (_, rows) async {
                  attempts.add(rows);
                  if (attempts.length == 1) {
                    throw StateError('Lost acknowledgement');
                  }
                },
              ),
            ),
          ),
        );
        if (!weights) {
          await tester.enterText(find.byType(TextField).first, 'Health check');
        }
        await tester.tap(find.text('Select all eligible animals'));
        await tester.pumpAndSettle();
        if (weights) {
          await tester.enterText(find.byType(TextField).first, '4.5');
        }
        await tester.tap(find.text('Save for 1 animals'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Retry to check'), findsOneWidget);
        expect(attempts.single.single['id'], isNotEmpty);
        expect(
          tester
              .widget<AbsorbPointer>(
                find.byWidgetPredicate(
                  (w) => w is AbsorbPointer && w.absorbing,
                ),
              )
              .absorbing,
          isTrue,
        );
        await tester.tap(find.text('Save for 1 animals'));
        await tester.pumpAndSettle();
        expect(attempts.length, 2);
        expect(attempts[1], attempts[0]);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
