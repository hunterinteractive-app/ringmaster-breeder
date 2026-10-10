import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/models/pedigree_layout.dart';

void main() {
  test('Parent results fit within landscape sheet', () {
    final layout = PedigreeLayout({
      'sire': {'leg_details': 'BOB\nBOV\nBOS\nBest in Show'},
    });
    expect(layout.height, 612);
    expect(layout.top(1) + 55 + 4 + 40, lessThan(layout.top(2)));
  });
  test('Long outer-generation results expand sheet without overlap', () {
    final layout = PedigreeLayout({
      'gg1': {'leg_details': List.filled(30, 'Show result').join('\n')},
    });
    expect(layout.top(7) + 55 + 4 + 300, lessThan(layout.top(8)));
    expect(layout.top(14) + 55, lessThan(layout.height - 22));
    expect(layout.left(7), 576);
  });
}
