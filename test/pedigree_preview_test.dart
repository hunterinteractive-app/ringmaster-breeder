import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/models/pedigree_entry.dart';
import 'package:ringmaster_breeder/widgets/pedigree_preview.dart';

void main() {
  testWidgets('Traditional preview aligns ancestors and supports zoom', (
    tester,
  ) async {
    final entry = PedigreeEntry();
    entry.nodes[entry.root]!.addAll({
      'name': 'Henry’s HH77',
      'tattoo': 'HH77',
      'breed': 'Tan',
      'variety': 'Chocolate',
      'sex': 'Doe',
      'dob': '2019-05-29',
    });
    for (var i = 1; i < 15; i++) {
      final key = entry.ensure(i);
      entry.nodes[key]!.addAll({
        'name': 'Ancestor $i',
        'tattoo': 'HH$i',
        'variety': 'Chocolate',
        'legs': 4,
        'registration_number': 'Z183P',
        'grand_champion_number': 'N2169',
        'dob': '2016-08-16',
        'leg_details':
            'BOB 05/13/17-LIVINGSTONCORBA\nPlaced: 1/10 05/06/17-TNS\nBOV 04/01/17-GPRBA',
      });
    }
    await tester.pumpWidget(MaterialApp(home: PedigreePreview(entry: entry)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final subject = tester.getCenter(
      find.byKey(const ValueKey('pedigree-slot-0')),
    );
    final sire = tester.getCenter(
      find.byKey(const ValueKey('pedigree-slot-1')),
    );
    final dam = tester.getCenter(find.byKey(const ValueKey('pedigree-slot-2')));
    expect(subject.dx, lessThan(sire.dx));
    expect(subject.dy, greaterThan(sire.dy));
    expect(subject.dy, lessThan(dam.dy));
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fit'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
