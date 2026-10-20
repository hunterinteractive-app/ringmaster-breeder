import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/genetics/breed_color_contexts.dart';
import 'package:ringmaster_breeder/genetics/coat_rules.dart';
import 'package:ringmaster_breeder/genetics/color_prediction.dart';
import 'package:ringmaster_breeder/screens/genetics_screen.dart';
import '../tool/genetics_coverage_checklist.dart';

Map<String, dynamic> rabbit(
  String breed,
  String variety, [
  Map<String, String>? details,
]) => {
  'species': 'rabbit',
  'breed': breed,
  'variety': variety,
  if (details != null) 'color_details': details,
};
Map<String, (double, double)> colors(ColorPrediction p) => {
  for (final c in p.colors) c.label: (c.minimum, c.maximum),
};
const remaining = [
  ('English Angora', 'Pearl'),
  ('French Angora', 'Pearl'),
  ('Satin Angora', 'Pearl'),
  ('Flemish Giant', 'Sandy'),
  ('Flemish Giant', 'Steel Gray'),
  ('Rex', 'Brindle'),
  ('Mini Rex', 'Brindle'),
  ('Mini Rex', 'Tan'),
  ('Satin', 'Siamese'),
  ('Mini Satin', 'Siamese'),
  ('Netherland Dwarf', 'Lutino'),
  ('Palomino', 'Lynx'),
];
const bases = ['Black', 'Blue', 'Chocolate', 'Lilac'];

void main() {
  test('All twelve have bounded paths, ten require real saved details', () {
    expect(remaining, hasLength(12));
    var detailsRequired = 0;
    for (final (breed, variety) in remaining) {
      final raw = rabbit(breed, variety);
      final example = BreedColorContexts.detailExample(raw);
      final entry = classifyChecklistEntry(breed, variety);
      if (example != null) {
        detailsRequired++;
        expect(entry['status'], 'needs_details');
        expect(RabbitColorPredictions.inputIssue(raw, raw), isNotNull);
        expect(
          () => RabbitColorPredictions.predict(sire: raw, dam: raw),
          throwsArgumentError,
        );
      } else {
        expect(entry['status'], 'shared_estimate');
      }
      final r = {...raw, if (example != null) 'color_details': example};
      final before = jsonEncode(r);
      final p = RabbitColorPredictions.predict(sire: r, dam: r);
      expect(p.colors, isNotEmpty, reason: '$r');
      expect(p.limitation, isNotNull, reason: '$r');
      for (final c in p.colors) {
        expect(c.minimum, inInclusiveRange(0, 1));
        expect(c.maximum, inInclusiveRange(c.minimum, 1));
      }
      final other = rabbit(breed, 'Black');
      expect(
        colors(RabbitColorPredictions.predict(sire: r, dam: other)),
        colors(RabbitColorPredictions.predict(sire: other, dam: r)),
        reason: '$r',
      );
      expect(
        RabbitColorPredictions.predict(sire: other, dam: r).limitation,
        p.limitation,
      );
      expect(jsonEncode(r), before);
    }
    expect(detailsRequired, 10);
  });

  test(
    'Pearl pigment keeps a union of chinchilla and sable aa/ee backgrounds',
    () {
      for (final breed in ['English Angora', 'French Angora', 'Satin Angora']) {
        for (final base in bases) {
          final r = rabbit(breed, 'Pearl', {'color': base, 'pattern': 'Pearl'});
          final input = CoatRules.resolve(r)!;
          expect(input.family, 'pearl');
          expect(input.loci['A']!.single.key, 'a/a');
          expect(input.loci['E']!.single.key, 'e/e');
          expect(input.loci['C']!.map((p) => p.key).toSet(), {
            'cchd/cchd',
            'cchd/cchl',
            'cchd/ch',
            'c/cchd',
            'cchl/cchl',
            'cchl/ch',
            'c/cchl',
          });
          final p = RabbitColorPredictions.predict(sire: r, dam: r);
          expect(p.colors.any((c) => c.label.contains('Frosted-pearl')), false);
          expect(p.colors.any((c) => c.minimum != c.maximum), true);
          if (['Chocolate', 'Lilac'].contains(base)) {
            expect(input.loci['B']!.single.key, 'b/b');
          }
          if (['Blue', 'Lilac'].contains(base)) {
            expect(input.loci['D']!.single.key, 'd/d');
          }
          for (final (name, family, cAllele) in [
            ('$base Sallander', 'non-extension self chinchilla', 'cchd'),
            ('$base Sable Pearl', 'sable point', 'cchl'),
          ]) {
            final known = CoatRules.resolve(
              rabbit(breed, 'Pearl', {'color': name}),
            )!;
            expect(known.family, family);
            expect(known.loci['C']!.every((p) => p.first == cAllele), true);
            expect(known.loci['C']!.length, lessThan(input.loci['C']!.length));
          }
        }
      }
    },
  );

  test(
    'Siamese needs its actual shaded family, never pigment alone or Evans Lilac typo',
    () {
      for (final breed in ['Satin', 'Mini Satin']) {
        for (final base in bases) {
          expect(
            CoatRules.resolve(rabbit(breed, 'Siamese', {'color': base})),
            isNull,
          );
          for (final (suffix, family) in [
            ('Sallander', 'non-extension self chinchilla'),
            ('Sable Point', 'sable point'),
            ('Sable', 'sable'),
            ('Seal', 'seal'),
          ]) {
            final r = rabbit(breed, 'Siamese', {
              'color': '$base $suffix',
              'pattern': 'Siamese',
            });
            final genes = CoatRules.resolve(r)!;
            expect(genes.family, family);
            if (base == 'Lilac') {
              expect(genes.loci['B']!.single.key, 'b/b');
              expect(genes.loci['D']!.single.key, 'd/d');
            }
            expect(
              RabbitColorPredictions.predict(sire: r, dam: r).colors,
              isNotEmpty,
            );
          }
        }
      }
    },
  );

  test(
    'Brindle keeps ej candidates and unknown A without promising pattern distribution',
    () {
      for (final breed in ['Rex', 'Mini Rex']) {
        for (final base in bases) {
          final partner = ['Blue', 'Lilac'].contains(base) ? 'Fawn' : 'Orange';
          final r = rabbit(breed, 'Brindle', {
            'color': '$base/$partner',
            'pattern': 'Brindle',
          });
          final input = CoatRules.resolve(r)!;
          expect(input.family, 'harlequin');
          expect(input.loci['A'], hasLength(allCoatPairs('A').length));
          expect(input.loci['E']!.map((p) => p.key).toSet(), {'ej/ej', 'e/ej'});
          final p = RabbitColorPredictions.predict(sire: r, dam: r);
          expect(
            p.colors.any((c) => c.label.contains('Brindling color family')),
            true,
          );
          expect(
            p.colors.any((c) => c.label.contains('Harlequin family')),
            false,
          );
          expect(p.limitation, contains('not a guarantee'));
        }
      }
      expect(
        CoatRules.resolve(
          rabbit('Mini Rex', 'Brindle', {'color': 'Blue/Orange'}),
        ),
        isNull,
      );
    },
  );

  test(
    'Sandy and Steel Gray are conditional families without W or exact ticking',
    () {
      final sandy = CoatRules.resolve(rabbit('Flemish Giant', 'Sandy'))!;
      expect(sandy.family, 'agouti');
      expect(sandy.loci.containsKey('W'), false);
      final steel = rabbit('Flemish Giant', 'Steel Gray');
      final genes = CoatRules.resolve(steel)!;
      expect(genes.family, 'steel');
      expect(genes.loci['E']!.single.key, 'E/Es');
      expect(genes.loci['C']!.every((p) => p.first == 'cchd'), true);
      final p = RabbitColorPredictions.predict(sire: steel, dam: steel);
      expect(p.limitation, contains('two Steel copies (Es/Es)'));
      expect(p.limitation, contains('not the chance of visibly ticked'));
      expect(
        p.colors
            .where((c) => c.label.toLowerCase().contains('steel'))
            .every((c) => c.label.contains('may be masked')),
        true,
      );
      expect(CoatRules.resolve(rabbit('Mini Rex', 'Sandy')), isNull);
      expect(CoatRules.resolve(rabbit('Mini Rex', 'Steel Gray')), isNull);
    },
  );

  test(
    'Mini Rex Tan requires explicit pattern and pigment; Palomino does not borrow generic Lynx',
    () {
      for (final base in bases) {
        expect(
          CoatRules.resolve(rabbit('Mini Rex', 'Tan', {'color': base})),
          isNull,
        );
        final input = CoatRules.resolve(
          rabbit('Mini Rex', 'Tan', {'color': base, 'pattern': 'Tan'}),
        )!;
        expect(input.family, 'otter');
        expect(input.loci.containsKey('W'), false);
      }
      for (final details in [
        <String, String>{},
        {'color': 'Lynx'},
        {'color': 'Lilac Agouti'},
        {'color': 'Cream', 'pattern': 'Agouti'},
      ]) {
        expect(CoatRules.resolve(rabbit('Palomino', 'Lynx', details)), isNull);
      }
      final agouti = CoatRules.resolve(
        rabbit('Palomino', 'Lynx', {
          'color': 'Lilac Agouti',
          'pattern': 'Agouti',
        }),
      )!;
      expect(agouti.family, 'agouti');
      expect(agouti.loci['B']!.single.key, 'b/b');
      expect(agouti.loci['D']!.single.key, 'd/d');
      final cream = CoatRules.resolve(
        rabbit('Palomino', 'Lynx', {
          'color': 'Cream',
          'pattern': 'Non-extension',
        }),
      )!;
      expect(cream.family, 'orange');
      expect(cream.loci['E']!.single.key, 'e/e');
      expect(cream.loci['B'], hasLength(3));
    },
  );

  test(
    'Contradictory or unsupported metadata never replaces a recorded special color',
    () {
      for (final (breed, variety) in remaining) {
        final r = rabbit(breed, variety);
        final example =
            BreedColorContexts.detailExample(r) ?? <String, String>{};
        for (final addition in [
          {'base_color': 'Blue'},
          {'pattern': 'Dutch'},
          {'eye_color': 'Blue'},
          {'wideband': 'ww'},
        ]) {
          final invalid = {
            ...r,
            'color_details': {...example, ...addition},
          };
          final before = jsonEncode(invalid);
          expect(CoatRules.resolve(invalid), isNull, reason: '$invalid');
          expect(
            RabbitColorPredictions.inputIssue(invalid, invalid),
            isNotNull,
          );
          expect(jsonEncode(invalid), before);
        }
      }
    },
  );

  testWidgets(
    'Experimental Lutino and verification limits remain visible on mobile',
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
                    ...rabbit('Netherland Dwarf', 'Lutino', {
                      'color': 'Black',
                      'pattern': 'Self',
                    }),
                    'id': 'b',
                    'name': 'Buck',
                    'sex': 'M',
                    'status': 'active',
                  },
                  {
                    ...rabbit('Netherland Dwarf', 'Black'),
                    'id': 'd',
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
      for (final i in [0, 1]) {
        final selector = find.byType(DropdownButtonFormField<String>).at(i);
        await tester.ensureVisible(selector);
        await tester.tap(selector);
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining(i == 0 ? 'Buck' : 'Doe').last);
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('experimental, conditional'), findsOneWidget);
      final button = find.text('See Possible Colors');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text(BreedColorContexts.lutinoLimitation), findsOneWidget);
      expect(
        find.textContaining('experimental Lutino-family estimates'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
