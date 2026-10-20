import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/genetics/coat_rules.dart';
import 'package:ringmaster_breeder/genetics/color_prediction.dart';
import 'package:ringmaster_breeder/screens/genetics_screen.dart';

Map<String, dynamic> rabbit(
  String breed,
  String variety, {
  Map<String, String>? details,
}) => {
  'species': 'rabbit',
  'breed': breed,
  'variety': variety,
  if (details != null) 'color_details': details,
};
Map<String, (double, double)> chances(ColorPrediction p) => {
  for (final c in p.colors) c.label: (c.minimum, c.maximum),
};
const standardInterpretations = {
  'American Chinchilla': 'Chinchilla',
  'American Sable': 'Sable',
  'Blue Holicer': 'Blue',
  'Cinnamon': 'Black Tortoise',
  'Cinnimini (COD)': 'Black Tortoise',
  'Czech Frosty': 'Frosty',
  'Florida White': 'Ruby Eyed White',
  'Giant Chinchilla': 'Chinchilla',
  'Lilac': 'Lilac',
  'Mini Californian': 'Black Pointed White',
  'Standard Chinchilla': 'Chinchilla',
  'Thrianta': 'Red',
};
const formattingAliases = <(String, String), String>{
  ('Beveren', 'Chocolate (COD)'): 'Chocolate',
  ('Beveren', 'Lilac (COD)'): 'Lilac',
  ('Britannia Petite', 'Chinchilla (COD)'): 'Chinchilla',
  ('Mini Satin', 'Sable Marten (COD)'): 'Sable Marten',
  ('Mini Satin', 'Smoke Pearl Marten (COD)'): 'Smoke Pearl Marten',
  ('Netherland Dwarf', 'Black (Broken)'): 'Broken Black',
  ('Netherland Dwarf', 'Black Otter (Broken)'): 'Broken Black Otter',
  ('Netherland Dwarf', 'Chocolate (Charlie)'): 'Charlie Chocolate',
  ('Netherland Dwarf', 'Frosty (COD)'): 'Frosty',
  ('Polish', 'Otter (COD)'): 'Otter',
  ('Rex', 'Fawn (COD)'): 'Fawn',
  ('Rex', 'Smoke Pearl (COD)'): 'Smoke Pearl',
};

void main() {
  test(
    'All 12 breed-specific Standard labels match their documented conditional color interpretation',
    () {
      expect(standardInterpretations.length, 12);
      for (final mapping in standardInterpretations.entries) {
        final standard = rabbit(mapping.key, 'Standard');
        final named = rabbit(mapping.key, mapping.value);
        expect(
          RabbitColorPredictions.inputIssue(standard, named),
          isNull,
          reason: mapping.key,
        );
        for (final carrier in CarrierKnowledge.values) {
          final evidence = ColorCarrierDetails(
            chocolate: carrier,
            dilute: carrier,
            tortoise: carrier,
          );
          final original = RabbitColorPredictions.predict(
            sire: named,
            dam: named,
            sireCarriers: evidence,
            damCarriers: evidence,
          );
          final aliased = RabbitColorPredictions.predict(
            sire: standard,
            dam: named,
            sireCarriers: evidence,
            damCarriers: evidence,
          );
          expect(chances(aliased), chances(original), reason: mapping.key);
          expect(aliased.scenarioCount, original.scenarioCount);
          expect(aliased.scope, contains('Standard is interpreted as'));
        }
      }
    },
  );

  test(
    'All 12 formatting aliases preserve chances, carriers and pattern states',
    () {
      expect(formattingAliases.length, 12);
      for (final entry in formattingAliases.entries) {
        final aliased = rabbit(entry.key.$1, entry.key.$2);
        final canonical = rabbit(entry.key.$1, entry.value);
        final a = RabbitColorPredictions.predict(sire: aliased, dam: canonical);
        final b = RabbitColorPredictions.predict(
          sire: canonical,
          dam: canonical,
        );
        expect(chances(a), chances(b), reason: '${entry.key}');
        expect(a.scenarioCount, b.scenarioCount);
        expect(
          RabbitColorPredictions.carrierLoci(aliased),
          RabbitColorPredictions.carrierLoci(canonical),
        );
        expect(
          chances(
            RabbitColorPredictions.predict(sire: canonical, dam: aliased),
          ),
          chances(b),
        );
      }
      expect(
        CoatRules.resolve(
          rabbit('Netherland Dwarf', 'Black Otter (Broken)'),
        )!.loci['En']!.single.key,
        'En/en',
      );
      expect(
        CoatRules.resolve(
          rabbit('Netherland Dwarf', 'Chocolate (Charlie)'),
        )!.loci['En']!.single.key,
        'En/En',
      );
    },
  );

  test(
    'New Standard interpretations keep observed phenotype facts and masked loci separate',
    () {
      for (final breed in [
        'American Chinchilla',
        'Giant Chinchilla',
        'Standard Chinchilla',
      ]) {
        final chin = CoatRules.resolve(rabbit(breed, 'Standard'))!;
        expect(chin.loci['A']!.every((p) => p.first == 'A'), true);
        expect(chin.loci['C']!.every((p) => p.first == 'cchd'), true);
      }
      final blue = CoatRules.resolve(rabbit('Blue Holicer', 'Standard'))!;
      expect(blue.loci['D']!.single.key, 'd/d');
      final cinnamon = CoatRules.resolve(rabbit('Cinnamon', 'Standard'))!;
      expect(cinnamon.loci['A']!.single.key, 'a/a');
      expect(cinnamon.loci['E']!.single.key, 'e/e');
      expect(cinnamon.loci['B']!.every((p) => p.first == 'B'), true);
      expect(
        CoatRules.resolve(
          rabbit('Cinnamon', 'Cinnamon'),
        )!.loci['A']!.single.key,
        'a/a',
      );
      final agouti = CoatRules.resolve(rabbit('Mini Rex', 'Cinnamon'))!;
      expect(agouti.loci['A']!.every((p) => p.first == 'A'), true);
      expect(agouti.loci['B']!.single.key, 'b/b');
      final frosty = CoatRules.resolve(rabbit('Czech Frosty', 'Standard'))!;
      expect(frosty.loci['E']!.single.key, 'e/e');
      final white = CoatRules.resolve(rabbit('Florida White', 'Standard'))!;
      expect(white.loci['C']!.single.key, 'c/c');
      expect(white.loci['A']!.length, 6);
      expect(white.loci['B']!.length, 3);
      final pointed = CoatRules.resolve(
        rabbit('Mini Californian', 'Standard'),
      )!;
      expect(pointed.loci['C']!.every((p) => p.first == 'ch'), true);
      expect(pointed.loci['A']!.length, 6);
      expect(pointed.loci['E']!.length, allCoatPairs('E').length);
      final red = CoatRules.resolve(rabbit('Thrianta', 'Standard'))!;
      expect(red.loci['E']!.single.key, 'e/e');
    },
  );

  test(
    'Aliases never override contradictory details, unsupported special breeds or unknown Standard labels',
    () {
      for (final details in [
        {'pattern': 'Solid'},
        {'pattern': 'Charlie'},
        {'color': 'Chocolate'},
      ]) {
        expect(
          CoatRules.resolve(
            rabbit('Netherland Dwarf', 'Black (Broken)', details: details),
          ),
          isNull,
        );
      }
      expect(
        CoatRules.resolve(
          rabbit('Florida White', 'Standard', details: {'eye_color': 'Blue'}),
        ),
        isNull,
      );
      expect(
        CoatRules.resolve(
          rabbit('Cinnamon', 'Standard', details: {'color': 'Cinnamon'}),
        ),
        isNotNull,
      );
      expect(
        CoatRules.resolve(
          rabbit(
            'Florida White',
            'Standard',
            details: {'color': 'White', 'eye_color': 'Red'},
          ),
        ),
        isNotNull,
      );
      expect(CoatRules.resolve(rabbit('Unknown breed', 'Standard')), isNull);
      for (final breed in ['Argenté St. Hubert (COD)', "Creme d’Argente"]) {
        final r = rabbit(breed, 'Black (COD)');
        expect(
          RabbitColorPredictions.inputIssue(r, r),
          isNotNull,
          reason: breed,
        );
      }
      expect(
        CoatRules.resolve(
          rabbit(
            'Netherland Dwarf',
            'Black (Broken)',
            details: {'color': 'Black (Broken)'},
          ),
        ),
        isNotNull,
      );
      expect(
        CoatRules.resolve(
          rabbit(
            'Netherland Dwarf',
            'Black (Broken)',
            details: {'color': 'Black'},
          ),
        ),
        isNotNull,
      );
      final unknown = rabbit('Rex', 'Unreviewed color (COD)');
      expect(RabbitColorPredictions.inputIssue(unknown, unknown), isNotNull);
    },
  );

  test('Interpretations never mutate source records or their saved labels', () {
    final sire = rabbit('Lilac', 'Standard', details: {'color': 'Lilac'});
    final dam = rabbit('Lilac', 'Lilac');
    final before = jsonEncode([sire, dam]);
    final prediction = RabbitColorPredictions.predict(sire: sire, dam: dam);
    expect(
      prediction.colors
          .where((c) => c.swatch != 'white')
          .every((c) => c.swatch == 'lilac'),
      true,
    );
    expect(prediction.hasRanges, true);
    expect(chances(prediction)['White (eye color not predicted)'], (0, .4375));
    expect(jsonEncode([sire, dam]), before);
  });

  testWidgets(
    'Standard parents retain their label and show the interpretation with results on mobile',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GeneticsPreviewForm(
                animals: [
                  {
                    ...rabbit('Lilac', 'Standard'),
                    'id': 'buck',
                    'name': 'Buck',
                    'sex': 'M',
                    'status': 'active',
                  },
                  {
                    ...rabbit('Lilac', 'Standard'),
                    'id': 'doe',
                    'name': 'Doe',
                    'sex': 'F',
                    'status': 'active',
                  },
                ],
              ),
            ),
          ),
        ),
      );
      for (final index in [0, 1]) {
        final field = find.byType(DropdownButtonFormField<String>).at(index);
        await tester.ensureVisible(field);
        await tester.tap(field);
        await tester.pumpAndSettle();
        await tester.tap(find.text(index == 0 ? 'Buck' : 'Doe').last);
        await tester.pumpAndSettle();
      }
      expect(find.text('Breed: Lilac • Variety: Standard'), findsNWidgets(2));
      expect(
        find.textContaining('Standard is interpreted as lilac'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('See Possible Colors'));
      await tester.tap(find.text('See Possible Colors'));
      await tester.pumpAndSettle();
      expect(find.text('Lilac coat-color estimates'), findsOneWidget);
      expect(find.text('Lilac'), findsOneWidget);
      expect(
        find.textContaining('Standard is interpreted as lilac'),
        findsNWidgets(2),
      );
      expect(find.text('Prediction unavailable'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
