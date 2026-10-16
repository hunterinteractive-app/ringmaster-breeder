// Local synthetic capacity checks. Timings are debug-host diagnostics, not
// production browser or database latency measurements.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:ringmaster_breeder/screens/animal_list_screen.dart';
import 'package:ringmaster_breeder/screens/herd_calendar_screen.dart';
import 'package:ringmaster_breeder/utils/herd_calendar.dart';
import 'package:ringmaster_breeder/widgets/weight_graph.dart';

void main() {
  for (final count in [5, 25, 100, 500, 1000]) {
    for (final width in [320.0, 1200.0]) {
      testWidgets('herd capacity: $count active animals at $width', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final animals = List.generate(
          count,
          (i) => <String, dynamic>{
            'id': '$i',
            'name': 'Herd animal $i',
            'tattoo': 'TAG-$i-END',
            'species': i.isEven ? 'rabbit' : 'cavy',
            'status': 'active',
            'breed': i.isEven ? 'Dutch' : 'American',
            'variety': 'Black',
            'sex': i.isEven ? 'Doe' : 'Sow',
            'dob': '2025-04-03',
          },
        );
        String? opened;
        final clock = Stopwatch()..start();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AnimalBrowser(
                animals: animals,
                onAdd: () {},
                onRefresh: () {},
                onOpen: (animal) => opened = animal['id'] as String,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('$count of $count animals'), findsOneWidget);
        expect(
          find.byType(AnimalRecordCard).evaluate().length,
          lessThanOrEqualTo(32),
        );
        // ignore: avoid_print
        print(
          'HERD $count width $width: initial ${clock.elapsedMilliseconds}ms; '
          '${find.byType(AnimalRecordCard).evaluate().length} cards',
        );
        final target = 'Herd animal ${count - 1} • TAG-${count - 1}-END';
        await tester.enterText(find.byType(TextField), 'TAG-${count - 1}-END');
        await tester.pumpAndSettle();
        expect(find.text('1 of $count animals'), findsOneWidget);
        await tester.tap(find.text(target));
        expect(opened, '${count - 1}');
        await tester.tap(find.byTooltip('List view'));
        await tester.pumpAndSettle();
        expect(find.text(target), findsOneWidget);
        await tester.tap(find.byTooltip('Clear search'));
        await tester.pumpAndSettle();
        expect(find.text('$count of $count animals'), findsOneWidget);
        expect(find.byType(ListTile).evaluate().length, lessThan(50));
        await tester.enterText(find.byType(TextField), 'no-such-animal');
        await tester.pumpAndSettle();
        expect(find.text('No animals match your filters.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('history capacity: 300000 health records and 10000 breedings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Spread records over twenty years and 1000 animals, including today.
    final today = calendarDate(DateTime.now());
    final health = List.generate(300000, (i) {
      final day = today.subtract(Duration(days: i % 7300));
      return <String, dynamic>{
        'id': 'health-$i',
        'animal': {'id': 'animal-${i % 1000}', 'name': 'Animal ${i % 1000}'},
        'title': 'Health $i',
        'administered_date': day.toIso8601String(),
        if (i % 10 == 0)
          'readminister_date': day
              .add(const Duration(days: 14))
              .toIso8601String(),
        if (i % 10 == 0)
          'expires_date': day.add(const Duration(days: 365)).toIso8601String(),
      };
    });
    final breedings = List.generate(
      10000,
      (i) => <String, dynamic>{
        'id': 'breeding-$i',
        'dam': {
          'id': 'animal-${i % 1000}',
          'name': 'Animal ${i % 1000}',
          'species': 'rabbit',
        },
        'breeding_date': today
            .subtract(Duration(days: i % 7300))
            .toIso8601String(),
        'status': 'active',
      },
    );
    final clock = Stopwatch()..start();
    final events = herdCalendarEvents(breedings, {}, health);
    final conversionMs = clock.elapsedMilliseconds;
    expect(events.length, 410000);
    var healthCount = 0;
    final ids = <String>{};
    DateTime? previous;
    for (final event in events) {
      if (event.category == 'Health') healthCount++;
      ids.add(event.animalId);
      if (previous != null && event.start.isBefore(previous)) {
        fail('Historical events are out of order');
      }
      previous = event.start;
    }
    expect(healthCount, 360000);
    expect(ids.length, 1000);
    expect(
      events.any((e) => e.title == 'Health record • Health 299999'),
      isTrue,
    );
    clock.reset();
    await tester.pumpWidget(
      MaterialApp(
        home: HerdCalendarScreen(
          ringId: 'synthetic',
          loader: () async => events,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final renderMs = clock.elapsedMilliseconds;
    expect(find.text('No events for this selection.'), findsNothing);
    expect(tester.takeException(), isNull);
    clock.reset();
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    final previousMs = clock.elapsedMilliseconds;
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Health'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // ignore: avoid_print
    print(
      'HISTORY 310000 records -> 410000 events: conversion ${conversionMs}ms; '
      'calendar initial ${renderMs}ms; previous month ${previousMs}ms',
    );
  });

  for (final count in [300, 1000, 10000]) {
    testWidgets('weight chart capacity: $count historical weights', (
      tester,
    ) async {
      final weights = List.generate(
        count,
        (i) => <String, dynamic>{
          'recorded_at': DateTime(
            2000,
            1,
            1,
          ).add(Duration(days: i)).toIso8601String(),
          'weight': i == count ~/ 2 ? 12.5 : 4.0 + (i % 10) / 10,
        },
      );
      final clock = Stopwatch()..start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WeightGraph(weights: weights)),
        ),
      );
      await tester.pumpAndSettle();
      final chart = tester.widget<LineChart>(find.byType(LineChart)).data;
      final line = chart.lineBarsData.single;
      expect(line.spots.length, count);
      expect(line.spots.first.x, 0);
      expect(line.spots.last.x, count - 1);
      expect(chart.maxY, greaterThan(12.5));
      expect(tester.takeException(), isNull);
      // ignore: avoid_print
      print('WEIGHTS $count: chart ${clock.elapsedMilliseconds}ms');
    });
  }
}
