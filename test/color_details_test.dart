import 'package:ringmaster_breeder/services/pedigree_pdf_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/utils/color_details.dart';
import 'package:ringmaster_breeder/models/pedigree_entry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('PDF lays out a full pedigree with composed color labels', () async {
    final pedigree = <String, dynamic>{
      for (final slot in [
        'animal',
        'sire',
        'dam',
        'sire_sire',
        'sire_dam',
        'dam_sire',
        'dam_dam',
        'gg1',
        'gg2',
        'gg3',
        'gg4',
        'gg5',
        'gg6',
        'gg7',
        'gg8',
      ])
        slot: {
          'name': 'Pedigree animal',
          'species': 'rabbit',
          'breed': 'Holland Lop',
          'variety': 'Silver Marten Group (COD)',
          'color_details': {'color': 'Chocolate', 'pattern': 'Silver Marten'},
          'registration_number': 'ABC123',
          'grand_champion_number': 'GC123',
        },
    };
    final bytes = await PedigreePdfService.generate(pedigree: pedigree);
    expect(bytes.length, greaterThan(1000));
  });
  test(
    'preserves breed terminology and combines separately saved descriptors',
    () {
      final animal = <String, dynamic>{
        'variety': 'Tortoise Shell',
        'color_details': {'base_color': 'Blue'},
      };
      expect(varietyLabel(animal), 'Tortoise Shell • Blue');
      expect(animal['variety'], 'Tortoise Shell');
      expect(
        varietyLabel({
          'variety': 'Broken',
          'color_details': {'color': 'Black', 'pattern': 'Broken'},
        }),
        'Broken • Black',
      );
      expect(varietyLabel({'variety': 'White'}), 'White');
    },
  );
  test('COD requires both color and pattern, including COD breeds', () {
    expect(codDetailsError('Mini Rex', 'Tan (COD)', {}), isNotNull);
    expect(
      codDetailsError('Mini Rex', 'Tan (COD)', {'color': 'Black'}),
      isNotNull,
    );
    expect(
      codDetailsError('Mini Rex', 'Tan (COD)', {
        'color': 'Black',
        'pattern': 'Tan',
      }),
      isNull,
    );
    expect(codDetailsError('Velveteen Lop (COD)', 'Solid', {}), isNotNull);
    expect(codDetailsError('English Angora', 'Broken', {}), isNull);
  });
  test(
    'draft round trip retains structured details for repeated ancestors',
    () {
      final entry = PedigreeEntry();
      final sire = entry.ensure(1);
      entry.nodes[sire]!['color_details'] = {
        'color': 'Blue',
        'pattern': 'Solid',
      };
      entry.ensure(2);
      entry.link(5, sire);
      final restored = PedigreeEntry()..restore(entry.data());
      expect(restored.at(1), restored.at(5));
      expect(colorDetails(restored.nodes[restored.at(5)]!), {
        'color': 'Blue',
        'pattern': 'Solid',
      });
    },
  );
}
