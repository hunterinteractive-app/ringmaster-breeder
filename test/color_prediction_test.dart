import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/genetics/color_prediction.dart';
import 'package:ringmaster_breeder/genetics/mendelian.dart';

Map<String, dynamic> tan(String color) => {
  'species': 'rabbit',
  'breed': 'Tan',
  'variety': color,
};

Map<BaseCoatColor, (double, double)> ranges(ColorPrediction prediction) => {
  for (final c in prediction.colors) c.color: (c.minimum, c.maximum),
};

// Restricted-model ratios are tested explicitly; the breeder-facing Tan model
// is exercised with unresolved backgrounds in tan_shared_prediction_test.dart.
void main() {
  test('Single-locus inheritance combines duplicate transmitted copies', () {
    final outcomes = inheritLocus(
      const AllelePair('B', 'b'),
      const AllelePair('B', 'b'),
    );
    expect(
      {for (final p in outcomes) p.genotype.key: p.probability},
      {'B/B': .25, 'B/b': .5, 'b/b': .25},
    );
    final recessive = inheritLocus(
      const AllelePair('b', 'b'),
      const AllelePair('b', 'b'),
    );
    expect(recessive.single.genotype.key, 'b/b');
    expect(recessive.single.probability, 1);
  });

  test(
    'Restricted B/D model: two double carriers give the Mendelian 9:3:3:1 base-color ratio',
    () {
      const carrier = ColorCarrierDetails(
        chocolate: CarrierKnowledge.yes,
        dilute: CarrierKnowledge.yes,
      );
      final p = RabbitColorPredictions.predictBaseColors(
        sire: tan('Black'),
        dam: tan('Black'),
        sireCarriers: carrier,
        damCarriers: carrier,
      );
      expect(p.scenarioCount, 1);
      expect(p.hasRanges, isFalse);
      expect(ranges(p), {
        BaseCoatColor.black: (.5625, .5625),
        BaseCoatColor.blue: (.1875, .1875),
        BaseCoatColor.chocolate: (.1875, .1875),
        BaseCoatColor.lilac: (.0625, .0625),
      });
    },
  );

  test(
    'Unknown carriers produce bounds, never an average of guessed genotypes',
    () {
      final p = RabbitColorPredictions.predictBaseColors(
        sire: tan('Black'),
        dam: tan('Black'),
      );
      expect(p.scenarioCount, 16);
      expect(p.hasRanges, isTrue);
      expect(ranges(p), {
        BaseCoatColor.black: (.5625, 1.0),
        BaseCoatColor.blue: (0.0, .25),
        BaseCoatColor.chocolate: (0.0, .25),
        BaseCoatColor.lilac: (0.0, .0625),
      });
    },
  );

  test(
    'Lilac × Chocolate uses phenotype facts while leaving dilution unknown',
    () {
      final p = RabbitColorPredictions.predictBaseColors(
        sire: tan('Lilac'),
        dam: tan('Chocolate'),
      );
      expect(ranges(p), {
        BaseCoatColor.chocolate: (.5, 1.0),
        BaseCoatColor.lilac: (0.0, .5),
      });
      final carrier = RabbitColorPredictions.predictBaseColors(
        sire: tan('Lilac'),
        dam: tan('Chocolate'),
        damCarriers: const ColorCarrierDetails(dilute: CarrierKnowledge.yes),
      );
      expect(ranges(carrier), {
        BaseCoatColor.chocolate: (.5, .5),
        BaseCoatColor.lilac: (.5, .5),
      });
      final nonCarrier = RabbitColorPredictions.predictBaseColors(
        sire: tan('Lilac'),
        dam: tan('Chocolate'),
        damCarriers: const ColorCarrierDetails(dilute: CarrierKnowledge.no),
      );
      expect(ranges(nonCarrier), {BaseCoatColor.chocolate: (1.0, 1.0)});
    },
  );

  test('Lilac × Lilac supplies both recessive loci without carrier inputs', () {
    final p = RabbitColorPredictions.predictBaseColors(
      sire: tan('Lilac'),
      dam: tan('Lilac'),
    );
    expect(p.scenarioCount, 1);
    expect(ranges(p), {BaseCoatColor.lilac: (1.0, 1.0)});
  });

  test(
    'All nine B/D genotypes cross symmetrically and exact chances sum to one',
    () {
      final parents = <(Map<String, dynamic>, ColorCarrierDetails)>[];
      for (final b in ['BB', 'Bb', 'bb']) {
        for (final d in ['DD', 'Dd', 'dd']) {
          final color = b == 'bb'
              ? (d == 'dd' ? 'Lilac' : 'Chocolate')
              : (d == 'dd' ? 'Blue' : 'Black');
          parents.add((
            tan(color),
            ColorCarrierDetails(
              chocolate: b == 'Bb' ? CarrierKnowledge.yes : CarrierKnowledge.no,
              dilute: d == 'Dd' ? CarrierKnowledge.yes : CarrierKnowledge.no,
            ),
          ));
        }
      }
      for (final a in parents) {
        for (final b in parents) {
          final forward = RabbitColorPredictions.predictBaseColors(
            sire: a.$1,
            dam: b.$1,
            sireCarriers: a.$2,
            damCarriers: b.$2,
          );
          final reverse = RabbitColorPredictions.predictBaseColors(
            sire: b.$1,
            dam: a.$1,
            sireCarriers: b.$2,
            damCarriers: a.$2,
          );
          expect(forward.scenarioCount, 1);
          expect(forward.hasRanges, isFalse);
          expect(
            forward.colors.fold(0.0, (sum, p) => sum + p.maximum),
            closeTo(1, 1e-10),
          );
          expect(ranges(forward), ranges(reverse));
          for (final chance in forward.colors) {
            expect(chance.minimum, inInclusiveRange(0, 1));
            expect(chance.maximum, inInclusiveRange(0, 1));
          }
        }
      }
    },
  );

  test(
    'Every unknown color-pair range encloses all compatible carrier choices',
    () {
      const choices = [CarrierKnowledge.no, CarrierKnowledge.yes];
      for (final a in BaseCoatColor.values) {
        for (final b in BaseCoatColor.values) {
          final bounds = ranges(
            RabbitColorPredictions.predictBaseColors(
              sire: tan(a.label),
              dam: tan(b.label),
            ),
          );
          for (final sc in choices) {
            for (final sd in choices) {
              for (final dc in choices) {
                for (final dd in choices) {
                  final p = RabbitColorPredictions.predictBaseColors(
                    sire: tan(a.label),
                    dam: tan(b.label),
                    sireCarriers: ColorCarrierDetails(
                      chocolate: sc,
                      dilute: sd,
                    ),
                    damCarriers: ColorCarrierDetails(chocolate: dc, dilute: dd),
                  );
                  for (final chance in p.colors) {
                    expect(
                      chance.maximum,
                      inInclusiveRange(
                        bounds[chance.color]!.$1,
                        bounds[chance.color]!.$2,
                      ),
                    );
                  }
                }
              }
            }
          }
        }
      }
    },
  );

  test(
    'Mixed species/breeds, missing varieties and conflicting details fail closed',
    () {
      for (final unsupported in [
        {...tan('Black'), 'breed': 'Dutch'},
        {...tan('Black'), 'species': 'cavy'},
        tan(''),
        tan('Dove'),
        {
          ...tan('Black'),
          'color_details': {'color': 'Blue'},
        },
      ]) {
        expect(
          RabbitColorPredictions.inputIssue(tan('Black'), unsupported),
          isNotNull,
        );
        expect(
          () => RabbitColorPredictions.predict(
            sire: tan('Black'),
            dam: unsupported,
          ),
          throwsArgumentError,
        );
      }
      for (final supported in [
        tan('Black Otter'),
        {
          ...tan('Black'),
          'color_details': {'pattern': 'Broken'},
        },
      ]) {
        expect(
          RabbitColorPredictions.inputIssue(tan('Black'), supported),
          isNull,
        );
        expect(
          RabbitColorPredictions.predict(
            sire: tan('Black'),
            dam: supported,
          ).scope,
          contains('Shared rabbit coat model'),
        );
      }
      expect(
        RabbitColorPredictions.inputIssue(tan('Black'), {
          ...tan('Black'),
          'color_details': {'base_color': 'Black', 'pattern': ''},
        }),
        isNull,
      );
      expect(
        RabbitColorPredictions.inputIssue(tan('Black'), {
          'species': ' Rabbit ',
          'breed': ' TAN ',
          'variety': ' lilac ',
        }),
        isNull,
      );
    },
  );
}
