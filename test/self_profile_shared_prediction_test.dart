import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/genetics/coat_rules.dart';
import 'package:ringmaster_breeder/genetics/coat_solver.dart';
import 'package:ringmaster_breeder/genetics/color_prediction.dart';
import 'package:ringmaster_breeder/genetics/mendelian.dart';
import '../tool/genetics_coverage_checklist.dart';

Map<String, dynamic> rabbit(
  String breed,
  String color, [
  Map<String, String>? details,
]) => {
  'species': 'rabbit',
  'breed': breed,
  'variety': color,
  if (details != null) 'color_details': details,
};
Map<String, (double, double)> ranges(ColorPrediction p) => {
  for (final c in p.colors) c.label: (c.minimum, c.maximum),
};
void main() {
  test(
    'Four self-color profiles retain masked genes for every pigment pairing',
    () {
      for (final breed in ['Havana', 'Polish', 'Lilac', 'Beveren']) {
        for (final sColor in ['Black', 'Blue', 'Chocolate', 'Lilac']) {
          final s = rabbit(breed, sColor);
          final input = CoatRules.resolve(s)!;
          expect(input.loci['A']!.single.key, 'a/a');
          expect(input.loci['C']!.length, 5);
          expect(input.loci['V']!.length, 2);
          expect(input.loci['E']!.length, 7); // Self also masks steel.
          for (final dColor in ['Black', 'Blue', 'Chocolate', 'Lilac']) {
            final d = rabbit(breed, dColor);
            final before = jsonEncode([s, d]);
            final p = RabbitColorPredictions.predict(sire: s, dam: d);
            expect(p.title, '$breed coat-color estimates');
            expect(p.scope, contains('$breed coat model'));
            expect(p.hasRanges, true);
            expect(ranges(p)['White (eye color not predicted)'], (0, .4375));
            expect(
              ranges(p),
              ranges(RabbitColorPredictions.predict(sire: d, dam: s)),
            );
            expect(jsonEncode([s, d]), before);
          }
        }
      }
    },
  );
  test(
    'Exact dense black self genes with two hidden white factors give 9/16 color and 7/16 white',
    () {
      final input = CoatInput('explicit test genes', {
        'A': [const AllelePair('a', 'a')],
        'B': [const AllelePair('B', 'B')],
        'C': [const AllelePair('C', 'c')],
        'D': [const AllelePair('D', 'D')],
        'E': [const AllelePair('E', 'E')],
        'En': [const AllelePair('en', 'en')],
        'V': [const AllelePair('V', 'v')],
      }, 'self');
      final expected = solveCoats(input, input);
      expect(
        {for (final c in expected.colors) c.outcome.label: c.maximum},
        {'Black': 9 / 16, 'White (eye color not predicted)': 7 / 16},
      );
      const known = ColorCarrierDetails(
        chocolate: CarrierKnowledge.no,
        dilute: CarrierKnowledge.no,
        tortoise: CarrierKnowledge.no,
      );
      for (final breed in ['Havana', 'Polish', 'Lilac', 'Beveren']) {
        final parent = rabbit(breed, 'Black');
        final p = RabbitColorPredictions.predict(
          sire: parent,
          dam: parent,
          sireCarriers: known,
          damCarriers: known,
        );
        final bound = ranges(p);
        expect(p.hasRanges, true);
        for (final c in expected.colors) {
          expect(
            c.maximum,
            inInclusiveRange(
              bound[c.outcome.label]!.$1,
              bound[c.outcome.label]!.$2,
            ),
          );
        }
        expect(p.colors.any((c) => c.tortoise), false);
      }
    },
  );
  test(
    'Recessive pigment stays fixed, while carriers do not remove hidden white or filter nonstandard outcomes',
    () {
      const yes = ColorCarrierDetails(
        chocolate: CarrierKnowledge.yes,
        dilute: CarrierKnowledge.yes,
      );
      for (final breed in ['Havana', 'Polish', 'Lilac', 'Beveren']) {
        final r = rabbit(breed, 'Lilac');
        final p = RabbitColorPredictions.predict(
          sire: r,
          dam: r,
          sireCarriers: yes,
          damCarriers: yes,
        );
        expect(
          p.colors
              .where((c) => c.swatch != 'white')
              .every((c) => c.swatch == 'lilac'),
          true,
        );
        expect(p.hasRanges, true);
        expect(RabbitColorPredictions.carrierLoci(r), {'E', 'c', 'v', 'ej'});
      }
      final b = rabbit('Beveren', 'Black');
      final p = RabbitColorPredictions.predict(
        sire: b,
        dam: b,
        sireCarriers: yes,
        damCarriers: yes,
      );
      expect(ranges(p)['Chocolate']!.$2, 3 / 16);
      expect(ranges(p)['Lilac']!.$2, 1 / 16);
    },
  );
  test(
    'Catalog status, aliases, saved patterns and conflict checks survive migration',
    () {
      for (final (breed, color) in [
        ('Havana', 'Black'),
        ('Polish', 'Blue'),
        ('Lilac', 'Standard'),
        ('Beveren', 'Black'),
      ]) {
        expect(
          classifyChecklistEntry(breed, color)['status'],
          'shared_estimate',
        );
        final r = rabbit(breed, color, {'pattern': 'Broken'});
        expect(CoatRules.resolve(r)!.loci['En']!.single.key, 'En/en');
        expect(
          RabbitColorPredictions.predict(
            sire: r,
            dam: r,
          ).colors.any((c) => c.broken),
          true,
        );
        final bad = rabbit(breed, color, {
          'base_color': color == 'Blue' ? 'Black' : 'Blue',
        });
        expect(
          () => RabbitColorPredictions.predict(sire: bad, dam: bad),
          throwsArgumentError,
        );
      }
      final a = rabbit('Havanna', 'Black'), b = rabbit('Havana', 'Black');
      expect(
        ranges(RabbitColorPredictions.predict(sire: a, dam: b)),
        ranges(RabbitColorPredictions.predict(sire: b, dam: b)),
      );
      final lilac = rabbit('Lilac', 'Standard');
      expect(
        ranges(RabbitColorPredictions.predict(sire: lilac, dam: lilac)),
        ranges(
          RabbitColorPredictions.predict(
            sire: rabbit('Lilac', 'Lilac'),
            dam: rabbit('Lilac', 'Lilac'),
          ),
        ),
      );
      final hotot = rabbit('Dwarf Hotot', 'Black');
      expect(
        RabbitColorPredictions.predict(sire: hotot, dam: hotot).title,
        contains('eye-band pigment'),
      );
      expect(CoatRules.resolve(hotot), isNull);
    },
  );
}
