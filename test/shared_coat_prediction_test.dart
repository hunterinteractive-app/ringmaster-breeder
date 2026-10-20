import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/genetics/coat_rules.dart';
import 'package:ringmaster_breeder/genetics/coat_solver.dart';
import 'package:ringmaster_breeder/genetics/color_prediction.dart';
import 'package:ringmaster_breeder/genetics/mendelian.dart';
import 'package:ringmaster_breeder/widgets/genetics_prediction_results.dart';
import 'package:ringmaster_breeder/screens/genetics_screen.dart';

Map<String, dynamic> rabbit(
  String variety, {
  String breed = 'Mini Rex',
  Map<String, String>? details,
}) => {
  'species': 'rabbit',
  'breed': breed,
  'variety': variety,
  if (details != null) 'color_details': details,
};
CoatInput exact(Map<String, AllelePair> changes) => CoatInput('known genes', {
  'A': [const AllelePair('a', 'a')],
  'B': [const AllelePair('B', 'B')],
  'C': [const AllelePair('C', 'C')],
  'D': [const AllelePair('D', 'D')],
  'E': [const AllelePair('E', 'E')],
  'En': [const AllelePair('en', 'en')],
  'V': [const AllelePair('V', 'V')],
  for (final e in changes.entries) e.key: [e.value],
}, 'test');
Map<String, (double, double)> bounds(SharedCoatPrediction prediction) => {
  for (final c in prediction.colors) c.outcome.label: (c.minimum, c.maximum),
};
bool matches(CoatEvent event, Map<String, AllelePair> genes) => event
    .classes
    .entries
    .every((e) => e.value.contains(coatClass(e.key, genes[e.key]!)));

void main() {
  test(
    'Offspring events partition every modeled phenotype class exactly once',
    () {
      final representatives = <String, Map<String, AllelePair>>{};
      for (final locus in coatDomains.keys) {
        representatives[locus] = {
          for (final pair in allCoatPairs(locus)) coatClass(locus, pair): pair,
        };
      }
      final events = coatEvents();
      expect(
        events.map((e) => e.outcome.label).toSet().length,
        events.length - 1,
      );
      var checked = 0;
      void visit(int index, Map<String, AllelePair> genes) {
        final loci = coatDomains.keys.toList();
        if (index == loci.length) {
          expect(
            events.where((e) => matches(e, genes)).length,
            1,
            reason: genes.map((k, v) => MapEntry(k, v.key)).toString(),
          );
          checked++;
          return;
        }
        for (final pair in representatives[loci[index]]!.values) {
          visit(index + 1, {...genes, loci[index]: pair});
        }
      }

      visit(0, {});
      expect(checked, 1728);
    },
  );

  test('Known agouti/tan/self inheritance and steel masking', () {
    final mixed = solveCoats(
      exact({'A': const AllelePair('A', 'at')}),
      exact({'A': const AllelePair('at', 'a')}),
    );
    expect(bounds(mixed), {
      'Chestnut / castor / gray': (.5, .5),
      'Otter / tan pattern (black base)': (.5, .5),
    });
    final tan = solveCoats(
      exact({'A': const AllelePair('at', 'a')}),
      exact({'A': const AllelePair('at', 'a')}),
    );
    expect(bounds(tan), {
      'Otter / tan pattern (black base)': (.75, .75),
      'Black': (.25, .25),
    });
    final steel = solveCoats(
      exact({'E': const AllelePair('Es', 'Es')}),
      exact({}),
    );
    expect(bounds(steel), {'Black': (1, 1)});
  });

  test('White masking takes precedence and does not guess hidden colors', () {
    final rew = CoatRules.resolve(rabbit('Ruby Eyed White'))!;
    expect(rew.loci['A']!.length, 6);
    expect(rew.loci['B']!.length, 3);
    expect(bounds(solveCoats(rew, rew)), {
      'White (eye color not predicted)': (1, 1),
    });
    final cc = exact({'C': const AllelePair('c', 'c')});
    final full = exact({});
    expect(bounds(solveCoats(cc, full)), {'Black': (1, 1)});
    final carrier = exact({'C': const AllelePair('C', 'c')});
    expect(bounds(solveCoats(carrier, cc)), {
      'Black': (.5, .5),
      'White (eye color not predicted)': (.5, .5),
    });
    final vienna = exact({'V': const AllelePair('V', 'v')});
    expect(bounds(solveCoats(vienna, vienna)), {
      'Black': (.75, .75),
      'White (eye color not predicted)': (.25, .25),
    });
    final whiteCarriers = exact({
      'C': const AllelePair('C', 'c'),
      'V': const AllelePair('V', 'v'),
    });
    expect(bounds(solveCoats(whiteCarriers, whiteCarriers)), {
      'Black': (9 / 16, 9 / 16),
      'White (eye color not predicted)': (7 / 16, 7 / 16),
    });
    final both = exact({
      'V': const AllelePair('v', 'v'),
      'C': const AllelePair('c', 'c'),
    });
    expect(bounds(solveCoats(both, both)), {
      'White (eye color not predicted)': (1, 1),
    });
  });

  test('Broken × broken is 1:2:1; white masks all three spotting states', () {
    final broken = exact({'En': const AllelePair('En', 'en')});
    expect(bounds(solveCoats(broken, broken)), {
      'Black': (.25, .25),
      'Broken Black': (.5, .5),
      'Charlie-pattern Black': (.25, .25),
    });
    final whiteBroken = exact({
      'En': const AllelePair('En', 'en'),
      'C': const AllelePair('c', 'c'),
    });
    expect(bounds(solveCoats(whiteBroken, whiteBroken)), {
      'White (eye color not predicted)': (1, 1),
    });
  });

  test('Pointed, chinchilla, sable and non-extension inheritance', () {
    final pointed = exact({'C': const AllelePair('ch', 'c')});
    expect(bounds(solveCoats(pointed, pointed)), {
      'Himalayan / pointed white (black base)': (.75, .75),
      'White (eye color not predicted)': (.25, .25),
    });
    final chin = exact({
      'A': const AllelePair('A', 'A'),
      'C': const AllelePair('cchd', 'c'),
    });
    expect(bounds(solveCoats(chin, chin)), {
      'Chinchilla': (.75, .75),
      'White (eye color not predicted)': (.25, .25),
    });
    final sable = exact({'C': const AllelePair('cchl', 'c')});
    expect(bounds(solveCoats(sable, sable)), {
      'Seal family (black base)': (.25, .25),
      'Sable family (black base)': (.5, .5),
      'White (eye color not predicted)': (.25, .25),
    });
    final tort = exact({'E': const AllelePair('e', 'e')});
    expect(bounds(solveCoats(tort, tort)), {'Tortoise (black base)': (1, 1)});
    final orange = exact({
      'A': const AllelePair('A', 'A'),
      'E': const AllelePair('e', 'e'),
      'B': const AllelePair('b', 'b'),
    });
    expect(bounds(solveCoats(orange, orange)), {
      'Orange / red / fawn family': (1, 1),
    });
    final harlequin = exact({'E': const AllelePair('ej', 'e')});
    expect(bounds(solveCoats(harlequin, harlequin)), {
      'Harlequin family (black base)': (.75, .75),
      'Tortoise (black base)': (.25, .25),
    });
  });

  test(
    'Exact crosses conserve probability and agree with direct allele transmission',
    () {
      final rng = Random(781);
      final events = coatEvents();
      for (var i = 0; i < 50; i++) {
        CoatInput parent() => exact({
          for (final l in coatDomains.keys)
            l: allCoatPairs(l)[rng.nextInt(allCoatPairs(l).length)],
        });
        final s = parent(), d = parent();
        final solved = solveCoats(s, d);
        final expected = <String, double>{};
        final loci = coatDomains.keys.toList();
        void transmit(int index, Map<String, AllelePair> genes, double chance) {
          if (index == loci.length) {
            final label = events
                .singleWhere((e) => matches(e, genes))
                .outcome
                .label;
            expected.update(label, (p) => p + chance, ifAbsent: () => chance);
            return;
          }
          final l = loci[index];
          for (final child in inheritLocus(
            s.loci[l]!.single,
            d.loci[l]!.single,
          )) {
            transmit(index + 1, {
              ...genes,
              l: child.genotype,
            }, chance * child.probability);
          }
        }

        transmit(0, {}, 1);
        expect(
          solved.colors.fold(0.0, (sum, c) => sum + c.maximum),
          closeTo(1, 1e-10),
        );
        expect(bounds(solved), {
          for (final e in expected.entries) e.key: (e.value, e.value),
        });
        expect(bounds(solved), bounds(solveCoats(d, s)));
      }
    },
  );

  test(
    'Factored uncertainty bounds equal exhaustive parental scenario extrema',
    () {
      final parent = CoatInput('unknown', {
        ...exact({}).loci,
        'A': [const AllelePair('A', 'a'), const AllelePair('A', 'at')],
        'B': [const AllelePair('B', 'B'), const AllelePair('B', 'b')],
        'C': [const AllelePair('C', 'C'), const AllelePair('C', 'c')],
        'E': [const AllelePair('E', 'E'), const AllelePair('E', 'e')],
        'V': [const AllelePair('V', 'V'), const AllelePair('V', 'v')],
      }, 'test');
      final possibilities = <CoatInput>[];
      final loci = coatDomains.keys.toList();
      void expand(int index, Map<String, AllelePair> genes) {
        if (index == loci.length) {
          possibilities.add(exact(genes));
          return;
        }
        for (final pair in parent.loci[loci[index]]!) {
          expand(index + 1, {...genes, loci[index]: pair});
        }
      }

      expand(0, {});
      final scenarios = [
        for (final s in possibilities)
          for (final d in possibilities) bounds(solveCoats(s, d)),
      ];
      final modeled = solveCoats(parent, parent);
      expect(modeled.scenarioCount, 1024);
      for (final c in modeled.colors) {
        final chances =
            scenarios.map((s) => s[c.outcome.label]?.$1 ?? 0).toList()..sort();
        expect(c.minimum, chances.first);
        expect(c.maximum, chances.last);
      }
    },
  );

  test(
    'Recorded colors resolve across breeds without pretending special patterns are self',
    () {
      for (final breed in [
        'Mini Rex',
        'Rex',
        'Holland Lop',
        'Jersey Wooly',
        'American Fuzzy Lop',
        'English Angora',
        'French Angora',
        'Satin Angora',
        'Netherland Dwarf',
        'Satin',
        'Mini Lop',
        'French Lop',
        'English Lop',
      ]) {
        for (final variety in [
          'Black',
          'Opal',
          'Chinchilla',
          'Broken Chocolate',
          'Ruby Eyed White',
          'Siamese Sable',
          'Black Otter',
          'Blue Tortoise Shell',
        ]) {
          final r = rabbit(variety, breed: breed);
          expect(
            RabbitColorPredictions.inputIssue(r, r),
            isNull,
            reason: '$breed $variety',
          );
          expect(
            RabbitColorPredictions.predict(sire: r, dam: r).colors,
            isNotEmpty,
          );
        }
      }
      expect(CoatRules.resolve(rabbit('White')), isNull);
      expect(
        CoatRules.resolve(
          rabbit('White', details: {'eye_color': 'Blue'}),
        )!.name,
        'Blue-eyed white',
      );
      expect(CoatRules.resolve(rabbit('Broken')), isNull);
      expect(
        CoatRules.resolve(
          rabbit('Broken', details: {'color': 'Black'}),
        )!.loci['En']!.single.key,
        'En/en',
      );
      expect(
        CoatRules.resolve(rabbit('Tri-Colored', details: {'color': 'Black'})),
        isNotNull,
      );
      expect(
        CoatRules.resolve(
          rabbit('Self Group - Black', breed: 'American Fuzzy Lop'),
        ),
        isNotNull,
      );
      expect(
        CoatRules.resolve(
          rabbit('Agouti', details: {'color': 'Black'}),
        )!.family,
        'agouti',
      );
      expect(
        CoatRules.resolve(rabbit('Shaded Group - Black', breed: 'English Lop')),
        isNull,
      );
      expect(CoatRules.resolve(rabbit('Black', breed: 'Dwarf Hotot')), isNull);
      expect(
        CoatRules.resolve(rabbit('Standard', breed: 'Silver Fox')),
        isNull,
      );
      expect(CoatRules.resolve(rabbit('Lynx', breed: 'Palomino')), isNull);
      expect(
        CoatRules.resolve(rabbit('Black', details: {'color': 'Chocolate'})),
        isNull,
      );
      expect(
        CoatRules.resolve(rabbit('Black', details: {'pattern': 'tortoise'})),
        isNull,
      );
      expect(
        CoatRules.resolve(
          rabbit('Ruby Eyed White', details: {'eye_color': 'Blue'}),
        ),
        isNull,
      );
      expect(
        CoatRules.resolve(rabbit('Black', details: {'tipping': 'Silver'})),
        isNull,
      );
    },
  );

  test(
    'Grouped and detailed colors must agree on their pattern and C/E facts',
    () {
      expect(
        CoatRules.resolve(rabbit('Shaded', details: {'color': 'Black'})),
        isNull,
      );
      expect(
        CoatRules.resolve(rabbit('Self', details: {'color': 'Black Otter'})),
        isNull,
      );
      expect(
        CoatRules.resolve(rabbit('Sable', details: {'color': 'Chinchilla'})),
        isNull,
      );
      expect(
        CoatRules.resolve(rabbit('Agouti', details: {'color': 'Chestnut'})),
        isNotNull,
      );
      expect(
        bounds(
          solveCoats(
            CoatRules.resolve(rabbit('Blue Eyed White'))!,
            CoatRules.resolve(rabbit('Blue Eyed White'))!,
          ),
        ),
        {'White (eye color not predicted)': (1, 1)},
      );
    },
  );

  testWidgets(
    'Shared selector flow calculates Opal without coverage dropdowns',
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
                    ...rabbit('Opal'),
                    'id': 'buck',
                    'name': 'Opal Buck',
                    'sex': 'M',
                    'status': 'active',
                  },
                  {
                    ...rabbit('Opal'),
                    'id': 'doe',
                    'name': 'Opal Doe',
                    'sex': 'F',
                    'status': 'active',
                  },
                  {
                    ...rabbit('Broken'),
                    'id': 'needs-color',
                    'name': 'Needs underlying color',
                    'sex': 'F',
                    'status': 'active',
                  },
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Available predictions'), findsNothing);
      expect(find.text('Your rabbits: prediction readiness'), findsNothing);
      expect(find.text('Prediction unavailable'), findsNothing);
      expect(find.textContaining('support@ringmasterone.com'), findsNothing);
      for (final i in [0, 1]) {
        final field = find.byType(DropdownButtonFormField<String>).at(i);
        await tester.ensureVisible(field);
        await tester.tap(field);
        await tester.pumpAndSettle();
        await tester.tap(find.text(i == 0 ? 'Opal Buck' : 'Opal Doe').last);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('See Possible Colors'));
      await tester.tap(find.text('See Possible Colors'));
      await tester.pumpAndSettle();
      expect(find.text('Mini Rex coat-color estimates'), findsOneWidget);
      expect(find.text('Opal'), findsOneWidget);
      expect(find.text('White (eye color not predicted)'), findsOneWidget);
      final doeField = find.byType(DropdownButtonFormField<String>).last;
      await tester.ensureVisible(doeField);
      await tester.tap(doeField);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Needs underlying color').last);
      await tester.pumpAndSettle();
      expect(find.text('Mini Rex coat-color estimates'), findsNothing);
      expect(find.text('Prediction unavailable'), findsOneWidget);
      expect(find.textContaining('needs its underlying color'), findsOneWidget);
      expect(find.textContaining('support@ringmasterone.com'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byWidgetPredicate((w) => w is FilledButton),
            )
            .onPressed,
        isNull,
      );
      // Returning to a supported pair clears the error and restores calculation.
      await tester.ensureVisible(doeField);
      await tester.tap(doeField);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Opal Doe').last);
      await tester.pumpAndSettle();
      expect(find.text('Prediction unavailable'), findsNothing);
      expect(find.textContaining('support@ringmasterone.com'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.byWidgetPredicate((w) => w is FilledButton),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Shared results keep boxes and readable white/pattern labels on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final r = rabbit('Ruby Eyed White');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GeneticsPredictionResults(
                prediction: RabbitColorPredictions.predict(sire: r, dam: r),
              ),
            ),
          ),
        ),
      );
      expect(find.text('White (eye color not predicted)'), findsOneWidget);
      expect(find.text('100%'), findsNWidgets(2)); // Card and scale endpoint.
      expect(find.textContaining('not guarantees'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
