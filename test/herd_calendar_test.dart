import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/utils/herd_calendar.dart';
import 'package:ringmaster_breeder/screens/herd_calendar_screen.dart';

Map<String, dynamic> record({
  String species = 'rabbit',
  String status = 'active',
  Map<String, dynamic> tracking = const {},
}) => {
  'id': 'b',
  'breeding_date': '2026-10-01',
  'status': status,
  'dam': {'id': 'd', 'name': 'Maple', 'tattoo': 'MPL', 'species': species},
  'tracking': tracking,
};
void main() {
  test('Entered shows are deduplicated and only mark their opening date', () {
    final show = <String, dynamic>{
      'id': 's',
      'name': 'Fall Show',
      'start_date': '2026-10-20',
      'end_date': '2026-10-22',
      'entry_count': 3,
      'location_name': 'Fairgrounds',
      'entries': [],
    };
    final events = enteredShowEvents([show, show]);
    expect(events.length, 1);
    expect(events.single.category, 'Shows');
    expect(events.single.occursOn(DateTime(2026, 10, 20)), true);
    expect(events.single.occursOn(DateTime(2026, 10, 21)), false);
    expect(events.single.note, contains('10-20-26 – 10-22-26'));
    expect(events.single.show!['entries'], isEmpty);
  });
  testWidgets('Show calendar event opens entered animal details', (
    tester,
  ) async {
    final now = DateTime.now();
    final events = enteredShowEvents([
      {
        'id': 's',
        'name': 'Entered Show',
        'start_date': DateTime(now.year, now.month, now.day).toIso8601String(),
        'entry_count': 1,
        'entries': [
          {
            'animal_name': 'Maple',
            'tattoo': 'MPL',
            'breed': 'Dutch',
            'exhibitor_name': 'Exhibitor',
          },
        ],
      },
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: HerdCalendarScreen(ringId: 'r', loader: () async => events),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shows'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Entered Show'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Entered Show'));
    await tester.pumpAndSettle();
    expect(find.text('Maple • MPL'), findsOneWidget);
    expect(find.textContaining('Manage these entries'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'Rabbit windows show only start and final dates with an explanatory note',
    () {
      final events = herdCalendarEvents(
        [record()],
        {
          'rabbit': {'gestation_min': 29, 'gestation_max': 31},
        },
        [],
      );
      final birth = events.firstWhere((e) => e.category == 'Birth');
      expect(birth.start, DateTime(2026, 10, 30));
      expect(birth.end, birth.start);
      final finalDue = events.lastWhere((e) => e.category == 'Birth');
      expect(finalDue.start, DateTime(2026, 11, 1));
      expect(finalDue.title, contains('Final due day'));
      expect(birth.note, contains('10-30-26 – 11-01-26'));
      expect(finalDue.note, birth.note);
      expect(
        events.where(
          (e) => e.category == 'Birth' && e.occursOn(DateTime(2026, 10, 31)),
        ),
        isEmpty,
      );
      expect(events.where((e) => e.category == 'Palpation').length, 1);
      expect(birth.occursOn(DateTime(2026, 11, 2)), false);
      expect(
        events.firstWhere((e) => e.category == 'Palpation').start,
        DateTime(2026, 10, 15),
      );
    },
  );
  test('Cavy has no nesting and uses pup and weaning windows', () {
    final before = herdCalendarEvents([record(species: 'cavy')], {}, []);
    expect(before.any((e) => e.category == 'Nesting'), false);
    expect(
      before.lastWhere((e) => e.category == 'Birth').end,
      DateTime(2026, 12, 12),
    );
    final after = herdCalendarEvents(
      [
        record(species: 'cavy', tracking: {'birth_date': '2026-12-01'}),
      ],
      {},
      [],
    );
    expect(after.firstWhere((e) => e.category == 'Birth').title, 'Pups born');
    expect(
      after.firstWhere((e) => e.category == 'Weaning').start,
      DateTime(2026, 12, 22),
    );
    expect(
      after.lastWhere((e) => e.category == 'Weaning').end,
      DateTime(2026, 12, 29),
    );
    expect(after.any((e) => e.category == 'Palpation'), false);
  });
  test(
    'Actual dates replace forecasts; cancelled and negative do not predict births',
    () {
      final events = herdCalendarEvents(
        [
          record(
            status: 'completed',
            tracking: {
              'check_date': '2026-10-15',
              'check_result': 'Positive',
              'birth_date': '2026-11-01',
              'wean_date': '2026-12-01',
            },
          ),
        ],
        {},
        [],
      );
      expect(events.where((e) => e.estimated), isEmpty);
      expect(events.length, 4);
      expect(
        herdCalendarEvents([record(status: 'cancelled')], {}, []),
        isEmpty,
      );
      expect(
        herdCalendarEvents(
          [
            record(tracking: {'check_result': 'Negative'}),
          ],
          {},
          [],
        ).any((e) => e.category == 'Birth'),
        false,
      );
    },
  );
  test('Health creates recorded, follow-up and expiration dates', () {
    final events = herdCalendarEvents([], {}, [
      {
        'title': 'Vaccine',
        'animal': {'id': 'a', 'name': null, 'tattoo': 'A1'},
        'administered_date': '2026-10-01',
        'readminister_date': '2026-11-01',
        'expires_date': '2027-10-01',
      },
    ]);
    expect(events.length, 3);
    expect(events.last.animal, 'A1');
    expect(events[1].title, 'Follow-up due • Vaccine');
  });
  for (final width in [320.0, 800.0, 1280.0]) {
    testWidgets('Calendar and agenda fit at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: HerdCalendarScreen(ringId: 'r', loader: () async => []),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Agenda'));
      await tester.pumpAndSettle();
      expect(find.text('This month'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
