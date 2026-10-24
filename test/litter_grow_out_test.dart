import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/screens/breeding_tracker_screen.dart';
import 'package:ringmaster_breeder/utils/litter_lifecycle.dart';
import 'package:ringmaster_breeder/widgets/breeding_dashboard.dart';

Map<String, dynamic> litter({String species = 'rabbit'}) => {
  'id': 'grow-out',
  'breeding_date': '2026-07-01',
  'status': 'active',
  'dam': {
    'name': 'Dam',
    'species': species,
    'breed': 'Dutch',
    'ring_id': 'herd',
  },
  'sire': {'name': 'Sire', 'breed': 'Dutch'},
  'tracking': {
    'birth_date': '2026-08-01',
    'born_alive': 3,
    'born_dead': 0,
    'wean_date': '2026-09-15',
    'weaned': 3,
    'weaned_males': 2,
    'weaned_females': 1,
    'weaning_destination': 'grow_out',
    'status': 'active',
  },
  'offspring': <Map<String, dynamic>>[],
};

void main() {
  test(
    'Grow out skips automatic record creation and counts only the group',
    () {
      final row = litter();
      expect(needsOffspring(row), isFalse);
      expect(breedingStage(row), 'Grow out');
      (row['offspring'] as List).add({
        'animal_id': 'kept',
        'animal': {'sex': 'Buck'},
      });
      expect(litterUnrecordedCount(row), 2);
      expect(litterIsGrowingOut(row), isTrue);
      row['tracking']['status'] = 'completed';
      expect(litterIsGrowingOut(row), isFalse);
      expect(breedingStage(row), 'Completed');
      row['tracking']['status'] = 'cancelled';
      expect(breedingStage(row), 'Cancelled');
    },
  );

  testWidgets('Weaning saves the grow-out choice without opening records', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final row = litter();
    row['tracking']['weaning_destination'] = 'individual';
    row['status'] = 'completed';
    row['tracking']['status'] = 'completed';
    Map<String, dynamic>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LitterTrackingDialog(
            record: row,
            writer: (data) async => saved = Map.of(data),
          ),
        ),
      ),
    );
    expect(find.text('Save tracking and create offspring records'), findsOne);
    final destination = find.byKey(const ValueKey('weaning-destination'));
    await tester.ensureVisible(destination);
    await tester.tap(destination);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grow out').last);
    await tester.pumpAndSettle();
    expect(
      find.text('Save tracking and create offspring records'),
      findsNothing,
    );
    await tester.tap(find.text('Save tracking'));
    await tester.pumpAndSettle();
    expect(saved?['weaning_destination'], 'grow_out');
    expect(saved?['status'], 'active');
    expect(saved?['weaned'], 3);
    expect(needsOffspring({...row, 'tracking': saved}), isFalse);
  });

  for (final species in ['rabbit', 'cavy']) {
    testWidgets('Selected $species get records while the remainder grow out', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final row = litter(species: species);
      // One male already has a record; the next male and female remain grouped.
      (row['offspring'] as List).add({
        'animal_id': 'kept',
        'animal': {'sex': species == 'cavy' ? 'Boar' : 'Buck'},
      });
      List<Map<String, dynamic>>? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LitterOffspringDialog(
              record: row,
              herdReader: () async => [],
              writer: (young) async => saved = young,
            ),
          ),
        ),
      );
      expect(find.textContaining('2 will remain in grow out'), findsOne);
      await tester.tap(find.text('Create 0 animals'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(
        find.text('Select at least one animal for its own record.'),
        findsOne,
      );
      await tester.tap(find.byKey(const ValueKey('offspring-select-1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('1 will remain in grow out'), findsOne);
      expect(find.text(species == 'cavy' ? 'Sow' : 'Doe'), findsOne);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ear number / tag'),
        'KEPT-2',
      );
      await tester.tap(find.text('Create 1 animal'));
      await tester.pumpAndSettle();
      expect(saved, hasLength(1));
      expect(saved!.single['tattoo'], 'KEPT-2');
      expect(saved!.single['sex'], 'F');
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [320.0, 1200.0]) {
    testWidgets('Grow-out filter and group actions fit at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? opened;
      final ordinary = litter()..['id'] = 'ordinary';
      ordinary['dam']['name'] = 'Other dam';
      ordinary['tracking']['weaning_destination'] = 'individual';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BreedingDashboard(
              records: [litter(), ordinary],
              settings: const {},
              filter: 'Grow out',
              onFilter: (_) {},
              onEdit: (_) {},
              onOffspring: (r) => opened = r['id'],
              onOpen: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Other dam'), findsNothing);
      expect(find.text('3 kits • 0 with individual records'), findsOne);
      expect(find.text('Grow-out weights & feed'), findsOne);
      final create = find.text('Create individual records');
      await tester.ensureVisible(create);
      await tester.tap(create);
      expect(opened, 'grow-out');
      expect(tester.takeException(), isNull);
    });
  }
}
