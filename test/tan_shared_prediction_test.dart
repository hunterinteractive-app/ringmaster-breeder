import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/genetics/coat_rules.dart';
import 'package:ringmaster_breeder/genetics/coat_solver.dart';
import 'package:ringmaster_breeder/genetics/color_prediction.dart';
import 'package:ringmaster_breeder/genetics/mendelian.dart';
import '../tool/genetics_coverage_checklist.dart';

Map<String, dynamic> tan(String color, [Map<String, String>? details]) => {
  'species': 'rabbit',
  'breed': 'Tan',
  'variety': color,
  if (details != null) 'color_details': details,
};
Map<String, (double, double)> ranges(ColorPrediction p) => {
  for (final c in p.colors) c.label: (c.minimum, c.maximum),
};
CoatInput exactTan({
  bool selfCarrier = false,
  bool whiteCarriers = false,
  bool pigmentCarriers = false,
}) => CoatInput('explicit test genes', {
  'A': [AllelePair('at', selfCarrier ? 'a' : 'at')],
  'B': [AllelePair('B', pigmentCarriers ? 'b' : 'B')],
  'C': [AllelePair('C', whiteCarriers ? 'c' : 'C')],
  'D': [AllelePair('D', pigmentCarriers ? 'd' : 'D')],
  'E': [const AllelePair('E', 'E')],
  'En': [const AllelePair('en', 'en')],
  'V': [AllelePair('V', whiteCarriers ? 'v' : 'V')],
}, 'otter');
void main() {
  test(
    'All four Tan varieties use shared unknowns, retain labels and calculate reciprocally',
    () {
      for (final sColor in ['Black', 'Blue', 'Chocolate', 'Lilac']) {
        final s = tan(sColor);
        final genes = CoatRules.resolve(s)!;
        expect(genes.family, 'otter');
        expect(genes.loci['A']!.map((p) => p.key).toSet(), {'at/at', 'a/at'});
        expect(genes.loci['C']!.length, 5);
        expect(genes.loci['V']!.length, 2);
        expect(genes.loci['E']!.map((p) => p.key).toSet(), {
          'E/E',
          'E/ej',
          'E/e',
        });
        expect(
          classifyChecklistEntry('Tan', sColor)['status'],
          'shared_estimate',
        );
        for (final dColor in ['Black', 'Blue', 'Chocolate', 'Lilac']) {
          final d = tan(dColor);
          final before = jsonEncode([s, d]);
          final p = RabbitColorPredictions.predict(sire: s, dam: d);
          expect(p.title, 'Tan coat-color estimates');
          expect(p.scope, contains('Tan coat model'));
          expect(p.limitation, contains('do not mean those genes are known'));
          expect(p.hasRanges, true);
          expect(
            ranges(p),
            ranges(RabbitColorPredictions.predict(sire: d, dam: s)),
          );
          expect(ranges(p)['White (eye color not predicted)'], (0, .4375));
          for (final c in p.colors) {
            expect(c.minimum, inInclusiveRange(0, 1));
            expect(c.maximum, inInclusiveRange(c.minimum, 1));
          }
          expect(jsonEncode([s, d]), before);
        }
      }
    },
  );
  test(
    'Exact Tan-pattern genes with hidden self and two white factors conserve probability',
    () {
      final input = exactTan(selfCarrier: true, whiteCarriers: true);
      final p = solveCoats(input, input);
      final actual = {for (final c in p.colors) c.outcome.label: c.maximum};
      expect(actual, {
        'Otter / tan pattern (black base)': 27 / 64,
        'Black': 9 / 64,
        'White (eye color not predicted)': 7 / 16,
      });
      expect(actual.values.reduce((a, b) => a + b), 1);
      final public = ranges(
        RabbitColorPredictions.predict(sire: tan('Black'), dam: tan('Black')),
      );
      for (final e in actual.entries) {
        expect(e.value, inInclusiveRange(public[e.key]!.$1, public[e.key]!.$2));
      }
    },
  );
  test(
    'The exact 9:3:3:1 pigment ratio requires explicit fixed background genes',
    () {
      final input = exactTan(pigmentCarriers: true);
      final p = solveCoats(input, input);
      final actual = {for (final c in p.colors) c.outcome.label: c.maximum};
      expect(actual, {
        'Otter / tan pattern (black base)': 9 / 16,
        'Otter / tan pattern (blue base)': 3 / 16,
        'Otter / tan pattern (chocolate base)': 3 / 16,
        'Otter / tan pattern (lilac base)': 1 / 16,
      });
      const carriers = ColorCarrierDetails(
        chocolate: CarrierKnowledge.yes,
        dilute: CarrierKnowledge.yes,
      );
      final public = RabbitColorPredictions.predict(
        sire: tan('Black'),
        dam: tan('Black'),
        sireCarriers: carriers,
        damCarriers: carriers,
      );
      expect(public.hasRanges, true);
      expect(public.scenarioCount, greaterThan(1));
      final bound = ranges(public);
      for (final e in actual.entries) {
        expect(e.value, inInclusiveRange(bound[e.key]!.$1, bound[e.key]!.$2));
      }
      expect(bound['White (eye color not predicted)'], (0, .4375));
      final restricted = RabbitColorPredictions.predictBaseColors(
        sire: tan('Black'),
        dam: tan('Black'),
        sireCarriers: carriers,
        damCarriers: carriers,
      );
      expect(
        restricted.scope,
        contains('assumes the offspring have Tan markings'),
      );
      expect(restricted.hasRanges, false);
    },
  );
  test(
    'Known carrier facts narrow only their loci; none turn a Lilac parent into black or remove hidden white',
    () {
      final lilac = tan('Lilac');
      const yes = ColorCarrierDetails(
        chocolate: CarrierKnowledge.yes,
        dilute: CarrierKnowledge.yes,
        tortoise: CarrierKnowledge.yes,
      );
      const no = ColorCarrierDetails(
        chocolate: CarrierKnowledge.no,
        dilute: CarrierKnowledge.no,
        tortoise: CarrierKnowledge.no,
      );
      final normal = RabbitColorPredictions.predict(sire: lilac, dam: lilac);
      final known = RabbitColorPredictions.predict(
        sire: lilac,
        dam: lilac,
        sireCarriers: yes,
        damCarriers: yes,
      );
      expect(
        known.colors
            .where((c) => c.swatch != 'white')
            .every((c) => c.swatch == 'lilac'),
        true,
      );
      expect(
        ranges(known)['White (eye color not predicted)'],
        ranges(normal)['White (eye color not predicted)'],
      );
      expect(
        known.colors.any((c) => c.label.startsWith('Fox / torted-otter')),
        true,
      );
      final noncarrier = RabbitColorPredictions.predict(
        sire: lilac,
        dam: lilac,
        sireCarriers: no,
        damCarriers: no,
      );
      expect(
        noncarrier.colors.any((c) => c.label.startsWith('Fox / torted-otter')),
        false,
      );
      expect(noncarrier.hasRanges, true);
      expect(RabbitColorPredictions.carrierLoci(tan('Black')), {
        'B',
        'D',
        'E',
        'c',
        'v',
        'a',
        'ej',
      });
      expect(RabbitColorPredictions.carrierLoci(lilac), {
        'E',
        'c',
        'v',
        'a',
        'ej',
      });
    },
  );
  test(
    'Migration keeps broken/details conflicts and restricted-model boundaries explicit',
    () {
      final broken = tan('Black', {'pattern': 'Broken'});
      expect(CoatRules.resolve(broken)!.loci['En']!.single.key, 'En/en');
      expect(
        RabbitColorPredictions.predict(
          sire: broken,
          dam: broken,
        ).colors.any((c) => c.broken),
        true,
      );
      for (final r in [
        tan('Black', {'color': 'Blue'}),
        tan('Black', {'pattern': 'Self'}),
        tan('Black', {'color': 'White'}),
        tan('Black', {'genotype': 'atat'}),
      ]) {
        expect(
          () => RabbitColorPredictions.predict(sire: r, dam: r),
          throwsArgumentError,
        );
      }
      expect(
        () =>
            RabbitColorPredictions.predictBaseColors(sire: broken, dam: broken),
        throwsArgumentError,
      );
      expect(
        () => RabbitColorPredictions.predictBaseColors(
          sire: tan('REW'),
          dam: tan('REW'),
        ),
        throwsArgumentError,
      );
    },
  );
}
