import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/services/catalog_service.dart';

void main() {
  test('Catalog identity ignores case and repeated whitespace', () {
    expect(CatalogService.normalize('  MINI   rex '), 'mini rex');
  });
  test('Spelling suggestions distinguish near matches', () {
    expect(CatalogService.distance('Choclate', 'Chocolate'), 1);
    expect(CatalogService.distance('Dutch', 'Duch'), 1);
    expect(CatalogService.distance('Tan', 'Dutch'), greaterThan(2));
  });
}
