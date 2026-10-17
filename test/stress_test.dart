import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/screens/animal_list_screen.dart';
import 'package:ringmaster_breeder/utils/herd_calendar.dart';
import 'package:ringmaster_breeder/widgets/bulk_records_dialog.dart';

List<Map<String, dynamic>> animals(int count) => List.generate(
  count,
  (i) => {
    'id': 'animal-$i',
    'name': 'Animal $i',
    'tattoo': 'TAG$i',
    'species': 'rabbit',
    'breed': 'Dutch',
    'variety': 'Black',
    'sex': 'Doe',
    'status': i % 10 == 0 ? 'sold' : 'active',
    'dob': '2025-04-03',
  },
);

void main() {
  testWidgets('stress: 1000 animal cards and repeated searches', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = animals(1000);
    Widget browser() => MaterialApp(
      home: Scaffold(
        body: AnimalBrowser(
          animals: data,
          onAdd: () {},
          onRefresh: () {},
          onOpen: (_) {},
        ),
      ),
    );
    final clock = Stopwatch()..start();
    await tester.pumpWidget(browser());
    await tester.pumpAndSettle();
    // Record construction as a diagnostic, not a speed assertion.
    // Widget-test timings are debug host timings, not browser frame timings.
    // ignore: avoid_print
    print(
      'STRESS 1000 records: initial cards ${clock.elapsedMilliseconds}ms; '
      '${find.byType(AnimalRecordCard).evaluate().length} mounted cards',
    );
    expect(find.text('900 of 1000 animals'), findsOneWidget);
    expect(find.byType(AnimalRecordCard).evaluate().length, lessThan(40));
    for (var i = 1; i <= 20; i++) {
      final id = i * 10 + 1;
      await tester.enterText(find.byType(TextField), 'TAG$id');
      await tester.pumpAndSettle();
      expect(find.text('Animal $id • TAG$id'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    // Preserve the current narrow search while growing the dataset.
    data.addAll(animals(10000).skip(1000));
    await tester.pumpWidget(browser());
    await tester.pumpAndSettle();
    clock.reset();
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('9000 of 10000 animals'), findsOneWidget);
    expect(find.byType(AnimalRecordCard).evaluate().length, lessThan(40));
    // ignore: avoid_print
    print(
      'STRESS 10000 records: card search reset ${clock.elapsedMilliseconds}ms; '
      '${find.byType(AnimalRecordCard).evaluate().length} mounted cards',
    );
    for (var i = 0; i < 20; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -800));
      await tester.pumpAndSettle();
      expect(find.byType(AnimalRecordCard).evaluate().length, lessThan(40));
      expect(tester.takeException(), isNull);
    }
    // Narrow the search before comparing the list search-reset timing.
    await tester.scrollUntilVisible(
      find.byType(TextField),
      -1400,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 100,
    );
    await tester.enterText(find.byType(TextField), 'TAG9999');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('List view'));
    await tester.pumpAndSettle();
    clock.reset();
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('9000 of 10000 animals'), findsOneWidget);
    expect(find.byType(ListTile).evaluate().length, lessThan(100));
    // ignore: avoid_print
    print(
      'STRESS 10000 records: list search reset ${clock.elapsedMilliseconds}ms',
    );
    for (var i = 0; i < 20; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -800));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.scrollUntilVisible(
      find.byType(TextField),
      -1400,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 100,
    );
    await tester.enterText(find.byType(TextField), 'TAG9999');
    await tester.pumpAndSettle();
    expect(find.text('Animal 9999 • TAG9999'), findsOneWidget);
    await tester.tap(find.byTooltip('Card view'));
    await tester.pumpAndSettle();
    expect(find.byType(AnimalRecordCard), findsOneWidget);
  });

  test(
    'stress: 10000 breedings and 10000 health records preserve and sort events',
    () {
      final breedings = List.generate(
        10000,
        (i) => <String, dynamic>{
          'dam': {'id': 'dam-$i', 'name': 'Dam $i', 'species': 'rabbit'},
          'breeding_date': '2026-01-01',
          'status': 'active',
        },
      );
      final health = List.generate(
        10000,
        (i) => <String, dynamic>{
          'animal': {'id': 'dam-$i', 'name': 'Dam $i'},
          'title': 'Check $i',
          'administered_date': '2026-02-01',
          'readminister_date': '2026-03-01',
          'expires_date': '2027-01-01',
        },
      );
      final clock = Stopwatch()..start();
      final events = herdCalendarEvents(breedings, {}, health);
      // Each active rabbit breeding produces five events; each health record three.
      expect(events.length, 80000);
      expect(events.where((e) => e.category == 'Health').length, 30000);
      expect(events.where((e) => e.animalId == 'dam-9999').length, 8);
      for (var i = 1; i < events.length; i++) {
        expect(events[i].start.isBefore(events[i - 1].start), isFalse);
      }
      // ignore: avoid_print
      print('STRESS 80000 calendar events: ${clock.elapsedMilliseconds}ms');
    },
  );

  testWidgets('stress: 1000 animal bulk selection, failed write and retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var calls = 0;
    final pending = Completer<void>();
    List<Map<String, dynamic>>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BulkRecordsDialog(
            animals: animals(1000),
            weights: false,
            writer: (table, rows) async {
              calls++;
              expect(table, 'animal_health_records');
              if (calls == 1) throw StateError('Synthetic write failure');
              saved = rows;
              await pending.future;
            },
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, 'Stress check');
    final selectAll = find.text('Select all eligible animals');
    await tester.ensureVisible(selectAll);
    await tester.tap(selectAll);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save for 900 animals'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.tap(find.text('Save for 900 animals'));
    await tester.pump();
    expect(calls, 2);
    expect(find.text('Saving…'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(saved!.length, 900);
    expect(saved!.map((r) => r['animal_id']).toSet().length, 900);
    expect(
      saved!.any(
        (r) => int.parse((r['animal_id'] as String).split('-').last) % 10 == 0,
      ),
      isFalse,
    );
    expect(saved!.every((r) => r['title'] == 'Stress check'), isTrue);
    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
