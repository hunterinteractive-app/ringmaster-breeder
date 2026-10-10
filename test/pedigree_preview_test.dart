import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/models/pedigree_entry.dart';
import 'package:ringmaster_breeder/widgets/pedigree_preview.dart';

void main() {
  testWidgets(
    'Saved tree shares layout, repeated markers and animal navigation',
    (tester) async {
      String? opened;
      final tree = PedigreePreview.snapshot(
        pedigree: {
          'animal': {'id': 'root', 'tattoo': 'HH77', 'breed': 'Tan'},
          'sire': {'id': 'sire', 'tattoo': 'HH32'},
          'dam': {'id': 'dam', 'tattoo': 'HH9'},
          'sire_sire': {
            'id': 'viper',
            'name': "Daly's VIPER",
            'tattoo': 'VIP',
            'dob': '2015-07-15',
            'leg_details': 'BOB 02/11/17-HHR',
          },
          'dam_sire': {'id': 'viper', 'name': "Daly's VIPER", 'tattoo': 'VIP'},
        },
        onAnimalTap: (id) => opened = id,
      );
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: tree)));
      await tester.pumpAndSettle();
      expect(find.text('Pedigree Tree'), findsOneWidget);
      expect(find.byTooltip('Close preview'), findsNothing);
      expect(find.textContaining('Repeated ancestor'), findsNWidgets(2));
      expect(find.textContaining('07/15/2015'), findsOneWidget);
      expect(find.text('BOB 02/11/17-HHR'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pedigree-slot-3')));
      expect(opened, 'viper');
      expect(
        tester.getCenter(find.byKey(const ValueKey('pedigree-slot-0'))).dx,
        lessThan(
          tester.getCenter(find.byKey(const ValueKey('pedigree-slot-1'))).dx,
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );
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
