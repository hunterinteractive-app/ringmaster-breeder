import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/screens/show_reports_screen.dart';
import 'package:ringmaster_breeder/widgets/show_connection_panel.dart';

void main() {
  testWidgets(
    'Receiving reports is independent of herd sharing and can be disabled',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var enabled = false;
      final calls = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ShowConnectionPanel(
                gateway: (action, ids) async {
                  calls.add(action);
                  if (action == 'reports-enable') enabled = true;
                  if (action == 'reports-disable') enabled = false;
                  if (action == 'reports-refresh') {
                    return {'reports': 2, 'results': 6};
                  }
                  return {
                    'connection': {
                      'enabled': false,
                      'herd_ids': [],
                      'reports_enabled': enabled,
                    },
                    'herds': [],
                  };
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(
        calls,
        containsAllInOrder(['reports-enable', 'reports-refresh', 'status']),
      );
      expect(
        find.text('Received 2 reports and 6 show results.'),
        findsOneWidget,
      );
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(calls.where((a) => a == 'reports-refresh').length, 1);
      expect(
        find.text('Report receiving stopped. Your received reports are kept.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'Result card displays fur placement, awards and unmatched status',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShowResultCard(
              row: {
                'animal_id': null,
                'source_available': false,
                'record': {
                  'shows': {'name': 'Test Show', 'start_date': '2026-10-01'},
                  'animal_name': 'Viper',
                  'tattoo': 'VIP',
                  'is_fur': true,
                  'placement': '3',
                  'fur_placement': '1',
                  'entry_awards': [
                    {'award_code': 'BOV'},
                  ],
                },
              },
            ),
          ),
        ),
      );
      expect(find.text('Viper • VIP'), findsOneWidget);
      expect(find.text('Oct 1, 2026'), findsOneWidget);
      expect(find.text('1st place'), findsOneWidget);
      expect(find.text('BOV • Best of Variety'), findsOneWidget);
      expect(
        find.text('Not linked to an animal. The result is retained here.'),
        findsOneWidget,
      );
      expect(
        find.text('Previous result — no current report available in Show.'),
        findsOneWidget,
      );
    },
  );
}
