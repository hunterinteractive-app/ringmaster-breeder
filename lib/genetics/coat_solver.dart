import 'coat_rules.dart';
import 'mendelian.dart';

/// Each event is a Cartesian product of per-locus phenotype classes. Events
/// partition the modeled offspring space, including the white masking cases.
class CoatEvent {
  final CoatOutcome outcome;
  final Map<String, Set<String>> classes;
  const CoatEvent(this.outcome, this.classes);
}

String coatClass(String locus, AllelePair pair) {
  if (locus == 'B') return pair.isRecessive('b') ? 'chocolate' : 'black';
  if (locus == 'D') return pair.isRecessive('d') ? 'dilute' : 'dense';
  if (locus == 'V') return pair.isRecessive('v') ? 'white' : 'colored';
  if (locus == 'En') {
    if (pair.isRecessive('En')) return 'charlie';
    return pair.isRecessive('en') ? 'solid' : 'broken';
  }
  final dominant = coatDomains[locus]!.firstWhere(
    (a) => a == pair.first || a == pair.second,
  );
  if (locus == 'C' && dominant == 'cchl' && pair.isRecessive('cchl')) {
    return 'seal';
  }
  return dominant;
}

List<CoatEvent> coatEvents({bool includeSpotting = true}) {
  final result = <CoatEvent>[
    const CoatEvent(
      CoatOutcome('White (eye color not predicted)', 'white', white: true),
      {
        'C': {'c'},
      },
    ),
    const CoatEvent(
      CoatOutcome('White (eye color not predicted)', 'white', white: true),
      {
        'C': {'C', 'cchd', 'cchl', 'seal', 'ch'},
        'V': {'white'},
      },
    ),
  ];
  for (final spots in [
    'solid',
    if (includeSpotting) ...['broken', 'charlie'],
  ]) {
    void add(
      String label,
      String base,
      Map<String, Set<String>> classes, {
      bool tortoise = false,
    }) {
      final prefix = spots == 'solid'
          ? ''
          : spots == 'broken'
          ? 'Broken '
          : 'Charlie-pattern ';
      result.add(
        CoatEvent(
          CoatOutcome(
            '$prefix$label',
            base,
            tortoise: tortoise,
            broken: spots != 'solid',
          ),
          {
            ...classes,
            'V': {'colored'},
            if (includeSpotting) 'En': {spots},
          },
        ),
      );
    }

    for (final b in ['black', 'chocolate']) {
      for (final d in ['dense', 'dilute']) {
        final base = b == 'chocolate'
            ? (d == 'dilute' ? 'lilac' : 'chocolate')
            : (d == 'dilute' ? 'blue' : 'black');
        final capital = '${base[0].toUpperCase()}${base.substring(1)}';
        final bd = <String, Set<String>>{
          'B': {b},
          'D': {d},
        };
        add('Himalayan / pointed white ($base base)', base, {
          ...bd,
          'C': {'ch'},
        });
        for (final c in ['C', 'cchd']) {
          final chin = c == 'cchd';
          final facts = {
            ...bd,
            'C': {c},
          };
          add('${chin ? 'Magpie' : 'Harlequin'} family ($base base)', base, {
            ...facts,
            'E': {'ej'},
          });
          // Self masks steel. It cannot be presented as visible steel.
          add(chin ? 'Self chinchilla ($base base)' : capital, base, {
            ...facts,
            'A': {'a'},
            'E': {'E', 'Es'},
          });
          add(
            '${chin ? 'Silver-tipped' : 'Gold-tipped'} steel family ($base base)',
            base,
            {
              ...facts,
              'A': {'A'},
              'E': {'Es'},
            },
          );
          add(
            '${chin ? 'Chinchilla tan-pattern' : 'Tan-pattern'} family with steel ($base base)',
            base,
            {
              ...facts,
              'A': {'at'},
              'E': {'Es'},
            },
          );
          add(
            chin
                ? 'Silver marten ($base base)'
                : 'Otter / tan pattern ($base base)',
            base,
            {
              ...facts,
              'A': {'at'},
              'E': {'E'},
            },
          );
          final agouti = chin
              ? (base == 'black'
                    ? 'Chinchilla'
                    : base == 'blue'
                    ? 'Squirrel / blue chinchilla'
                    : 'Chinchilla ($base base)')
              : switch (base) {
                  'black' => 'Chestnut / castor / gray',
                  'blue' => 'Opal',
                  'chocolate' => 'Chocolate agouti / amber',
                  _ => 'Lynx',
                };
          add(agouti, base, {
            ...facts,
            'A': {'A'},
            'E': {'E'},
          });
          add(
            chin
                ? 'Non-extension self-chinchilla family ($base base)'
                : 'Tortoise ($base base)',
            base,
            {
              ...facts,
              'A': {'a'},
              'E': {'e'},
            },
            tortoise: !chin,
          );
          add(
            chin
                ? 'Non-extension marten family ($base base)'
                : 'Fox / torted-otter family ($base base)',
            base,
            {
              ...facts,
              'A': {'at'},
              'E': {'e'},
            },
          );
        }
        final shaded = {
          ...bd,
          'C': {'cchl', 'seal'},
        };
        add('Shaded steel family ($base base)', base, {
          ...shaded,
          'A': {'A', 'at'},
          'E': {'Es'},
        });
        add('Shaded harlequin family ($base base)', base, {
          ...shaded,
          'E': {'ej'},
        });
        add('Sable-point family ($base base)', base, {
          ...shaded,
          'E': {'e'},
        });
        add('Sable agouti family ($base base)', base, {
          ...shaded,
          'A': {'A'},
          'E': {'E'},
        });
        add('Sable marten family ($base base)', base, {
          ...shaded,
          'A': {'at'},
          'E': {'E'},
        });
        for (final c in ['cchl', 'seal']) {
          add('${c == 'seal' ? 'Seal' : 'Sable'} family ($base base)', base, {
            ...bd,
            'C': {c},
            'A': {'a'},
            'E': {'E', 'Es'},
          });
        }
      }
    }
    // These families do not reliably reveal B (and frosty also masks D).
    // Merge the masked states BEFORE taking extrema; bounds cannot be added.
    for (final d in ['dense', 'dilute']) {
      add(
        d == 'dilute'
            ? 'Cream / dilute-fawn family'
            : 'Orange / red / fawn family',
        d == 'dilute' ? 'cream' : 'orange',
        {
          'C': {'C'},
          'A': {'A'},
          'E': {'e'},
          'D': {d},
        },
      );
    }
    add('Frosted-pearl / ermine family', 'white', {
      'C': {'cchd'},
      'A': {'A'},
      'E': {'e'},
    });
  }
  return List.unmodifiable(result);
}

class CoatEstimate {
  final CoatOutcome outcome;
  final double minimum, maximum;
  const CoatEstimate(this.outcome, this.minimum, this.maximum);
}

class SharedCoatPrediction {
  final List<CoatEstimate> colors;
  final int scenarioCount;
  const SharedCoatPrediction(this.colors, this.scenarioCount);
}

/// Exact extrema without exponential scenario enumeration. For each outcome,
/// P(outcome | parent genes) is a product of independent locus events. Parent
/// possibilities are also a Cartesian product, so min/max of the nonnegative
/// product equals the product of the per-locus min/max. No genotype prior is
/// assumed. Masked states must be grouped into the event before this operation.
SharedCoatPrediction solveCoats(
  CoatInput sire,
  CoatInput dam, {
  bool includeSpotting = true,
}) {
  final distributions = <String, List<List<InheritedPair>>>{};
  var scenarios = 1;
  for (final locus in coatDomains.keys) {
    if (locus == 'En' && !includeSpotting) continue;
    final s = sire.loci[locus]!, d = dam.loci[locus]!;
    if (s.isEmpty || d.isEmpty) {
      throw ArgumentError('Contradictory $locus information');
    }
    scenarios *= s.length * d.length;
    distributions[locus] = [
      for (final a in s)
        for (final b in d) inheritLocus(a, b),
    ];
  }
  final cache = <String, (double, double)>{};
  (double, double) bounds(String locus, Set<String> classes) {
    final key = '$locus:${(classes.toList()..sort()).join(',')}';
    return cache.putIfAbsent(key, () {
      var minimum = 1.0, maximum = 0.0;
      for (final distribution in distributions[locus]!) {
        var chance = 0.0;
        for (final offspring in distribution) {
          if (classes.contains(coatClass(locus, offspring.genotype))) {
            chance += offspring.probability;
          }
        }
        if (chance < minimum) minimum = chance;
        if (chance > maximum) maximum = chance;
      }
      return (minimum, maximum);
    });
  }

  final cc = bounds('C', {'c'}), vv = bounds('V', {'white'});
  double whiteChance(double c, double v) => c + v - c * v;
  final whiteMin = whiteChance(cc.$1, vv.$1),
      whiteMax = whiteChance(cc.$2, vv.$2);
  final colors = <CoatEstimate>[
    if (whiteMax > 0)
      CoatEstimate(
        const CoatOutcome(
          'White (eye color not predicted)',
          'white',
          white: true,
        ),
        whiteMin,
        whiteMax,
      ),
  ];
  for (final event in coatEvents(includeSpotting: includeSpotting)) {
    if (event.outcome.white) continue;
    var minimum = 1.0, maximum = 1.0;
    for (final fact in event.classes.entries) {
      final range = bounds(fact.key, fact.value);
      minimum *= range.$1;
      maximum *= range.$2;
    }
    if (maximum > 0) colors.add(CoatEstimate(event.outcome, minimum, maximum));
  }
  colors.sort((a, b) {
    final chance = b.maximum.compareTo(a.maximum);
    return chance != 0 ? chance : a.outcome.label.compareTo(b.outcome.label);
  });
  return SharedCoatPrediction(List.unmodifiable(colors), scenarios);
}
