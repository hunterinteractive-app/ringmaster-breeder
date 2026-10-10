import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/widgets/bulk_records_dialog.dart';

void main() {
  testWidgets(
    'Bulk weights require each selected weight and exclude sold animals',
    (tester) async {
      List<Map<String, dynamic>>? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BulkRecordsDialog(
              animals: const [
                {'id': 'a', 'tattoo': 'A', 'status': 'active'},
                {'id': 'b', 'tattoo': 'B', 'status': 'active'},
                {'id': 'c', 'tattoo': 'SOLD', 'status': 'sold'},
              ],
              weights: true,
              writer: (table, rows) async {
                expect(table, 'animal_weights');
                saved = rows;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Select all eligible animals'));
      await tester.pumpAndSettle();
      expect(find.text('SOLD'), findsNothing);
      await tester.tap(find.text('Save for 2 animals'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      await tester.enterText(find.byType(TextField).at(0), '4.25');
      await tester.enterText(find.byType(TextField).at(1), '5.1');
      await tester.tap(find.text('Save for 2 animals'));
      await tester.pumpAndSettle();
      expect(saved!.map((r) => r['animal_id']), ['a', 'b']);
      expect(saved!.map((r) => r['weight']), [4.25, 5.1]);
      expect(saved!.first['recorded_at'], saved!.last['recorded_at']);
    },
  );
  testWidgets('Bulk health copies the record only to selected animals', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    List<Map<String, dynamic>>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BulkRecordsDialog(
            animals: const [
              {'id': 'a', 'tattoo': 'A'},
              {'id': 'b', 'tattoo': 'B'},
            ],
            weights: false,
            writer: (table, rows) async {
              expect(table, 'animal_health_records');
              saved = rows;
            },
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'Routine check');
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save for 1 animals'));
    await tester.pumpAndSettle();
    expect(saved!.length, 1);
    expect(saved!.single['animal_id'], 'a');
    expect(saved!.single['title'], 'Routine check');
  });
}
