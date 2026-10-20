import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/genetics/coat_rules.dart';
import 'package:ringmaster_breeder/genetics/coat_solver.dart';
import 'package:ringmaster_breeder/genetics/color_prediction.dart';
import 'package:ringmaster_breeder/genetics/mendelian.dart';
import '../tool/genetics_coverage_checklist.dart';

Map<String, dynamic> rabbit(String color, [Map<String, String>? details]) => {
  'species': 'rabbit',
  'breed': 'Dutch',
  'variety': color,
  if (details != null) 'color_details': details,
};
Map<String, (double, double)> ranges(ColorPrediction p) => {
  for (final c in p.colors) c.label: (c.minimum, c.maximum),
};
CoatInput exact(Map<String, List<AllelePair>> changes) =>
    CoatInput('test genes', {
      'A': [const AllelePair('a', 'a')],
      'B': [const AllelePair('B', 'B')],
      'C': [const AllelePair('C', 'c')],
      'D': [const AllelePair('D', 'D')],
      'E': [const AllelePair('E', 'E')],
      'V': [const AllelePair('V', 'v')],
      'En': allCoatPairs('En'),
      ...changes,
    }, 'test');

void main() {
  test(
    'All nine Dutch catalog colors calculate reciprocally without marking claims',
    () {
      const colors = [
        'Black',
        'Blue',
        'Chinchilla',
        'Chocolate',
        'Golden Yellow',
        'Gray',
        'Lilac',
        'Steel',
        'Tortoise',
      ];
      for (final sColor in colors) {
        final s = rabbit(sColor);
        final status = classifyChecklistEntry('Dutch', sColor);
        expect(status['status'], 'shared_estimate');
        expect(status['calculator_scope'], 'dutch_underlying_color');
        for (final dColor in colors) {
          final d = rabbit(dColor);
          final before = jsonEncode([s, d]);
          final p = RabbitColorPredictions.predict(sire: s, dam: d);
          expect(p.title, 'Dutch underlying-color estimates');
          expect(p.limitationTitle, 'Dutch markings are not predicted');
          expect(p.scope, contains('No Dutch marking genotype is inferred'));
          expect(p.limitation, contains('100% color-family'));
          expect(p.markings, isEmpty);
          expect(p.colors.every((c) => !c.broken), true);
          expect(
            ranges(p),
            ranges(RabbitColorPredictions.predict(sire: d, dam: s)),
          );
          expect(jsonEncode([s, d]), before);
        }
      }
    },
  );

  test(
    'Aliases, Dutch annotations and English spotting do not invent Dutch genes',
    () {
      const aliases = {
        'Tort': 'Tortoise',
        'Tortoiseshell': 'Tortoise',
        'Tortoise Shell': 'Tortoise',
        'Black Tort': 'Tortoise',
        'Tort. - Black': 'Tortoise',
        'Tort. - Blue': 'Blue Tortoise',
        'Tort. - Choc.': 'Chocolate Tortoise',
        'Tort. - Lilac': 'Lilac Tortoise',
        'Grey': 'Gray',
      };
      for (final e in aliases.entries) {
        final a = rabbit(e.key), b = rabbit(e.value);
        expect(
          ranges(RabbitColorPredictions.predict(sire: a, dam: a)),
          ranges(RabbitColorPredictions.predict(sire: b, dam: b)),
          reason: e.key,
        );
      }
      final plain = rabbit('Black');
      final expected = ranges(
        RabbitColorPredictions.predict(sire: plain, dam: plain),
      );
      for (final pattern in ['Dutch', 'Broken', 'Charlie', 'Solid']) {
        final parent = rabbit('Black', {'pattern': pattern});
        final parsed = CoatRules.resolve(parent)!;
        expect(parsed.loci.keys.any((k) => k.toLowerCase() == 'du'), false);
        expect(
          parsed.loci['En']!.length,
          ['Dutch', 'Solid'].contains(pattern) ? 3 : 1,
        );
        expect(
          ranges(RabbitColorPredictions.predict(sire: parent, dam: parent)),
          expected,
        );
      }
      final bad = rabbit('Black', {'base_color': 'Blue'});
      expect(
        () => RabbitColorPredictions.predict(sire: bad, dam: plain),
        throwsArgumentError,
      );
      final hotot = {...plain, 'breed': 'Dwarf Hotot'};
      expect(CoatRules.resolve(hotot), isNull);
      expect(
        RabbitColorPredictions.predict(sire: hotot, dam: hotot).title,
        contains('eye-band pigment'),
      );
    },
  );

  test(
    'Color-only events partition all 576 non-spotting phenotype classes',
    () {
      final loci = coatDomains.keys.where((l) => l != 'En').toList();
      final representatives = {
        for (final l in loci)
          l: {
            for (final p in allCoatPairs(l)) coatClass(l, p): p,
          }.values.toList(),
      };
      final events = coatEvents(includeSpotting: false);
      expect(events.every((e) => !e.classes.containsKey('En')), true);
      var checked = 0;
      void visit(int i, Map<String, AllelePair> genes) {
        if (i == loci.length) {
          expect(
            events
                .where(
                  (e) => e.classes.entries.every(
                    (f) => f.value.contains(coatClass(f.key, genes[f.key]!)),
                  ),
                )
                .length,
            1,
          );
          checked++;
          return;
        }
        for (final p in representatives[loci[i]]!) {
          visit(i + 1, {...genes, loci[i]: p});
        }
      }

      visit(0, {});
      expect(checked, 576);
    },
  );

  test(
    'Color marginal precedes extrema and overlapping white masks count once',
    () {
      final unknown = exact({});
      final p = solveCoats(unknown, unknown, includeSpotting: false);
      expect(
        {for (final c in p.colors) c.outcome.label: (c.minimum, c.maximum)},
        {
          'Black': (9 / 16, 9 / 16),
          'White (eye color not predicted)': (7 / 16, 7 / 16),
        },
      );
      expect(p.scenarioCount, 1);
      expect(p.colors.fold<double>(0, (sum, c) => sum + c.maximum), 1);
      for (final en in allCoatPairs('En')) {
        final parent = exact({
          'En': [en],
        });
        final separate = solveCoats(parent, parent);
        expect(
          separate.colors
              .where((c) => !c.outcome.white)
              .fold<double>(0, (sum, c) => sum + c.maximum),
          9 / 16,
        );
      }
    },
  );

  test(
    'Carrier edits narrow Dutch extension without fixing other hidden genes',
    () {
      final s = rabbit('Black'), d = rabbit('Tortoise');
      final no = RabbitColorPredictions.predict(
        sire: s,
        dam: d,
        sireCarriers: const ColorCarrierDetails(tortoise: CarrierKnowledge.no),
      );
      final yes = RabbitColorPredictions.predict(
        sire: s,
        dam: d,
        sireCarriers: const ColorCarrierDetails(tortoise: CarrierKnowledge.yes),
      );
      expect(no.colors.any((c) => c.tortoise), false);
      expect(yes.colors.any((c) => c.tortoise), true);
      expect(yes.hasRanges, true);
      expect(ranges(yes)['White (eye color not predicted)'], (0, 7 / 16));
      final gray = rabbit('Gray');
      expect(RabbitColorPredictions.carrierLoci(gray), contains('E'));
      final agouti = RabbitColorPredictions.predict(
        sire: gray,
        dam: gray,
        sireCarriers: const ColorCarrierDetails(tortoise: CarrierKnowledge.yes),
        damCarriers: const ColorCarrierDetails(tortoise: CarrierKnowledge.yes),
      );
      expect(ranges(agouti)['Orange / red / fawn family']!.$2, .25);
    },
  );
}
