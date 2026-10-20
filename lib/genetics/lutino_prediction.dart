import 'breed_color_contexts.dart';
import 'coat_rules.dart';
import 'coat_solver.dart';
import 'mendelian.dart';

/// Conditional classical p-factor model, not a molecular locus claim.
/// The documented Lutino parent is pp. Unrecorded status in the other parent
/// permits PP, Pp and pp (the effect can be concealed); there is no carrier prior.
/// The independent factor is applied only after the ordinary coat calculation.
/// White is already masked and must not be split or counted twice.
class LutinoPredictions {
  static bool applies(Map<String, dynamic> animal) =>
      BreedColorContexts.kind(animal) == 'dwarf lutino';

  static const unknown = [
    AllelePair('P', 'P'),
    AllelePair('P', 'p'),
    AllelePair('p', 'p'),
  ];
  static const affected = [AllelePair('p', 'p')];

  static SharedCoatPrediction apply(
    SharedCoatPrediction coats,
    List<AllelePair> sire,
    List<AllelePair> dam,
  ) {
    if (sire.isEmpty ||
        dam.isEmpty ||
        [...sire, ...dam].any(
          (p) =>
              !['P', 'p'].contains(p.first) || !['P', 'p'].contains(p.second),
        )) {
      throw ArgumentError('Unsupported p-factor information');
    }
    final chances = [
      for (final s in sire)
        for (final d in dam)
          inheritLocus(s, d)
              .where((p) => p.genotype.isRecessive('p'))
              .fold(0.0, (sum, p) => sum + p.probability),
    ]..sort();
    final minimum = chances.first, maximum = chances.last;
    final colors =
        <CoatEstimate>[
          for (final color in coats.colors)
            if (color.outcome.white)
              color
            else ...[
              if (maximum < 1 || minimum < 1)
                CoatEstimate(
                  color.outcome,
                  color.minimum * (1 - maximum),
                  color.maximum * (1 - minimum),
                ),
              if (maximum > 0)
                CoatEstimate(
                  CoatOutcome(
                    'Lutino-modified family: ${color.outcome.label} (shade not predicted)',
                    'cream',
                    broken: color.outcome.broken,
                  ),
                  color.minimum * minimum,
                  color.maximum * maximum,
                ),
            ],
        ]..sort((a, b) {
          final chance = b.maximum.compareTo(a.maximum);
          return chance != 0
              ? chance
              : a.outcome.label.compareTo(b.outcome.label);
        });
    return SharedCoatPrediction(
      List.unmodifiable(colors),
      coats.scenarioCount * sire.length * dam.length,
    );
  }
}
