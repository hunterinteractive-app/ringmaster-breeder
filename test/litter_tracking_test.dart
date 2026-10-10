import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/screens/breeding_tracker_screen.dart';

void main() {
  final record = <String, dynamic>{
    'id': 'test',
    'breeding_date': '2026-01-01',
    'status': 'active',
    'dam': {'species': 'rabbit'},
    'offspring': [],
  };
  test(
    'Gestation estimates differ by species; litter stages reflect milestones',
    () {
      expect(estimatedDue(record), DateTime(2026, 2, 1));
      expect(
        estimatedDue({
          ...record,
          'dam': {'species': 'cavy'},
        }),
        DateTime(2026, 3, 10),
      );
      expect(
        breedingStage({
          ...record,
          'tracking': {'birth_date': '2026-02-01'},
        }),
        'Nursing litter',
      );
      expect(
        breedingStage({
          ...record,
          'tracking': {'wean_date': '2026-03-01'},
        }),
        'Weaned',
      );
      expect(breedingStage({...record, 'status': 'cancelled'}), 'Cancelled');
    },
  );
  testWidgets(
    'Litter counts validate before saving, preserving event details',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, dynamic>? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LitterTrackingDialog(
              record: {
                ...record,
                'tracking': {
                  'birth_date': '2026-02-01',
                  'born_alive': 3,
                  'born_dead': 1,
                  'wean_date': '2026-03-01',
                  'weaned': 4,
                  'check_result': 'Positive',
                  'check_date': '2026-01-15',
                  'status': 'active',
                },
              },
              writer: (data) async {
                saved = Map.of(data);
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Save tracking'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(
        find.text('Number weaned cannot exceed number born alive.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Number weaned'),
        '2',
      );
      await tester.tap(find.text('Save tracking'));
      await tester.pumpAndSettle();
      expect(saved?['weaned'], 2);
      expect(saved?['born_alive'], 3);
      expect(saved?['birth_date'], '2026-02-01');
    },
  );
}
