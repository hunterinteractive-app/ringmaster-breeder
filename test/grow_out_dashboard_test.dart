import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/services/grow_out_service.dart';
import 'package:ringmaster_breeder/utils/grow_out_summary.dart';
import 'package:ringmaster_breeder/widgets/grow_out_dashboard.dart';
import 'package:ringmaster_breeder/screens/production_measurements_screen.dart';
import 'package:ringmaster_breeder/screens/breeding_tracker_screen.dart';
import 'litter_grow_out_test.dart' show litter;

void main() {
  final today = DateTime(2026, 10, 24);
  final readings = <Map<String, dynamic>>[
    {
      'id': 'old',
      'breeding_id': 'grow-out',
      'recorded_date': '2026-09-16',
      'weight': 5,
      'feed_weight': 10,
    },
    {
      'id': 'latest-weight',
      'breeding_id': 'grow-out',
      'recorded_date': '2026-10-01',
      'weight': '12',
      'feed_weight': 30,
    },
    {
      'id': 'latest-feed',
      'breeding_id': 'grow-out',
      'recorded_date': '2026-10-02',
      'feed_weight': '35',
    },
    {
      'id': 'voided',
      'breeding_id': 'grow-out',
      'recorded_date': '2026-10-03',
      'weight': 99,
      'feed_weight': 99,
      'voided': true,
    },
    {
      'id': 'future',
      'breeding_id': 'grow-out',
      'recorded_date': '2027-01-01',
      'weight': 100,
      'feed_weight': 100,
    },
    {
      'id': 'nursing',
      'breeding_id': 'grow-out',
      'recorded_date': '2026-09-01',
      'weight': 100,
      'feed_weight': 100,
    },
  ];

  test('Totals use the latest valid weight and cumulative feed per group', () {
    final rabbit = litter();
    (rabbit['offspring'] as List).add({
      'animal_id': 'kept',
      'animal': {'sex': 'Buck'},
    });
    final cavy = litter(species: 'cavy')..['id'] = 'cavy';
    final completed = litter()..['status'] = 'completed';
    completed['tracking']['status'] = 'completed';
    final summary = GrowOutSummary(
      growOutGroups([rabbit, cavy, completed], readings, now: today),
    );
    expect(summary.groups, hasLength(2));
    expect(summary.animals, 5);
    expect(summary.rabbits, 2);
    expect(summary.cavies, 3);
    expect(summary.weighed, 1);
    expect(summary.fed, 1);
    expect(summary.weight, 12);
    expect(summary.feed, 35);
    expect(summary.groups.first.remainingSex(true), 1);
    expect(summary.groups.first.remainingSex(false), 1);
    final unknown = GrowOutSummary(growOutGroups([cavy], readings, now: today));
    expect(unknown.weight, isNull);
    expect(unknown.feed, isNull);
    final zeroFeed = GrowOutSummary(
      growOutGroups(
        [cavy],
        [
          {
            'id': 'zero',
            'breeding_id': 'cavy',
            'recorded_date': '2026-10-01',
            'weight': 0,
            'feed_weight': 0,
          },
        ],
        now: today,
      ),
    );
    expect(zeroFeed.weight, isNull);
    expect(zeroFeed.feed, 0);
  });

  test(
    'Measurement loads batch groups and exhaust pages even with a smaller API cap',
    () async {
      final records = [for (var i = 0; i < 101; i++) litter()..['id'] = 'g$i'];
      final calls = <List<String>>[];
      final rows = await loadGrowOutMeasurements(
        records,
        readPage: (ids, from, to) async {
          calls.add(ids);
          // Server cap of 200, with more than 1,000 readings in the first batch.
          final count = ids.first == 'g0' ? 1201 : 1;
          if (from >= count) return [];
          return [
            for (var i = from; i < (from + 200).clamp(0, count); i++)
              {'id': '${ids.first}-$i', 'breeding_id': ids.first},
          ];
        },
      );
      expect(rows, hasLength(1202));
      expect(calls.first, hasLength(100));
      expect(calls.last, ['g100']);
      expect(
        await loadGrowOutMeasurements(
          [],
          readPage: (_, _, _) async => throw StateError('Must not query'),
        ),
        isEmpty,
      );
      await expectLater(
        loadGrowOutMeasurements(
          records,
          readPage: (_, _, _) async => throw StateError('Failed'),
        ),
        throwsStateError,
      );
    },
  );

  for (final width in [320.0, 1200.0]) {
    testWidgets('Dashboard totals, filters and group actions work at $width', (
      t,
    ) async {
      t.view.physicalSize = Size(width, 1800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final rabbit = litter();
      final cavy = litter(species: 'cavy')..['id'] = 'cavy';
      cavy['dam']['name'] = 'Cavy dam';
      String? measured, selected, edited;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GrowOutDashboard(
              records: [rabbit, cavy],
              measurements: readings,
              onMeasurements: (r) => measured = r['id'],
              onOffspring: (r) => selected = r['id'],
              onEdit: (r) => edited = r['id'],
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('3 rabbits • 3 cavies'), findsOneWidget);
      expect(find.text('12 lb'), findsOneWidget);
      expect(find.text('35 lb'), findsOneWidget);
      await t.tap(find.text('Rabbits'));
      await t.pumpAndSettle();
      expect(find.text('3 rabbits • 0 cavies'), findsOneWidget);
      expect(find.text('Cavy dam'), findsNothing);
      for (final label in [
        'Weights & feed',
        'Create individual records',
        'Update litter tracking',
      ]) {
        final action = find.text(label);
        await t.ensureVisible(action);
        await t.tap(action);
        await t.pumpAndSettle();
      }
      expect(measured, 'grow-out');
      expect(selected, 'grow-out');
      expect(edited, 'grow-out');
      final search = find.byType(TextField);
      await t.ensureVisible(search);
      await t.enterText(search, 'no matching dam');
      await t.pumpAndSettle();
      expect(
        find.text('No grow-out groups match these filters.'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    });
  }

  testWidgets(
    'Dashboard creates selected records and updates the remaining total',
    (t) async {
      t.view.physicalSize = const Size(1000, 1800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final row = litter();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, set) => GrowOutDashboard(
                records: [row],
                measurements: readings,
                onMeasurements: (_) {},
                onEdit: (_) {},
                onOffspring: (r) async {
                  await showDialog<bool>(
                    context: context,
                    builder: (_) => LitterOffspringDialog(
                      record: r,
                      herdReader: () async => [],
                      writer: (young) async {
                        for (final y in young) {
                          (row['offspring'] as List).add({
                            'animal_id': y['tattoo'],
                            'animal': {'sex': y['sex']},
                          });
                        }
                      },
                    ),
                  );
                  set(() {});
                },
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Create individual records'));
      await t.tap(find.text('Create individual records'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('offspring-select-0')));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextFormField, 'Ear number / tag'),
        'KEEP1',
      );
      await t.tap(find.text('Create 1 animal'));
      await t.pumpAndSettle();
      expect(find.text('2 growing out'), findsOneWidget);
      expect(find.text('1 with individual records'), findsOneWidget);
      expect(find.text('2 rabbits • 0 cavies'), findsOneWidget);
      // The prior group weighing is retained as recorded, not divided by the new count.
      expect(find.text('Group weight: 12 lb'), findsOneWidget);
    },
  );

  testWidgets(
    'Grow-out measurements save group weight and cumulative feed together',
    (t) async {
      final rows = <Map<String, dynamic>>[];
      await t.pumpWidget(
        MaterialApp(
          home: ProductionMeasurementsScreen(
            recordId: 'grow-out',
            growOut: true,
            loader: () async => List.of(rows),
            writer: (r) async => rows.add(Map.of(r)),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Grow-out weights & feed'), findsOneWidget);
      await t.tap(find.byType(FloatingActionButton));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextField, 'Total group weight (lb) · optional'),
        '13',
      );
      await t.enterText(
        find.widgetWithText(TextField, 'Cumulative group feed (lb) · optional'),
        '40',
      );
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      await t.pump();
      expect(rows.single['breeding_id'], 'grow-out');
      expect(rows.single['weight'], 13);
      expect(rows.single['feed_weight'], 40);
      expect(find.textContaining('40 lb cumulative feed'), findsOneWidget);
    },
  );
}
