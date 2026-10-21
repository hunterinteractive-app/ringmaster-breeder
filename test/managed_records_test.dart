import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/widgets/managed_record_dialogs.dart';
import 'package:ringmaster_breeder/widgets/link_litter_offspring_dialog.dart';
import 'package:ringmaster_breeder/screens/breeding_tracker_screen.dart';

void main() {
  testWidgets(
    'New contacts can be entered without an import and retries preserve the form',
    (t) async {
      t.view.physicalSize = const Size(1000, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final saved = <Map<String, dynamic>>[];
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContactEditorDialog(
              herds: const [
                {'id': 'herd', 'name': 'My herd'},
              ],
              writer: (row) async {
                saved.add(Map.of(row));
                if (saved.length == 1) throw Exception('Uncertain response');
              },
            ),
          ),
        ),
      );
      await t.enterText(find.byType(TextField).first, 'Breeder');
      await t.enterText(find.byType(TextField).at(1), 'Rabbitry');
      await t.tap(find.text('Save contact'));
      await t.pumpAndSettle();
      expect(saved.length, 1);
      expect(saved.first['ring_id'], 'herd');
      expect(saved.first['name'], 'Breeder');
      await t.tap(find.text('Save contact'));
      await t.pumpAndSettle();
      expect(saved.last, saved.first);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('New show results capture judges, placings and leg flags', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    Map<String, dynamic>? saved;
    String? animal;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShowResultEditorDialog(
            animals: const [
              {'id': 'rabbit', 'name': 'Rabbit', 'tattoo': 'R1'},
            ],
            writer: (id, row) async {
              animal = id;
              saved = Map.of(row);
            },
          ),
        ),
      ),
    );
    await t.enterText(find.byType(TextField).first, 'New show');
    await t.enterText(find.byType(TextField).at(1), '2014-01-01');
    await t.enterText(find.byType(TextField).at(3), 'Judge');
    await t.ensureVisible(find.text('ARBA leg recorded'));
    await t.tap(find.text('ARBA leg recorded'));
    await t.tap(find.text('Save show result'));
    await t.pumpAndSettle();
    expect(animal, 'rabbit');
    expect(saved?['judge'], 'Judge');
    expect(saved?['is_leg'], true);
    expect(t.takeException(), isNull);
  });
  testWidgets('Linking existing offspring preserves selected identities', (
    t,
  ) async {
    t.view.physicalSize = const Size(600, 1100);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    List<String>? ids;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LinkLitterOffspringDialog(
            animals: const [
              {'id': 'one', 'name': 'Already linked'},
              {'id': 'two', 'name': 'Imported kit'},
            ],
            linked: const {'one'},
            limit: 2,
            writer: (rows) async {
              ids = rows;
            },
          ),
        ),
      ),
    );
    await t.tap(find.textContaining('Imported kit'));
    await t.tap(find.text('Link selected rabbits'));
    await t.pumpAndSettle();
    expect(ids, unorderedEquals(['one', 'two']));
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'An imported litter can save notes without inventing unknown counts',
    (t) async {
      t.view.physicalSize = const Size(1000, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      Map<String, dynamic>? saved;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LitterTrackingDialog(
              record: const {
                'id': 'litter',
                'import_source': 'source',
                'breeding_date': '2013-01-01',
                'status': 'completed',
                'dam': {'species': 'rabbit'},
                'offspring': [],
                'tracking': {
                  'revision': 1,
                  'birth_date': '2013-02-01',
                  'weaned': 4,
                  'born_total': 5,
                  'status': 'completed',
                  'import_record': {'ID': '1'},
                },
              },
              writer: (data) async {
                saved = Map.of(data);
              },
            ),
          ),
        ),
      );
      await t.tap(find.text('Save tracking'));
      await t.pumpAndSettle();
      expect(saved?['weaned'], 4);
      expect(saved?['born_alive'], null);
      expect(saved?['born_dead'], null);
      expect(t.takeException(), isNull);
    },
  );
}
