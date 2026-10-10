import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/services/catalog_service.dart';

void main() {
  test(
    'Standard colors remain recognized without a Show match and aliases deduplicate',
    () {
      final rows = CatalogService.sortedChoices([
        {
          'name': 'Black',
          'is_recognized': true,
          'standard_reference': '2026–2030',
        },
        {
          'name': 'Self Group - Black',
          'standard_name': 'Black',
          'is_recognized': true,
          'standard_reference': '2026–2030',
        },
        {'name': 'Custom Test', 'is_recognized': false},
        {
          'name': 'Shaded Group - Blue',
          'catalog_kind': 'legacy_ambiguous',
          'is_recognized': false,
        },
        {'name': 'Fox Group (COD)', 'is_recognized': true},
      ]);
      expect(rows.length, 3);
      expect(rows.first['name'], 'Black');
      expect(CatalogService.matches(rows.first, 'Self Group - Black'), isTrue);
      expect(
        CatalogService.choiceNote(rows.first),
        'Recognized • ARBA Standard',
      );
      expect(CatalogService.choiceNote(rows[1]), 'Unrecognized');
      expect(CatalogService.choiceNote(rows[2]), 'COD');
      expect(
        CatalogService.choiceNote({
          'name': 'Agouti',
          'catalog_kind': 'color_group',
          'is_recognized': true,
        }),
        contains('Color group'),
      );
    },
  );

  test(
    'Legacy spelling, accents and COD aliases converge without fuzzy merges',
    () {
      for (final pair in [
        ['Argente St. Hubert', 'Argenté St. Hubert (COD)'],
        ["Champagne d’Argente", "Champagne d'Argent"],
        ['Peruvian Stain', 'Peruvian Satin'],
        ['Argente\u0301 St. Hubert', 'Argenté St. Hubert (COD)'],
      ]) {
        expect(
          CatalogService.identity(pair[0]),
          CatalogService.identity(pair[1]),
        );
      }
      expect(
        CatalogService.identity('Crested'),
        isNot(CatalogService.identity('White Crested')),
      );
      expect(
        CatalogService.identity('Tan'),
        isNot(CatalogService.identity('Satin')),
      );
    },
  );
  test(
    'COD aliases retain all varieties and canonical label regardless of input order',
    () {
      final rows = <Map<String, dynamic>>[
        {
          'name': 'Argente St. Hubert',
          'is_recognized': false,
          'varieties': [
            {'name': 'Blue', 'is_recognized': false},
          ],
        },
        {
          'name': 'Argenté St. Hubert (COD)',
          'is_recognized': true,
          'varieties': [
            {'name': 'Black', 'is_recognized': true},
          ],
        },
      ];
      for (final list in [rows, rows.reversed.toList()]) {
        final result = CatalogService.sortedChoices(list);
        expect(result.length, 1);
        expect(result.single['name'], 'Argenté St. Hubert (COD)');
        expect(
          (result.single['varieties'] as List).map((r) => r['name']).toList(),
          ['Black', 'Blue'],
        );
      }
    },
  );

  test('COD alias uses Show spelling and choices sort A to Z', () {
    final choices = CatalogService.sortedChoices([
      {'name': 'Velveteen Lop', 'is_recognized': false},
      {'name': 'Velveteen Lop (COD)', 'is_recognized': true},
      {'name': 'Tan', 'is_recognized': true},
      {'name': 'american', 'is_recognized': false},
    ]);
    expect(choices.map((r) => r['name']).toList(), [
      'american',
      'Tan',
      'Velveteen Lop (COD)',
    ]);
    expect(CatalogService.isCod(choices.last), true);
    expect(
      CatalogService.identity('Velveteen Lop (COD)'),
      CatalogService.identity('Velveteen Lop'),
    );
  });

  test('Catalog identity ignores case and repeated whitespace', () {
    expect(CatalogService.normalize('  MINI   rex '), 'mini rex');
  });
  test('Spelling suggestions distinguish near matches', () {
    expect(CatalogService.distance('Choclate', 'Chocolate'), 1);
    expect(CatalogService.distance('Dutch', 'Duch'), 1);
    expect(CatalogService.distance('Tan', 'Dutch'), greaterThan(2));
  });
}
