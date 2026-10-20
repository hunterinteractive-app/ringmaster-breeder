import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/genetics/animal_genotype.dart';
import 'package:ringmaster_breeder/genetics/color_prediction.dart';
import 'package:ringmaster_breeder/genetics/saved_genotype_constraints.dart';
import 'package:ringmaster_breeder/genetics/mendelian.dart';

Map<String, dynamic> rabbit(
  String variety, [
  String? genotype,
  String breed = 'Dutch',
]) => {
  'species': 'rabbit',
  'breed': breed,
  'variety': variety,
  if (genotype != null)
    'genotype': AnimalGenotype(
      notation: genotype,
      basis: 'imported',
      source: 'Synthetic reference',
    ).toJson(),
};
Map<String, (double, double)> chances(ColorPrediction prediction) => {
  for (final c in prediction.colors) c.label: (c.minimum, c.maximum),
};

void main() {
  test('Saved heterozygotes produce the independent 9:3:3:1 color cross', () {
    final parent = rabbit('Chocolate', 'aa bb CC Dd Ee enen VV');
    final result = RabbitColorPredictions.predict(sire: parent, dam: parent);
    expect(chances(result), {
      'Chocolate': (.5625, .5625),
      'Lilac': (.1875, .1875),
      'Tortoise (chocolate base)': (.1875, .1875),
      'Tortoise (lilac base)': (.0625, .0625),
    });
    expect(result.scenarioCount, 1);
    expect(
      result.parentInterpretations.join(),
      contains('using saved genotype'),
    );
    expect(result.parentInterpretations.join(), contains('Imported'));
    expect(
      result.parentInterpretations.join(),
      contains('not independently verified'),
    );
  });

  test('Homozygous references remove speculative hidden-color outcomes', () {
    final parent = rabbit('Chocolate', 'aa bb CC DD EE VV');
    expect(chances(RabbitColorPredictions.predict(sire: parent, dam: parent)), {
      'Chocolate': (1.0, 1.0),
    });
    final broad = RabbitColorPredictions.predict(
      sire: rabbit('Chocolate'),
      dam: rabbit('Chocolate'),
    );
    expect(broad.colors.length, greaterThan(4));
    expect(broad.hasRanges, isTrue);
  });

  test(
    'Partial and absent saved genes retain ranges without assigning a prior',
    () {
      final parent = rabbit('Chocolate', 'aa bb C_ D? E-');
      final result = RabbitColorPredictions.predict(sire: parent, dam: parent);
      expect(result.hasRanges, isTrue);
      expect(result.unresolvedInformation.join(), contains('remain unknown'));
      expect(result.scenarioCount, greaterThan(1));
      final empty = {...rabbit('Chocolate'), 'genotype': <String, dynamic>{}};
      expect(
        chances(RabbitColorPredictions.predict(sire: empty, dam: empty)),
        chances(
          RabbitColorPredictions.predict(
            sire: rabbit('Chocolate'),
            dam: rabbit('Chocolate'),
          ),
        ),
      );
    },
  );

  test('Saved white mechanisms are combined without double counting', () {
    final parent = rabbit('Black', 'aa BB Cc DD EE Vv');
    expect(chances(RabbitColorPredictions.predict(sire: parent, dam: parent)), {
      'White (eye color not predicted)': (.4375, .4375),
      'Black': (.5625, .5625),
    });
  });

  test(
    'Constraints respect allele copy counts and do not promote one known copy',
    () {
      final one = SavedGenotypeConstraints.read(rabbit('Black', 'B?'))!;
      expect(one.matches('B', const AllelePair('B', 'B')), isTrue);
      expect(one.matches('B', const AllelePair('B', 'b')), isTrue);
      expect(one.matches('B', const AllelePair('b', 'b')), isFalse);
      final two = SavedGenotypeConstraints.read(rabbit('Black', 'BB'))!;
      expect(two.matches('B', const AllelePair('B', 'b')), isFalse);
    },
  );

  test(
    'Conflicting phenotype, unsupported notation and malformed saved entries block estimates',
    () {
      for (final parent in [
        rabbit('Blue', 'DD'),
        rabbit('Chocolate', 'BB'),
        rabbit('Black', 'aa aa'),
        rabbit('Black', 'aa bb Sa- L- wewe'),
        {...rabbit('Black'), 'genotype': 'aabb'},
        {
          ...rabbit('Black'),
          'genotype': {'notation': 'aa', 'basis': 'verified-by-app'},
        },
      ]) {
        expect(
          RabbitColorPredictions.inputIssue(parent, rabbit('Chocolate')),
          isNotNull,
        );
        expect(
          () => RabbitColorPredictions.predict(
            sire: parent,
            dam: rabbit('Chocolate'),
          ),
          throwsArgumentError,
        );
      }
      expect(
        RabbitColorPredictions.inputIssue(rabbit('Blue', 'DD'), rabbit('Blue')),
        contains('conflicts'),
      );
    },
  );

  test(
    'Temporary carriers cannot override saved homozygous or heterozygous genes',
    () {
      final parent = rabbit('Chocolate', 'DD EE');
      expect(
        RabbitColorPredictions.carrierIssue(
          parent,
          parent,
          sireCarriers: const ColorCarrierDetails(dilute: CarrierKnowledge.yes),
        ),
        contains('conflicts'),
      );
      expect(RabbitColorPredictions.carrierLoci(parent), isNot(contains('D')));
    },
  );

  test(
    'Hotot limited pigment estimates use saved B/D and preserve their scope',
    () {
      final parent = rabbit('Black', 'Bb Dd', 'Dwarf Hotot');
      final result = RabbitColorPredictions.predict(sire: parent, dam: parent);
      expect(chances(result), {
        'Black base pigment': (.5625, .5625),
        'Blue base pigment': (.1875, .1875),
        'Chocolate base pigment': (.1875, .1875),
        'Lilac base pigment': (.0625, .0625),
      });
      expect(result.parentInterpretations.join(), contains('Only B/D'));
      expect(
        RabbitColorPredictions.carrierIssue(
          parent,
          parent,
          sireCarriers: const ColorCarrierDetails(
            chocolate: CarrierKnowledge.no,
          ),
        ),
        contains('conflict'),
      );
    },
  );

  test('Reversing parents preserves saved-genotype percentages', () {
    final sire = rabbit('Black', 'aa Bb CC Dd Ee VV');
    final dam = rabbit('Lilac', 'aa bb CC dd Ee VV');
    expect(
      chances(RabbitColorPredictions.predict(sire: sire, dam: dam)),
      chances(RabbitColorPredictions.predict(sire: dam, dam: sire)),
    );
  });
}
