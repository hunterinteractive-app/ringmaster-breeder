import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/genetics/animal_genotype.dart';
import 'package:ringmaster_breeder/genetics/color_prediction.dart';
import 'package:ringmaster_breeder/genetics/what_if_prediction.dart';
import 'package:ringmaster_breeder/services/what_if_catalog.dart';

Map<String, dynamic> parent(String breed, String variety, [String? genes]) => {
  'species': 'rabbit',
  'breed': breed,
  'variety': variety,
  if (genes != null) 'genotype': AnimalGenotype(notation: genes).toJson(),
};
Map<String, (double, double)> chances(ColorPrediction prediction) => {
  for (final c in prediction.colors) c.label: (c.minimum, c.maximum),
};

void main() {
  test('Catalog unions every rabbit variety without filtering by breed', () {
    final catalog = WhatIfCatalog.fromRows([
      {
        'species': 'rabbit',
        'name': 'Tan',
        'varieties': [
          {'name': 'Lilac'},
          {'name': 'Black'},
          {'name': ' Black '},
        ],
      },
      {
        'species': 'rabbit',
        'name': 'Dutch',
        'varieties': [
          {'name': 'Tort', 'standard_name': 'Tortoise'},
          {'name': 'black'},
        ],
      },
      {
        'species': 'cavy',
        'name': 'Abyssinian',
        'varieties': [
          {'name': 'Cavy only'},
        ],
      },
    ]);
    expect(catalog.breeds, ['Dutch', 'Tan']);
    expect(catalog.varieties, ['Black', 'Lilac', 'Tort', 'Tortoise']);
  });

  test(
    'Different breeds use an exact 9:3:3:1 cross without altering saved calculator',
    () {
      final s = parent('Havana', 'Black', 'aa Bb CC Dd EE enen VV');
      final d = parent('Rex', 'Black', 'aa Bb CC Dd EE enen VV');
      final before = jsonEncode([s, d]);
      expect(RabbitColorPredictions.inputIssue(s, d), contains('same breed'));
      final result = WhatIfPredictions.predict(sire: s, dam: d);
      expect(chances(result), {
        'Black': (.5625, .5625),
        'Blue': (.1875, .1875),
        'Chocolate': (.1875, .1875),
        'Lilac': (.0625, .0625),
      });
      expect(result.scenarioCount, 1);
      expect(result.limitation, contains('does not predict breed'));
      expect(
        result.parentInterpretations.join(),
        contains('Hypothetical genotype'),
      );
      expect(
        result.parentInterpretations.join(),
        isNot(contains('saved genotype')),
      );
      expect(jsonEncode([s, d]), before);
      expect(
        chances(WhatIfPredictions.predict(sire: d, dam: s)),
        chances(result),
      );
    },
  );

  test('Same-breed What If preserves existing special model percentages', () {
    for (final p in [
      parent('Dutch', 'Chocolate', 'aa bb CC Dd Ee VV'),
      parent('Tan', 'Lilac', 'atat bb CC dd EE enen VV'),
      parent('Dwarf Hotot', 'Black', 'Bb Dd'),
    ]) {
      final expected = RabbitColorPredictions.predict(sire: p, dam: p);
      final result = WhatIfPredictions.predict(sire: p, dam: p);
      expect(chances(result), chances(expected));
      expect(result.markings.length, expected.markings.length);
      expect(
        result.parentInterpretations.join(),
        isNot(contains('saved genotype')),
      );
    }
  });

  test('Each parent retains its own breed interpretation', () {
    final result = WhatIfPredictions.predict(
      sire: parent('Tan', 'Black', 'atat BB CC DD EE enen VV'),
      dam: parent('Havana', 'Black', 'aa BB CC DD EE enen VV'),
    );
    expect(result.colors.length, 1);
    expect(result.colors.single.label.toLowerCase(), contains('otter'));
    expect(result.colors.single.minimum, 1);
  });

  test('Unknown carriers remain ranges with no invented prior', () {
    final result = WhatIfPredictions.predict(
      sire: parent('Havana', 'Chocolate'),
      dam: parent('Rex', 'Chocolate'),
    );
    expect(result.hasRanges, isTrue);
    expect(result.unresolvedInformation, isNotEmpty);
    final chocolate = result.colors.singleWhere((c) => c.label == 'Chocolate');
    expect(chocolate.maximum, 1);
    expect(chocolate.minimum, lessThan(chocolate.maximum));
  });

  test(
    'Dutch mixtures exclude unmodeled spotting while preserving color math',
    () {
      final s = parent('Dutch', 'Chocolate', 'aa bb CC Dd Ee VV');
      final d = parent('Havana', 'Chocolate', 'aa bb CC Dd Ee enen VV');
      final result = WhatIfPredictions.predict(sire: s, dam: d);
      expect(chances(result), {
        'Chocolate': (.5625, .5625),
        'Lilac': (.1875, .1875),
        'Tortoise (chocolate base)': (.1875, .1875),
        'Tortoise (lilac base)': (.0625, .0625),
      });
      expect(result.limitation, contains('Dutch white markings'));
      expect(
        chances(WhatIfPredictions.predict(sire: d, dam: s)),
        chances(result),
      );
    },
  );

  test('Overlapping white mechanisms count white offspring once', () {
    final result = WhatIfPredictions.predict(
      sire: parent('Havana', 'Black', 'aa BB Cc DD EE enen Vv'),
      dam: parent('Rex', 'Black', 'aa BB Cc DD EE enen Vv'),
    );
    expect(chances(result), {
      'White (eye color not predicted)': (.4375, .4375),
      'Black': (.5625, .5625),
    });
  });

  test(
    'Unsupported combinations and conflicting assumptions fail with support guidance',
    () {
      for (final s in [
        parent('Dwarf Hotot', 'Black'),
        parent('Netherland Dwarf', 'Lutino'),
        parent('Havana', 'Unbuilt variety'),
        parent('Havana', 'Blue', 'DD'),
        parent('Havana', 'Black', 'aa Sa-'),
        parent('Havana', 'White'),
      ]) {
        final d = parent('Rex', 'Black');
        expect(
          WhatIfPredictions.inputIssue(s, d),
          contains('support@ringmasterone.com'),
        );
        expect(
          () => WhatIfPredictions.predict(sire: s, dam: d),
          throwsArgumentError,
        );
      }
    },
  );
}
