import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/genetics/coat_rules.dart';
import 'package:ringmaster_breeder/genetics/color_prediction.dart';
import 'package:ringmaster_breeder/genetics/hotot_colors.dart';
import 'package:ringmaster_breeder/screens/genetics_screen.dart';

Map<String, dynamic> animal(
  String id,
  String breed,
  String variety,
  String sex,
) => {
  'id': id,
  'name': id,
  'species': 'rabbit',
  'breed': breed,
  'variety': variety,
  'sex': sex,
  'status': 'active',
};
Widget form(List<Map<String, dynamic>> animals) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GeneticsPreviewForm(animals: animals),
      ),
    ),
  ),
);
void main() {
  test(
    'Unreadable saved color details block shared and pigment-only estimates',
    () {
      for (final breed in [
        'Tan',
        'Dutch',
        'Mini Rex',
        'Dwarf Hotot',
        'Blanc de Hotot',
      ]) {
        final good = animal('good', breed, 'Black', 'M');
        for (final details in [
          'Black',
          '',
          42,
          ['Black'],
        ]) {
          final bad = {...good, 'color_details': details};
          final before = jsonEncode(bad);
          expect(CoatRules.resolve(bad), isNull);
          if (HototColorRules.handles(breed)) {
            expect(
              HototColorRules.inputIssue(bad),
              contains('could not be read'),
            );
          }
          expect(
            RabbitColorPredictions.inputIssue(bad, good),
            contains('could not be read'),
          );
          expect(
            RabbitColorPredictions.inputIssue(good, bad),
            contains('could not be read'),
          );
          expect(
            () => RabbitColorPredictions.predict(sire: bad, dam: good),
            throwsArgumentError,
          );
          expect(jsonEncode(bad), before);
        }
        expect(
          RabbitColorPredictions.inputIssue({
            ...good,
            'color_details': null,
          }, good),
          isNull,
        );
        expect(
          RabbitColorPredictions.inputIssue({
            ...good,
            'color_details': <String, dynamic>{},
          }, good),
          isNull,
        );
      }
    },
  );
  test(
    'Incomplete, ambiguous and conflicting records explain why calculation is blocked',
    () {
      final good = animal('good', 'Mini Rex', 'Black', 'M');
      final examples = <Map<String, dynamic>, String>{
        {...good, 'variety': ''}: 'recorded variety',
        {...good, 'breed': ''}: 'recorded breed',
        {...good, 'variety': 'White'}: 'ruby-eyed or blue-eyed',
        {...good, 'variety': 'Broken Pattern'}: 'underlying color',
        {...good, 'variety': 'Self'}: 'color group',
        {
          ...good,
          'color_details': {'color': 'Blue'},
        }: 'conflicting',
      };
      for (final entry in examples.entries) {
        final before = jsonEncode(entry.key);
        expect(
          RabbitColorPredictions.inputIssue(entry.key, entry.key),
          contains(entry.value),
        );
        expect(
          () => RabbitColorPredictions.predict(sire: entry.key, dam: entry.key),
          throwsArgumentError,
        );
        expect(jsonEncode(entry.key), before);
      }
    },
  );
  testWidgets(
    'Selectors sort breed then variety then name and prioritize either selected breed',
    (tester) async {
      tester.view.physicalSize = const Size(700, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final animals = [
        for (final sex in ['M', 'F']) ...[
          animal('$sex-Tan', 'Tan', 'Black', sex),
          animal('$sex-Dutch-Z', 'Dutch', 'Blue', sex),
          animal('$sex-missing', '', 'Black', sex),
          animal('$sex-Dutch-A', 'Dutch', 'Black', sex),
          animal('$sex-Dutch-B', 'Dutch', 'Black', sex),
          animal('$sex-Beveren', 'Beveren', 'Blue', sex),
        ],
      ];
      final before = jsonEncode(animals);
      await tester.pumpWidget(form(animals));
      List<String> order(int index) => tester
          .widgetList<DropdownButton<String>>(
            find.byType(DropdownButton<String>),
          )
          .elementAt(index)
          .items!
          .map((i) => i.value!)
          .toList();
      expect(order(0), [
        'M-Beveren',
        'M-Dutch-A',
        'M-Dutch-B',
        'M-Dutch-Z',
        'M-Tan',
        'M-missing',
      ]);
      var selector = find.byType(DropdownButtonFormField<String>).first;
      await tester.ensureVisible(selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('M-Tan').last);
      await tester.pumpAndSettle();
      expect(order(1), [
        'F-Tan',
        'F-Beveren',
        'F-Dutch-A',
        'F-Dutch-B',
        'F-Dutch-Z',
        'F-missing',
      ]);
      selector = find.byType(DropdownButtonFormField<String>).last;
      await tester.ensureVisible(selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('F-Dutch-A').last);
      await tester.pumpAndSettle();
      expect(order(0), [
        'M-Dutch-A',
        'M-Dutch-B',
        'M-Dutch-Z',
        'M-Beveren',
        'M-Tan',
        'M-missing',
      ]);
      expect(find.text('Prediction unavailable'), findsOneWidget);
      expect(find.textContaining('support@ringmasterone.com'), findsOneWidget);
      expect(jsonEncode(animals), before);
      expect(tester.takeException(), isNull);
    },
  );
}
