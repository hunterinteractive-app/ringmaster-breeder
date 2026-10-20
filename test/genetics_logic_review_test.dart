import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/genetics/coat_rules.dart';
import 'package:ringmaster_breeder/genetics/coat_solver.dart';
import 'package:ringmaster_breeder/genetics/color_prediction.dart';
import 'package:ringmaster_breeder/genetics/mendelian.dart';
import 'package:ringmaster_breeder/widgets/genetics_prediction_results.dart';

import '../tool/genetics_percentage_oracle.dart';

const auditDomains = {
  'A': ['A', 'at', 'a'],
  'B': ['B', 'b'],
  'C': ['C', 'cchd', 'cchl', 'ch', 'c'],
  'D': ['D', 'd'],
  'E': ['Es', 'E', 'ej', 'e'],
  'En': ['En', 'en'],
  'V': ['V', 'v'],
};

void main() {
  test(
    'Blue-eyed white cannot be albino cc but can carry c under Vienna white',
    () {
      const bew = {
        'species': 'rabbit',
        'breed': 'Mini Rex',
        'variety': 'Blue Eyed White',
      };
      const black = {
        'species': 'rabbit',
        'breed': 'Mini Rex',
        'variety': 'Black',
      };
      final input = CoatRules.resolve(bew)!;
      expect(input.loci['C']!.length, 14);
      expect(input.loci['C']!.any((p) => p.isRecessive('c')), false);
      expect(input.loci['C']!.any((p) => p.key == 'C/c'), true);
      expect(input.loci['V']!.single.isRecessive('v'), true);
      final prediction = RabbitColorPredictions.predict(sire: bew, dam: black);
      expect(
        prediction.scope,
        contains('modeled genes are inherited independently'),
      );
      final white = prediction.colors.singleWhere(
        (c) => c.label == 'White (eye color not predicted)',
      );
      // Most-white compatible case: C/c vv × C/c V/v. One quarter cc,
      // one half vv, and one eighth both: 1/4 + 1/2 - 1/8 = 5/8.
      // The old cc vv input wrongly raised this upper bound to 3/4.
      expect((white.minimum, white.maximum), (0, 5 / 8));
      final reverse = RabbitColorPredictions.predict(sire: black, dam: bew);
      expect(
        reverse.colors.map((c) => (c.label, c.minimum, c.maximum)).toList(),
        prediction.colors.map((c) => (c.label, c.minimum, c.maximum)).toList(),
      );
      final rew = CoatRules.resolve({...bew, 'variety': 'Ruby Eyed White'})!;
      expect(rew.loci['C']!.single.isRecessive('c'), true);
      // Albino parents may still hide vv, and two observed BEWs remain all-white.
      expect(rew.loci['V']!.any((p) => p.isRecessive('v')), true);
      final both = RabbitColorPredictions.predict(sire: bew, dam: bew);
      expect(both.colors.single.minimum, 1);
      expect(both.colors.single.maximum, 1);
      expect(RabbitColorPredictions.carrierLoci(bew), contains('c'));
    },
  );
  test(
    'Every three-locus uncertainty grouping agrees with independent complete squares',
    () {
      final random = Random(1941), loci = coatDomains.keys.toList();
      var groups = 0, squares = 0;
      for (var i = 0; i < loci.length; i++) {
        for (var j = i + 1; j < loci.length; j++) {
          for (var k = j + 1; k < loci.length; k++) {
            final varied = {loci[i], loci[j], loci[k]};
            Map<String, List<List<String>>> choices() => {
              for (final l in loci)
                l: (() {
                  final domain = auditDomains[l]!;
                  final allele = domain[random.nextInt(domain.length)];
                  if (!varied.contains(l)) {
                    return [
                      [allele, allele],
                    ];
                  }
                  final pairs = [
                    for (var a = 0; a < domain.length; a++)
                      for (var b = a; b < domain.length; b++)
                        [domain[a], domain[b]],
                  ]..shuffle(random);
                  return pairs.take(2).toList();
                })(),
            };
            final s = choices(), d = choices();
            List<Genes> expand(Map<String, List<List<String>>> options) {
              var rows = <Genes>[{}];
              for (final e in options.entries) {
                rows = [
                  for (final r in rows)
                    for (final pair in e.value) {...r, e.key: pair},
                ];
              }
              return rows;
            }

            CoatInput input(Map<String, List<List<String>>> options) =>
                CoatInput('Independent review case', {
                  for (final e in options.entries)
                    e.key: [for (final p in e.value) AllelePair(p[0], p[1])],
                }, 'test');
            final spotting = groups.isEven;
            final expected = [
              for (final sire in expand(s))
                for (final dam in expand(d))
                  square(sire, dam, spotting: spotting),
            ];
            squares += expected.length;
            final actual = solveCoats(
              input(s),
              input(d),
              includeSpotting: spotting,
            );
            final labels = expected.expand((e) => e.keys).toSet();
            expect(
              actual.colors.map((c) => c.outcome.label).toSet(),
              labels,
              reason: '$varied',
            );
            for (final c in actual.colors) {
              final chances =
                  expected.map((e) => e[c.outcome.label] ?? 0).toList()..sort();
              expect(
                c.minimum,
                chances.first,
                reason: '$varied: ${c.outcome.label} minimum',
              );
              expect(
                c.maximum,
                chances.last,
                reason: '$varied: ${c.outcome.label} maximum',
              );
            }
            expect(
              expected.every((e) => e.values.reduce((a, b) => a + b) == 1),
              true,
            );
            groups++;
          }
        }
      }
      expect(groups, 35);
      expect(squares, 2240);
    },
  );

  test(
    'All 2187 carrier combinations either narrow bounds or explain a conflict',
    () {
      const rabbit = {'species': 'rabbit', 'breed': 'Tan', 'variety': 'Black'};
      final original = RabbitColorPredictions.predict(
        sire: rabbit,
        dam: rabbit,
      );
      final baseline = {for (final c in original.colors) c.label: c};
      var valid = 0, conflicts = 0;
      for (var code = 0; code < 2187; code++) {
        var n = code;
        final states = <CarrierKnowledge>[];
        for (var i = 0; i < 7; i++) {
          states.add(CarrierKnowledge.values[n % 3]);
          n ~/= 3;
        }
        final facts = ColorCarrierDetails(
          chocolate: states[0],
          dilute: states[1],
          tortoise: states[2],
          albino: states[3],
          vienna: states[4],
          selfPattern: states[5],
          harlequin: states[6],
        );
        final issue = RabbitColorPredictions.carrierIssue(
          rabbit,
          rabbit,
          sireCarriers: facts,
        );
        if (states[2] == CarrierKnowledge.yes &&
            states[6] == CarrierKnowledge.yes) {
          expect(issue, contains('support@ringmasterone.com'));
          conflicts++;
          continue;
        }
        expect(issue, isNull);
        final prediction = RabbitColorPredictions.predict(
          sire: rabbit,
          dam: rabbit,
          sireCarriers: facts,
        );
        expect(
          prediction.scenarioCount,
          lessThanOrEqualTo(original.scenarioCount),
        );
        expect(
          prediction.colors.map((c) => c.label).toSet().length,
          prediction.colors.length,
        );
        for (final c in prediction.colors) {
          expect(c.minimum.isFinite && c.maximum.isFinite, true);
          expect(
            c.minimum,
            inInclusiveRange(baseline[c.label]!.minimum, c.maximum),
          );
          expect(c.maximum, lessThanOrEqualTo(baseline[c.label]!.maximum));
        }
        if (code % 100 == 0) {
          final reverse = RabbitColorPredictions.predict(
            sire: rabbit,
            dam: rabbit,
            damCarriers: facts,
          );
          expect(
            reverse.colors.map((c) => (c.label, c.minimum, c.maximum)).toList(),
            prediction.colors
                .map((c) => (c.label, c.minimum, c.maximum))
                .toList(),
          );
        }
        valid++;
      }
      expect(valid, 1944);
      expect(conflicts, 243);
    },
  );

  testWidgets(
    'Large result pages retain every outcome and reset for a new calculation',
    (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final result = RabbitColorPredictions.predict(
        sire: {
          'species': 'rabbit',
          'breed': 'Netherland Dwarf',
          'variety': 'Lutino',
          'color_details': {'color': 'Black', 'pattern': 'Self'},
        },
        dam: {
          'species': 'rabbit',
          'breed': 'Netherland Dwarf',
          'variety': 'Blue Eyed White',
        },
      );
      expect(result.colors.length, 397);
      final watch = Stopwatch()..start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GeneticsPredictionResults(prediction: result),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      watch.stop();
      // Diagnostic only: debug test rendering is not a device frame budget.
      debugPrint(
        '48-card first-page narrow-layout debug render: ${watch.elapsedMilliseconds} ms',
      );
      final seen = <String>{};
      for (var start = 0; start < result.colors.length; start += 48) {
        final end = (start + 48).clamp(0, result.colors.length);
        expect(
          find.textContaining('Showing colors ${start + 1}–$end of 397.'),
          findsOneWidget,
        );
        for (final c in result.colors.sublist(start, end)) {
          expect(find.text(c.label), findsOneWidget);
          seen.add(c.label);
        }
        expect(
          find.text('Color family • exact appearance varies').evaluate().length,
          lessThanOrEqualTo(48),
        );
        if (end < result.colors.length) {
          final next = find.text('Next colors');
          await tester.ensureVisible(next);
          await tester.tap(next);
          await tester.pumpAndSettle();
        }
      }
      expect(seen.length, 397);
      final nextButton = find.ancestor(
        of: find.text('Next colors'),
        matching: find.byWidgetPredicate((w) => w is OutlinedButton),
      );
      expect(tester.widget<OutlinedButton>(nextButton).onPressed, isNull);
      final previous = find.text('Previous colors');
      await tester.ensureVisible(previous);
      await tester.tap(previous);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Showing colors 337–384 of 397.'),
        findsOneWidget,
      );
      // Same result widget, new calculation: start from its first color again.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GeneticsPredictionResults(
                prediction: RabbitColorPredictions.predict(
                  sire: {
                    'species': 'rabbit',
                    'breed': 'Mini Rex',
                    'variety': 'Ruby Eyed White',
                  },
                  dam: {
                    'species': 'rabbit',
                    'breed': 'Mini Rex',
                    'variety': 'Blue Eyed White',
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Showing colors 1–48 of 286.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
