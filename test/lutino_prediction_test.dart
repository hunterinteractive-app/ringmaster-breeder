import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/genetics/coat_rules.dart';
import 'package:ringmaster_breeder/genetics/coat_solver.dart';
import 'package:ringmaster_breeder/genetics/color_prediction.dart';
import 'package:ringmaster_breeder/genetics/lutino_prediction.dart';
import 'package:ringmaster_breeder/genetics/mendelian.dart';

void main() {
  const black = SharedCoatPrediction([
    CoatEstimate(CoatOutcome('Black', 'black'), 1, 1),
  ], 1);
  const pairs = [
    AllelePair('P', 'P'),
    AllelePair('P', 'p'),
    AllelePair('p', 'p'),
  ];
  const expected = [
    [0.0, 0.0, 0.0],
    [0.0, 0.25, 0.5],
    [0.0, 0.5, 1.0],
  ];
  test(
    'All nine exact p-factor crosses conserve probability and are reciprocal',
    () {
      for (var i = 0; i < 3; i++) {
        for (var j = 0; j < 3; j++) {
          final p = LutinoPredictions.apply(black, [pairs[i]], [pairs[j]]);
          final modified = p.colors.where(
            (c) => c.outcome.label.startsWith('Lutino-'),
          );
          expect(
            modified.fold<double>(0, (sum, c) => sum + c.minimum),
            expected[i][j],
          );
          expect(p.colors.every((c) => c.minimum == c.maximum), true);
          expect(p.colors.fold<double>(0, (sum, c) => sum + c.maximum), 1);
          final reverse = LutinoPredictions.apply(
            black,
            [pairs[j]],
            [pairs[i]],
          );
          expect(
            p.colors
                .map((c) => (c.outcome.label, c.minimum, c.maximum))
                .toList(),
            reverse.colors
                .map((c) => (c.outcome.label, c.minimum, c.maximum))
                .toList(),
          );
        }
      }
    },
  );

  test('Overlapping white masks are merged before the p-factor split', () {
    final genes = CoatInput('known', {
      'A': [const AllelePair('a', 'a')],
      'B': [const AllelePair('B', 'B')],
      'C': [const AllelePair('C', 'c')],
      'D': [const AllelePair('D', 'D')],
      'E': [const AllelePair('E', 'E')],
      'En': [const AllelePair('en', 'en')],
      'V': [const AllelePair('V', 'v')],
    }, 'self');
    final coats = solveCoats(genes, genes);
    final p = LutinoPredictions.apply(coats, [pairs[1]], [pairs[1]]);
    final white = p.colors.where((c) => c.outcome.white).single;
    expect(white.minimum, 7 / 16);
    expect(white.maximum, 7 / 16);
    expect(
      p.colors
          .where((c) => c.outcome.label.startsWith('Lutino-'))
          .single
          .minimum,
      9 / 64,
    );
    expect(p.colors.fold<double>(0, (sum, c) => sum + c.minimum), 1);
    expect(p.colors.fold<double>(0, (sum, c) => sum + c.maximum), 1);
    expect(
      p.colors.where(
        (c) => c.outcome.label.contains('Lutino') && c.outcome.white,
      ),
      isEmpty,
    );
  });

  test('Unknown p status produces extrema without a genotype prior', () {
    final p = LutinoPredictions.apply(
      black,
      LutinoPredictions.affected,
      LutinoPredictions.unknown,
    );
    expect(p.scenarioCount, 3);
    expect(p.colors, hasLength(2));
    expect(p.colors.every((c) => c.minimum == 0 && c.maximum == 1), true);
    expect(
      () => LutinoPredictions.apply(black, [], pairs),
      throwsArgumentError,
    );
    expect(
      () => LutinoPredictions.apply(black, [const AllelePair('x', 'p')], pairs),
      throwsArgumentError,
    );
  });

  test(
    'Lutino records require verified underlying facts and experimental limits',
    () {
      const raw = {
        'species': 'rabbit',
        'breed': 'Netherland Dwarf',
        'variety': 'Lutino',
      };
      for (final details in [
        null,
        {'color': 'Dove'},
        {'color': 'Black'},
        {'color': 'Orange', 'pattern': 'Self'},
      ]) {
        final r = {...raw, if (details != null) 'color_details': details};
        expect(
          RabbitColorPredictions.inputIssue(r, r),
          contains('verified underlying color'),
        );
        expect(
          () => RabbitColorPredictions.predict(sire: r, dam: r),
          throwsArgumentError,
        );
      }
      for (final (color, pattern) in [
        ('Black', 'Self'),
        ('Orange', 'Agouti'),
        ('Lilac Otter', 'Otter'),
        ('Blue Tortoise', 'Tortoise'),
      ]) {
        final r = {
          ...raw,
          'color_details': {'color': color, 'pattern': pattern},
        };
        final p = RabbitColorPredictions.predict(sire: r, dam: r);
        expect(p.title, contains('experimental'));
        expect(p.limitation, contains('not complete or breed-validated'));
        expect(
          p.colors
              .where((c) => !c.label.startsWith('White'))
              .every((c) => c.label.startsWith('Lutino-modified family')),
          true,
        );
      }
      final ordinary = {...raw, 'variety': 'Black'};
      final lutino = {
        ...raw,
        'color_details': {'color': 'Black', 'pattern': 'Self'},
      };
      final silvered = {...raw, 'variety': 'Champagne (COD)'};
      for (final (sire, dam) in [(lutino, silvered), (silvered, lutino)]) {
        final mixed = RabbitColorPredictions.predict(sire: sire, dam: dam);
        expect(mixed.limitation, contains('experimental, conditional'));
        expect(mixed.limitation, contains('Whether silvering appears'));
        expect(mixed.limitationTitle, 'Experimental Lutino-family model');
      }
      final p = RabbitColorPredictions.predict(sire: ordinary, dam: ordinary);
      expect(p.title, isNot(contains('Lutino')));
      expect(p.colors.any((c) => c.label.contains('Lutino')), false);
    },
  );
}
