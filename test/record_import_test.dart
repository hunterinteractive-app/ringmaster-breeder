import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/screens/record_import_screen.dart';
import 'package:ringmaster_breeder/services/record_import_service.dart';

class FakeImport implements RecordImportGateway {
  final bool hasRing;
  FakeImport({this.hasRing = true});
  Map<String, dynamic>? selection;
  @override
  Future<List<Map<String, dynamic>>> ownedRings() async => hasRing
      ? [
          {'id': 'ring', 'name': 'My Ring'},
        ]
      : [];
  @override
  Future<Map<String, dynamic>> lookup() async => {
    'matches': [
      {
        'id': 'show-profile',
        'source': 'show',
        'display_name': 'Show exhibitor',
      },
      {
        'id': 'club-profile',
        'source': 'club',
        'display_name': 'Club exhibitor',
      },
    ],
  };
  @override
  Future<Map<String, dynamic>> importRecords(
    Map<String, dynamic> selection,
  ) async {
    this.selection = selection;
    return {
      'status': 'imported',
      'profiles_selected': 1,
      'animals_added': 0,
      'entries_added': 0,
    };
  }
}

void main() {
  for (final hasRing in [true, false]) {
    testWidgets('Show import respects Ring availability: $hasRing', (
      tester,
    ) async {
      final gateway = FakeImport(hasRing: hasRing);
      await tester.pumpWidget(
        MaterialApp(home: RecordImportScreen(gateway: gateway)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show exhibitor'));
      await tester.scrollUntilVisible(
        find.text('Import selected records'),
        250,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import selected records'));
      await tester.pumpAndSettle();
      expect(gateway.selection?['profile_ids'], ['show-profile']);
      expect(gateway.selection?['include_animals'], false);
      expect(gateway.selection?['include_entries'], true);
    });
  }
  testWidgets('Animal import requires an explicit choice', (tester) async {
    final gateway = FakeImport();
    await tester.pumpWidget(
      MaterialApp(home: RecordImportScreen(gateway: gateway)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show exhibitor'));
    await tester.scrollUntilVisible(find.text('Also import animals'), 200);
    await tester.tap(find.text('Also import animals'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Import selected records'), 200);
    await tester.tap(find.text('Import selected records'));
    await tester.pumpAndSettle();
    expect(gateway.selection?['include_animals'], true);
    expect(gateway.selection?['include_entries'], true);
  });
  testWidgets(
    'Switching source clears selection and Club excludes animal/history imports',
    (tester) async {
      final gateway = FakeImport();
      await tester.pumpWidget(
        MaterialApp(home: RecordImportScreen(gateway: gateway)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show exhibitor'));
      await tester.tap(find.text('Club'));
      await tester.pumpAndSettle();
      expect(find.text('Show exhibitor'), findsNothing);
      await tester.tap(find.text('Club exhibitor'));
      await tester.scrollUntilVisible(
        find.text('Import selected records'),
        250,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import selected records'));
      await tester.pumpAndSettle();
      expect(gateway.selection?['profile_ids'], ['club-profile']);
      expect(gateway.selection?['include_animals'], false);
      expect(gateway.selection?['include_entries'], false);
    },
  );
}
