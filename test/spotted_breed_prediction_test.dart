import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/genetics/coat_rules.dart';
import 'package:ringmaster_breeder/genetics/color_prediction.dart';
import 'package:ringmaster_breeder/genetics/spotted_breeds.dart';
import 'package:ringmaster_breeder/screens/genetics_screen.dart';

Map<String, dynamic> rabbit(
  String breed,
  String variety, {
  String? pattern,
  Map<String, String> extra = const {},
}) => {
  'species': 'rabbit',
  'breed': breed,
  'variety': variety,
  'status': 'active',
  if (pattern != null || extra.isNotEmpty)
    'color_details': {if (pattern != null) 'pattern': pattern, ...extra},
};
Map<String, (double, double)> markings(ColorPrediction p) => {
  for (final c in p.markings) c.label: (c.minimum, c.maximum),
};
const varieties = {
  'Checkered Giant': ['Black', 'Blue'],
  'English Spot': [
    'Black',
    'Blue',
    'Chocolate',
    'Lilac',
    'Tortoise',
    'Gray',
    'Gold',
  ],
  'Dwarf Papillon': ['Black', 'Blue', 'Chocolate', 'Lilac'],
  'Rhinelander': ['Black', 'Blue'],
};

void main() {
  test(
    'All 15 bare catalog colors retain unknown spotting rather than assuming a marked breed is spotted',
    () {
      var count = 0;
      for (final breed in varieties.entries) {
        for (final color in breed.value) {
          final r = rabbit(breed.key, color);
          final before = jsonEncode(r);
          final input = CoatRules.resolve(r)!;
          expect(input.loci['En']!.map((p) => p.key).toSet(), {
            'En/en',
            'en/en',
            'En/En',
          });
          final result = RabbitColorPredictions.predict(sire: r, dam: r);
          expect(markings(result), {
            'Unspotted': (0.0, 1.0),
            'Spotted': (0.0, 1.0),
            'Minimal marking (Charlie)': (0.0, 1.0),
          });
          expect(
            result.scope,
            contains('spotting is not recorded and remains unknown'),
          );
          expect(result.scope, contains('Exact spot placement'));
          expect(
            result.colors.any((c) => c.label.startsWith('Spotted ')),
            true,
          );
          expect(
            result.colors.any((c) => c.label.startsWith('Unspotted ')),
            true,
          );
          expect(jsonEncode(r), before);
          count++;
        }
      }
      expect(count, 15);
    },
  );

  test(
    'All nine known spotting crosses conserve probability; reciprocal crosses agree',
    () {
      const states = ['Solid', 'Spotted', 'Charlie'];
      // Rows and columns: en/en, En/en, En/En. State order: unspotted, spotted, Charlie.
      const expected = [
        [
          [1.0, 0.0, 0.0],
          [.5, .5, 0.0],
          [0.0, 1.0, 0.0],
        ],
        [
          [.5, .5, 0.0],
          [.25, .5, .25],
          [0.0, .5, .5],
        ],
        [
          [0.0, 1.0, 0.0],
          [0.0, .5, .5],
          [0.0, 0.0, 1.0],
        ],
      ];
      for (final breed in varieties.keys) {
        for (var i = 0; i < states.length; i++) {
          for (var j = 0; j < states.length; j++) {
            final s = rabbit(breed, 'Black', pattern: states[i]);
            final d = rabbit(breed, 'Black', pattern: states[j]);
            final result = RabbitColorPredictions.predict(sire: s, dam: d);
            expect(result.markings.map((c) => c.minimum), expected[i][j]);
            expect(result.markings.every((c) => c.minimum == c.maximum), true);
            expect(result.markings.fold(0.0, (sum, c) => sum + c.maximum), 1);
            expect(
              markings(result),
              markings(RabbitColorPredictions.predict(sire: d, dam: s)),
            );
          }
        }
      }
    },
  );

  test(
    'A known unspotted parent and an unknown parent do not invent a fixed ratio',
    () {
      final s = rabbit('Checkered Giant', 'Black', pattern: 'Solid');
      final d = rabbit('Checkered Giant', 'Blue');
      expect(markings(RabbitColorPredictions.predict(sire: s, dam: d)), {
        'Unspotted': (0.0, 1.0),
        'Spotted': (0.0, 1.0),
        'Minimal marking (Charlie)': (0.0, 0.0),
      });
      final normal = rabbit('Checkered Giant', 'Black', pattern: 'Spotted');
      expect(markings(RabbitColorPredictions.predict(sire: normal, dam: d)), {
        'Unspotted': (0.0, .5),
        'Spotted': (.5, .5),
        'Minimal marking (Charlie)': (0.0, .5),
      });
    },
  );

  test(
    'Rhinelander Black and Blue refer to brindled pigments, never plain self coats',
    () {
      for (final color in ['Black', 'Blue']) {
        final input = CoatRules.resolve(rabbit('Rhinelander', color))!;
        expect(input.family, 'harlequin');
        expect(input.loci['A']!.length, 6);
        expect(input.loci['E']!.map((p) => p.key).toSet(), {'ej/ej', 'e/ej'});
        expect(input.loci['B']!.every((p) => p.first == 'B'), true);
        if (color == 'Blue') expect(input.loci['D']!.single.key, 'd/d');
      }
      final result = RabbitColorPredictions.predict(
        sire: rabbit('Rhinelander', 'Black', pattern: 'Spotted'),
        dam: rabbit('Rhinelander', 'Black', pattern: 'Spotted'),
      );
      expect(
        result.colors.any(
          (c) => c.label == 'Spotted Harlequin family (black base)',
        ),
        true,
      );
      expect(result.colors.any((c) => c.label == 'Spotted Black'), false);
    },
  );

  test(
    'Papillon tortoise/tricolor require a color; qualifiers and detail conflicts are preserved',
    () {
      for (final label in [
        'Tortoise',
        'Tortoise Shell',
        'Tri Color',
        'Tricolor Group (COD)',
      ]) {
        expect(CoatRules.resolve(rabbit('Dwarf Papillon', label)), isNull);
        for (final base in ['Black', 'Blue', 'Chocolate', 'Lilac']) {
          final input = CoatRules.resolve(
            rabbit('Dwarf Papillon', label, extra: {'color': base}),
          )!;
          expect(
            input.family,
            label.startsWith('Tort') ? 'tortoise' : 'harlequin',
          );
          expect(input.loci['En']!.length, 3);
        }
      }
      final broken = rabbit('English Spot', 'Black (Broken)');
      expect(CoatRules.resolve(broken)!.loci['En']!.single.key, 'En/en');
      final charlie = rabbit(
        'Dwarf Papillon',
        'Charlie Chocolate',
        extra: {'color': 'Chocolate'},
      );
      expect(CoatRules.resolve(charlie)!.loci['En']!.single.key, 'En/En');
      expect(
        SpottedBreedRules.interpretationNote(charlie),
        contains('recorded Charlie'),
      );
      for (final r in [
        rabbit('English Spot', 'Black (Broken)', pattern: 'Solid'),
        rabbit(
          'English Spot',
          'Black',
          pattern: 'Spotted',
          extra: {'base_color': 'Chocolate'},
        ),
        rabbit(
          'Rhinelander',
          'Black',
          pattern: 'Spotted',
          extra: {'color': 'Blue'},
        ),
        rabbit(
          'Dwarf Papillon',
          'Tortoise',
          extra: {'color': 'Blue', 'base_color': 'Chocolate'},
        ),
        rabbit('Dwarf Papillon', 'Tri Color', extra: {'color': 'Black Magpie'}),
        rabbit('Checkered Giant', 'Black', pattern: 'Dutch'),
        rabbit('English Spot', 'Black', pattern: 'Checkered'),
        rabbit(
          'Dwarf Papillon',
          'Black',
          pattern: 'Spotted',
          extra: {'tipping': 'Silver'},
        ),
        rabbit('Silver Fox', 'Black', pattern: 'Spotted'),
      ]) {
        expect(CoatRules.resolve(r), isNull, reason: '$r');
        expect(
          RabbitColorPredictions.inputIssue(r, r),
          isNotNull,
          reason: '$r',
        );
      }
    },
  );

  testWidgets(
    'Spotted selection shows marking boxes and keeps missing evidence visible on mobile',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1400);
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
                    ...rabbit('Checkered Giant', 'Black', pattern: 'Spotted'),
                    'id': 'b',
                    'sex': 'M',
                    'name': 'Spotted Buck',
                  },
                  {
                    ...rabbit('Checkered Giant', 'Black', pattern: 'Spotted'),
                    'id': 'd',
                    'sex': 'F',
                    'name': 'Spotted Doe',
                  },
                  {
                    ...rabbit('Checkered Giant', 'Black'),
                    'id': 'u',
                    'sex': 'F',
                    'name': 'Unknown Doe',
                  },
                ],
              ),
            ),
          ),
        ),
      );
      for (final i in [0, 1]) {
        final field = find.byType(DropdownButtonFormField<String>).at(i);
        await tester.ensureVisible(field);
        await tester.tap(field);
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(i == 0 ? 'Spotted Buck' : 'Spotted Doe').last,
        );
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('See Possible Colors'));
      await tester.tap(find.text('See Possible Colors'));
      await tester.pumpAndSettle();
      expect(find.text('Spotting inheritance'), findsOneWidget);
      expect(find.text('Unspotted'), findsOneWidget);
      expect(find.text('Spotted'), findsOneWidget);
      expect(find.text('Minimal marking (Charlie)'), findsOneWidget);
      expect(find.text('25%'), findsNWidgets(2));
      expect(find.text('50%'), findsOneWidget);
      expect(find.textContaining('not guarantees'), findsWidgets);
      final doe = find.byType(DropdownButtonFormField<String>).last;
      await tester.ensureVisible(doe);
      await tester.tap(doe);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unknown Doe').last);
      await tester.pumpAndSettle();
      expect(find.text('Spotting inheritance'), findsNothing);
      expect(
        find.textContaining('spotting is not recorded and remains unknown'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('See Possible Colors'));
      await tester.tap(find.text('See Possible Colors'));
      await tester.pumpAndSettle();
      expect(find.text('Spotting inheritance'), findsOneWidget);
      expect(find.text('Unknown parent spotting'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
}
