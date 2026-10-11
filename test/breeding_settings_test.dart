import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/widgets/breeding_settings_dialog.dart';

void main() {
  test('Species defaults and calendar windows match requested ranges', () {
    final r = breedingDefaults('rabbit'), c = breedingDefaults('cavy');
    expect(
      [
        r['gestation_min'],
        r['gestation_max'],
        r['palpation_min'],
        r['palpation_max'],
        r['nesting_day'],
        r['weaning_min'],
        r['weaning_max'],
      ],
      [28, 32, 14, 14, 26, 4, 8],
    );
    expect(
      [
        c['gestation_min'],
        c['gestation_max'],
        c['palpation_min'],
        c['palpation_max'],
        c['nesting_day'],
        c['weaning_min'],
        c['weaning_max'],
      ],
      [59, 72, 28, 30, null, 3, 4],
    );
    expect(breedingDay(DateTime(2026, 3, 1), 14), DateTime(2026, 3, 15));
    expect(breedingDay(DateTime(2026, 10, 20), 4 * 7), DateTime(2026, 11, 17));
  });
  testWidgets('Reject reversed ranges and save both species for the Ring', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    List<Map<String, dynamic>>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BreedingSettingsDialog(
            ringId: 'ring',
            settings: const {},
            writer: (rows) async {
              saved = rows;
            },
          ),
        ),
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Gestation start (days)').first,
      '40',
    );
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Gestation start (days)').first,
      '29',
    );
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    expect(saved!.length, 2);
    expect(saved!.first['gestation_min'], 29);
    expect(saved!.last['nesting_day'], isNull);
    expect(saved!.every((r) => r['ring_id'] == 'ring'), isTrue);
  });
}
