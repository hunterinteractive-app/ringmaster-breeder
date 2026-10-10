import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/widgets/record_breeding_dialog.dart';

void main() {
  testWidgets(
    'One sire saves independent records for multiple same-species dams',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      List<Map<String, dynamic>>? saved;
      Map<String, dynamic> animal(
        String id,
        String sex, {
        String species = 'rabbit',
        String status = 'active',
        String breed = 'Tan',
      }) => {
        'id': id,
        'tattoo': id,
        'sex': sex,
        'species': species,
        'status': status,
        'ring_id': 'ring',
        'breed': breed,
        'variety': 'Chocolate',
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecordBreedingDialog(
              animals: [
                animal('SIRE', 'Buck'),
                animal('DAM1', 'Doe', breed: 'Dutch'),
                animal('DAM2', 'Doe'),
                animal('CAVY', 'Sow', species: 'cavy'),
                animal('SOLD', 'Doe', status: 'sold'),
              ],
              writer: (records) async => saved = records,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Save breeding'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(find.text('Choose a sire and at least one dam.'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SIRE').last);
      await tester.pumpAndSettle();
      expect(find.text('CAVY'), findsNothing);
      expect(find.text('SOLD'), findsNothing);
      expect(find.text('Tan • Chocolate'), findsWidgets);
      expect(
        tester.getTopLeft(find.text('DAM2')).dy,
        lessThan(tester.getTopLeft(find.text('DAM1')).dy),
      );
      await tester.tap(find.text('DAM1'));
      await tester.tap(find.text('DAM2'));
      await tester.enterText(find.byType(TextField), 'Test breeding');
      await tester.tap(find.text('Save breeding'));
      await tester.pumpAndSettle();
      expect(saved!.length, 2);
      expect(saved!.map((r) => r['dam_id']), ['DAM1', 'DAM2']);
      expect(
        saved!.every(
          (r) => r['sire_id'] == 'SIRE' && r['notes'] == 'Test breeding',
        ),
        isTrue,
      );
      expect(saved!.first['breeding_date'], saved!.last['breeding_date']);
    },
  );
}
