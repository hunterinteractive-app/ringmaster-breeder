import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/genetics/color_prediction.dart';
import 'package:ringmaster_breeder/screens/genetics_screen.dart';

Map<String, dynamic> rabbit(String breed, String variety) => {
  'species': 'rabbit',
  'breed': breed,
  'variety': variety,
};
Map<String, (double, double)> chances(ColorPrediction p) => {
  for (final c in p.colors) c.label: (c.minimum, c.maximum),
};
const nonCarrier = ColorCarrierDetails(
  chocolate: CarrierKnowledge.no,
  dilute: CarrierKnowledge.no,
  tortoise: CarrierKnowledge.no,
);

void main() {
  test('Each enabled breed has explicit input coverage and its own scope', () {
    final expected = {
      'Tan': ['Black', 'Blue', 'Chocolate', 'Lilac'],
      'Havana': ['Black', 'Blue', 'Chocolate', 'Lilac'],
      'Polish': ['Black', 'Blue', 'Chocolate', 'Lilac'],
      'Lilac': ['Lilac'],
      'Beveren': ['Black', 'Blue'],
      'Dwarf Hotot': ['Black', 'Blue', 'Chocolate', 'Lilac'],
      'Blanc de Hotot': ['Standard', 'Black', 'Blue', 'Chocolate', 'Lilac'],
      'Dutch': [
        'Black',
        'Blue',
        'Chocolate',
        'Lilac',
        'Tortoise',
        'Blue Tort',
        'Chocolate Tort',
        'Lilac Tort',
      ],
    };
    expect(RabbitColorPredictions.profiles.length, expected.length);
    for (final breed in expected.entries) {
      for (final variety in breed.value) {
        final p = RabbitColorPredictions.predict(
          sire: rabbit(breed.key, variety),
          dam: rabbit(breed.key, variety),
        );
        expect(p.title, startsWith(breed.key));
        expect(p.scope, contains(breed.key));
        expect(p.colors, isNotEmpty);
      }
    }
    expect(
      RabbitColorPredictions.inputIssue(
        rabbit('Havanna', 'Black'),
        rabbit(' HAVANA ', ' chocolate '),
      ),
      isNull,
    );
    expect(
      RabbitColorPredictions.inputIssue(
        rabbit('Beveren', 'Chocolate'),
        rabbit('Beveren', 'Black'),
      ),
      isNull,
    );
    expect(
      RabbitColorPredictions.inputIssue(
        rabbit('Lilac', 'Black'),
        rabbit('Lilac', 'Lilac'),
      ),
      isNull,
    );
  });

  test(
    'Explicit restricted self-color profiles use independently tested B/D transmission',
    () {
      for (final breed in ['Havana', 'Polish']) {
        final p = RabbitColorPredictions.predictBaseColors(
          sire: rabbit(breed, 'Lilac'),
          dam: rabbit(breed, 'Chocolate'),
        );
        expect(chances(p), {'Chocolate': (.5, 1.0), 'Lilac': (0.0, .5)});
        expect(p.colors.every((c) => !c.tortoise), isTrue);
      }
      final lilac = RabbitColorPredictions.predictBaseColors(
        sire: rabbit('Lilac', 'Lilac'),
        dam: rabbit('Lilac', 'Lilac'),
      );
      expect(chances(lilac), {'Lilac': (1.0, 1.0)});
    },
  );

  test('Possible outputs are not filtered to a breed show standard', () {
    const carriers = ColorCarrierDetails(
      chocolate: CarrierKnowledge.yes,
      dilute: CarrierKnowledge.no,
    );
    final p = RabbitColorPredictions.predictBaseColors(
      sire: rabbit('Beveren', 'Black'),
      dam: rabbit('Beveren', 'Black'),
      sireCarriers: carriers,
      damCarriers: carriers,
    );
    expect(chances(p), {'Black': (.75, .75), 'Chocolate': (.25, .25)});
  });

  test(
    'Restricted Dutch normal × tortoise depends on the normal parent’s hidden e',
    () {
      final sire = rabbit('Dutch', 'Chocolate'),
          dam = rabbit('Dutch', 'Tortoise');
      const damCarriers = ColorCarrierDetails(
        chocolate: CarrierKnowledge.yes,
        dilute: CarrierKnowledge.no,
      );
      final unknown = RabbitColorPredictions.predictBaseColors(
        sire: sire,
        dam: dam,
        sireCarriers: const ColorCarrierDetails(dilute: CarrierKnowledge.no),
        damCarriers: damCarriers,
      );
      expect(chances(unknown), {
        'Black': (.25, .5),
        'Chocolate': (.25, .5),
        'Tortoise (black base)': (0.0, .25),
        'Tortoise (chocolate base)': (0.0, .25),
      });
      final carrier = RabbitColorPredictions.predictBaseColors(
        sire: sire,
        dam: dam,
        sireCarriers: nonCarrier.copyWith(tortoise: CarrierKnowledge.yes),
        damCarriers: damCarriers,
      );
      expect(chances(carrier), {
        'Black': (.25, .25),
        'Chocolate': (.25, .25),
        'Tortoise (black base)': (.25, .25),
        'Tortoise (chocolate base)': (.25, .25),
      });
      final noCarrier = RabbitColorPredictions.predictBaseColors(
        sire: sire,
        dam: dam,
        sireCarriers: nonCarrier,
        damCarriers: damCarriers,
      );
      expect(chances(noCarrier), {'Black': (.5, .5), 'Chocolate': (.5, .5)});
    },
  );

  test(
    'Restricted Dutch tortoise × tortoise only produces tortoise under fixed backgrounds',
    () {
      final p = RabbitColorPredictions.predictBaseColors(
        sire: rabbit('Dutch', 'Tortoise'),
        dam: rabbit('Dutch', 'Tortoise'),
      );
      expect(p.colors.every((c) => c.tortoise), isTrue);
      expect(chances(p)['Tortoise (black base)'], (.5625, 1.0));
      final lilac = RabbitColorPredictions.predictBaseColors(
        sire: rabbit('Dutch', 'Lilac Tort'),
        dam: rabbit('Dutch', 'Lilac Tort'),
      );
      expect(chances(lilac), {'Tortoise (lilac base)': (1.0, 1.0)});
    },
  );

  test(
    'All 27 exact B/D/E genotypes cross with conserved probability and reciprocity',
    () {
      final parents = <(Map<String, dynamic>, ColorCarrierDetails)>[];
      for (final b in ['BB', 'Bb', 'bb']) {
        for (final d in ['DD', 'Dd', 'dd']) {
          for (final e in ['EE', 'Ee', 'ee']) {
            final color = b == 'bb'
                ? (d == 'dd' ? 'Lilac' : 'Chocolate')
                : (d == 'dd' ? 'Blue' : 'Black');
            parents.add((
              rabbit('Dutch', e == 'ee' ? '$color Tort' : color),
              ColorCarrierDetails(
                chocolate: b == 'Bb'
                    ? CarrierKnowledge.yes
                    : CarrierKnowledge.no,
                dilute: d == 'Dd' ? CarrierKnowledge.yes : CarrierKnowledge.no,
                tortoise: e == 'Ee'
                    ? CarrierKnowledge.yes
                    : CarrierKnowledge.no,
              ),
            ));
          }
        }
      }
      for (final a in parents) {
        for (final b in parents) {
          final p = RabbitColorPredictions.predictBaseColors(
            sire: a.$1,
            dam: b.$1,
            sireCarriers: a.$2,
            damCarriers: b.$2,
          );
          final reverse = RabbitColorPredictions.predictBaseColors(
            sire: b.$1,
            dam: a.$1,
            sireCarriers: b.$2,
            damCarriers: a.$2,
          );
          expect(p.scenarioCount, 1);
          expect(p.hasRanges, isFalse);
          expect(
            p.colors.fold(0.0, (sum, c) => sum + c.maximum),
            closeTo(1, 1e-10),
          );
          expect(chances(p), chances(reverse));
        }
      }
    },
  );

  test(
    'Shared families extend the original profiles; ambiguous inputs still block',
    () {
      for (final breed in ['Havana', 'Polish', 'Lilac', 'Beveren', 'Dutch']) {
        for (final color in [
          'REW',
          'Blue Eyed White',
          'Broken Black',
          'Steel',
          'Chinchilla',
          'Golden Yellow',
        ]) {
          final r = rabbit(breed, color);
          expect(RabbitColorPredictions.inputIssue(r, r), isNull);
          expect(
            RabbitColorPredictions.predict(sire: r, dam: r).scope,
            contains('Shared rabbit coat model'),
          );
        }
        for (final color in ['Broken', 'Shaded', 'Unknown color', '']) {
          final r = rabbit(breed, color);
          expect(
            () => RabbitColorPredictions.predict(sire: r, dam: r),
            throwsArgumentError,
          );
        }
      }
      expect(
        RabbitColorPredictions.inputIssue(
          rabbit('Tan', 'Black'),
          rabbit('Dutch', 'Black'),
        ),
        contains('Mixed-breed'),
      );
      expect(
        RabbitColorPredictions.inputIssue({
          ...rabbit('Havana', 'Black'),
          'color_details': {'pattern': 'Broken'},
        }, rabbit('Havana', 'Black')),
        isNull,
      );
      expect(
        RabbitColorPredictions.inputIssue({
          ...rabbit('Dutch', 'Tortoise'),
          'color_details': {'pattern': 'Dutch', 'base_color': 'Black'},
        }, rabbit('Dutch', 'Black')),
        isNull,
      );
    },
  );

  testWidgets(
    'Dutch controls, model name and tortoise result render on narrow screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final animals = [
        {
          ...rabbit('Dutch', 'Lilac'),
          'id': 'buck',
          'name': 'Buck',
          'sex': 'M',
          'status': 'active',
        },
        {
          ...rabbit('Dutch', 'Lilac Tort'),
          'id': 'doe',
          'name': 'Doe',
          'sex': 'F',
          'status': 'active',
        },
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GeneticsPreviewForm(animals: animals),
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
      final optional = find.text('Optional: known carrier information');
      expect(optional, findsNWidgets(2));
      await tester.ensureVisible(optional.first);
      await tester.tap(optional.first);
      await tester.pumpAndSettle();
      expect(find.text('Carries non-extension (e)?'), findsOneWidget);
      expect(find.text('Carries chocolate?'), findsNothing);
      final calculate = find.text('See Possible Colors');
      await tester.ensureVisible(calculate);
      await tester.tap(calculate);
      await tester.pumpAndSettle();
      expect(find.text('Dutch underlying-color estimates'), findsOneWidget);
      expect(find.text('Tortoise (lilac base)'), findsOneWidget);
      expect(find.text('Dutch markings are not predicted'), findsOneWidget);
      expect(find.text('White (eye color not predicted)'), findsOneWidget);
      expect(find.text('Tan base-color estimates'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
