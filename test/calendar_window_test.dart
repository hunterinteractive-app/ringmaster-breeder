import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/services/herd_calendar_service.dart';
import 'package:ringmaster_breeder/screens/herd_calendar_screen.dart';
import 'package:ringmaster_breeder/utils/herd_calendar.dart';

void main() {
  testWidgets(
    'calendar rolls across years, returns to today and ignores stale requests',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final windows = <CalendarWindow>[];
      final pending = <Completer<List<HerdCalendarEvent>>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: HerdCalendarScreen(
            ringId: 'r',
            windowLoader: (w) {
              windows.add(w);
              final c = Completer<List<HerdCalendarEvent>>();
              pending.add(c);
              return c.future;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Next month'));
      await tester.pump();
      expect(
        windows[1].start,
        DateTime(windows[0].start.year, windows[0].start.month + 1),
      );
      pending[1].complete([]);
      await tester.pumpAndSettle();
      pending[0].complete([
        HerdCalendarEvent(
          title: 'Stale',
          animal: 'A',
          category: 'Health',
          animalId: 'a',
          start: DateTime.now(),
          end: DateTime.now(),
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Stale'), findsNothing);
      await tester.tap(find.text('Today'));
      await tester.pump();
      expect(windows.last.start, windows.first.start);
      pending.last.complete([]);
      await tester.pumpAndSettle();
      final dec = CalendarWindow.around(DateTime(2026, 12));
      expect(dec.start, DateTime(2026, 11));
      expect(dec.end, DateTime(2027, 2));
      final jan = CalendarWindow.around(DateTime(2027, 1));
      expect(jan.start, DateTime(2026, 12));
      expect(jan.end, DateTime(2027, 3));
      expect(tester.takeException(), isNull);
    },
  );
}
