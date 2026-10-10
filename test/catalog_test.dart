import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/services/catalog_service.dart';

void main() {
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
