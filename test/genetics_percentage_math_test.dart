import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/genetics/coat_rules.dart';
import 'package:ringmaster_breeder/genetics/coat_solver.dart';
import 'package:ringmaster_breeder/genetics/mendelian.dart';

import '../tool/genetics_percentage_oracle.dart';

CoatInput input(Genes genes) => CoatInput('Synthetic math check', {
  for (final e in genes.entries) e.key: [AllelePair(e.value[0], e.value[1])],
}, 'test');

void compareExact(Genes sire, Genes dam, {bool spotting = true}) {
  final expected = square(sire, dam, spotting: spotting);
  final actual = solveCoats(input(sire), input(dam), includeSpotting: spotting);
  expect(actual.scenarioCount, 1);
  expect({for (final c in actual.colors) c.outcome.label: c.maximum}, expected);
  expect(actual.colors.every((c) => c.minimum == c.maximum), true);
  expect(actual.colors.fold<double>(0, (sum, c) => sum + c.maximum), 1);
}

void main() {
  test(
    'All 397 modeled one-locus parent pairs transmit allele copies correctly',
    () {
      var checked = 0;
      for (final domain in coatDomains.values) {
        // Construct genotype pairs independently of allCoatPairs.
        final pairs = <List<String>>[
          for (var i = 0; i < domain.length; i++)
            for (var j = i; j < domain.length; j++) [domain[i], domain[j]],
        ];
        for (final sire in pairs) {
          for (final dam in pairs) {
            final expected = <String, double>{};
            for (var code = 0; code < 4; code++) {
              final key = ([sire[code ~/ 2], dam[code % 2]]..sort()).join('/');
              expected.update(key, (v) => v + .25, ifAbsent: () => .25);
            }
            final actual = inheritLocus(
              AllelePair(sire[0], sire[1]),
              AllelePair(dam[0], dam[1]),
            );
            expect({
              for (final p in actual) p.genotype.key: p.probability,
            }, expected);
            checked++;
          }
        }
      }
      expect(checked, 397);
    },
  );

  test(
    '243 fixed-background pigment crosses agree with independent complete squares',
    () {
      var checked = 0;
      for (final pattern in ['A', 'at', 'a']) {
        for (final sb in ['BB', 'Bb', 'bb']) {
          for (final sd in ['DD', 'Dd', 'dd']) {
            for (final db in ['BB', 'Bb', 'bb']) {
              for (final dd in ['DD', 'Dd', 'dd']) {
                compareExact(
                  known(pattern: pattern, b: sb, d: sd),
                  known(pattern: pattern, b: db, d: dd),
                );
                checked++;
              }
            }
          }
        }
      }
      expect(checked, 243);
    },
  );

  test(
    'White overlap, self, nonextension and spotting retain all offspring probability',
    () {
      final sire = {
        ...known(),
        'A': ['at', 'a'],
        'C': ['C', 'c'],
        'E': ['E', 'e'],
        'V': ['V', 'v'],
        'En': ['En', 'en'],
      };
      compareExact(sire, sire);
      final expected = square(sire, sire);
      expect(expected['White (eye color not predicted)'], 7 / 16);
      // Dutch excludes spotting classes before calculation; never discard and rescale.
      compareExact(sire, sire, spotting: false);
    },
  );

  test(
    'Unknown-gene extrema equal 64 independent complete parental squares',
    () {
      final base = known();
      final possibilities = <Genes>[
        for (final c in [
          ['C', 'C'],
          ['C', 'c'],
        ])
          for (final e in [
            ['E', 'E'],
            ['E', 'e'],
          ])
            for (final v in [
              ['V', 'V'],
              ['V', 'v'],
            ])
              {...base, 'C': c, 'E': e, 'V': v},
      ];
      final distributions = [
        for (final s in possibilities)
          for (final d in possibilities) square(s, d),
      ];
      final uncertain = CoatInput('Controlled unknowns', {
        ...input(base).loci,
        for (final l in ['C', 'E', 'V'])
          l: [
            AllelePair(base[l]![0], base[l]![1]),
            AllelePair(
              base[l]![0],
              l == 'C'
                  ? 'c'
                  : l == 'E'
                  ? 'e'
                  : 'v',
            ),
          ],
      }, 'test');
      final modeled = solveCoats(uncertain, uncertain);
      expect(modeled.scenarioCount, 64);
      final labels = distributions.expand((d) => d.keys).toSet();
      expect(modeled.colors.map((c) => c.outcome.label).toSet(), labels);
      for (final color in modeled.colors) {
        final values =
            distributions.map((d) => d[color.outcome.label] ?? 0).toList()
              ..sort();
        expect(color.minimum, values.first);
        expect(color.maximum, values.last);
      }
      expect(modeled.colors.singleWhere((c) => c.outcome.white).minimum, 0);
      expect(
        modeled.colors.singleWhere((c) => c.outcome.white).maximum,
        7 / 16,
      );
    },
  );
}
