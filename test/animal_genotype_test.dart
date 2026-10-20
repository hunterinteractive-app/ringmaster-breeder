import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/genetics/animal_genotype.dart';

void main() {
  test(
    'Reference notation preserves unknowns, case, spacing and provenance',
    () {
      const notation = 'aa bb C- D? E-\nenen Sa- L- wewe';
      final json = const AnimalGenotype(
        notation: notation,
        basis: 'imported',
        source: 'Rabbit Register',
      ).toJson();
      final record = AnimalGenotype.read(json)!;
      expect(record.notation, notation);
      expect(record.basis, 'imported');
      expect(record.source, 'Rabbit Register');
      expect(const AnimalGenotype(notation: '').toJson(), isEmpty);
      expect(AnimalGenotype.read({}), isNull);
      expect(AnimalGenotype.read(null), isNull);
    },
  );

  test(
    'Malformed or oversized entries cannot be silently treated as known genes',
    () {
      for (final bad in [
        'aabb',
        {'notation': 'aa'},
        {'notation': '', 'basis': 'inferred'},
        {'notation': 'aa', 'basis': 'confirmed-by-app'},
        {'notation': 'aa', 'basis': 'inferred', 'extra': true},
        {'notation': List.filled(501, 'a').join(), 'basis': 'inferred'},
      ]) {
        expect(() => AnimalGenotype.read(bad), throwsFormatException);
      }
      expect(AnimalGenotype.validate('', 'Unattached source'), isNotNull);
      expect(
        AnimalGenotype.validate('aa', List.filled(301, 'a').join()),
        isNotNull,
      );
    },
  );

  test(
    'Color inference never upgrades unknown alleles to homozygous facts',
    () {
      final rabbit = {
        'species': 'rabbit',
        'breed': 'Dutch',
        'variety': 'Chocolate',
      };
      expect(AnimalGenotype.colorInference(rabbit), 'aa bb C- D- V-');
      expect(rabbit.containsKey('genotype'), isFalse);
      expect(
        AnimalGenotype.colorInference({...rabbit, 'variety': 'Lilac'}),
        contains('dd'),
      );
      expect(
        AnimalGenotype.colorInference({
          ...rabbit,
          'variety': 'Ruby-eyed White',
        }),
        'cc',
      );
      expect(
        AnimalGenotype.colorInference({...rabbit, 'variety': 'Unknown color'}),
        isNull,
      );
      expect(
        AnimalGenotype.colorInference({...rabbit, 'species': 'cavy'}),
        isNull,
      );
    },
  );
}
