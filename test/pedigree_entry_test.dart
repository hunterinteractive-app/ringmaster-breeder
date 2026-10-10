import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/models/pedigree_entry.dart';
import 'package:ringmaster_breeder/screens/pedigree_entry_screen.dart';

void main() {
  test(
    'Matching ancestors reuse identity and ancestry without allowing cycles',
    () {
      final p = PedigreeEntry();
      p.nodes[p.root]!['name'] = 'Subject';
      p.ensure(1);
      p.ensure(2);
      final vip = p.ensure(3);
      p.nodes[vip]!.addAll({'name': "DALY'S VIPER", 'tattoo': 'VIP'});
      final ancestor = p.ensure(7);
      p.nodes[ancestor]!['name'] = 'Earlier sire';
      final repeated = p.ensure(5);
      p.nodes[repeated]!['name'] = '  daly’s viper  ';
      expect(p.matchingAncestors(5), [vip]);
      p.nodes[repeated]!['name'] = 'Different spelling';
      p.nodes[repeated]!['tattoo'] = ' vip ';
      expect(p.matchingAncestors(5), [vip]);
      p.link(5, vip);
      expect(p.at(11), ancestor);
      expect(p.matchingAncestors(7), isEmpty);
    },
  );
  testWidgets('Entering a matching ear number asks before autofilling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: PedigreeEntryScreen(
          ringId: 'test',
          initialAnimals: [
            {
              'id': 'vip',
              'species': 'rabbit',
              'sex': 'Buck',
              'name': "DALY'S VIPER",
              'tattoo': 'VIP',
              'breed': 'Tan',
              'variety': 'Black',
            },
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Sire'));
    await tester.pumpAndSettle();
    final ear = find.byWidgetPredicate(
      (w) => w is TextFormField && w.key.toString().contains('tattoo'),
    );
    await tester.enterText(ear, 'VIP');
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
    expect(find.text('Is this the same animal?'), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, "DALY'S VIPER • VIP"));
    await tester.pumpAndSettle();
    expect(find.text('Is this the same animal?'), findsNothing);
    expect(
      find.text(
        'Using an existing animal and its saved ancestry. Its record will not be overwritten.',
      ),
      findsOneWidget,
    );
  });
  test(
    'New ancestors inherit last catalog choices without overwriting existing nodes',
    () {
      final p = PedigreeEntry();
      p.nodes[p.root]!['breed'] = 'Mini Lop';
      p.rememberCatalog(p.root, 'breed', 'Mini Lop');
      p.rememberCatalog(p.root, 'variety', 'Chinchilla');
      final sire = p.ensure(1);
      expect(p.nodes[sire]!['breed'], 'Mini Lop');
      expect(p.nodes[sire]!['variety'], 'Chinchilla');
      p.nodes[sire]!['variety'] = 'Black';
      p.rememberCatalog(sire, 'variety', 'Black');
      expect(p.nodes[p.ensure(3)]!['variety'], 'Black');
      final restored = PedigreeEntry()..restore(p.data());
      expect(restored.nodes[restored.ensure(2)]!['variety'], 'Black');
      restored.nodes[sire]!['breed'] = 'Mini Rex';
      restored.rememberCatalog(sire, 'breed', 'Mini Rex');
      expect(restored.nodes[restored.ensure(4)]!['variety'], '');
      expect(restored.nodes[restored.ensure(3)]!['variety'], 'Black');
    },
  );
  test(
    'Repeated ancestors share one identity through draft save and restore',
    () {
      final p = PedigreeEntry();
      p.nodes[p.root]!['name'] = 'Subject';
      p.nodes[p.root]!['leg_details'] =
          'BOB 05/13/17-LIVINGSTONCORBA\nPlaced: 1/10 05/06/17-TNS';
      final sire = p.ensure(1);
      p.nodes[sire]!['name'] = 'Repeated sire';
      final dam = p.ensure(2);
      p.nodes[dam]!['name'] = 'Dam';
      p.link(5, sire);
      expect(p.at(1), p.at(5));
      p.nodes[sire]!['tattoo'] = 'S1';
      expect(p.nodes[p.at(5)]!['tattoo'], 'S1');
      expect(p.data()['nodes'].length, 3);
      final restored = PedigreeEntry()..restore(p.data());
      expect(restored.at(1), restored.at(5));
      expect(
        restored.nodes[restored.root]!['leg_details'],
        p.nodes[p.root]!['leg_details'],
      );
      expect(() => p.link(3, sire), throwsStateError);
      expect(() => p.link(4, sire), throwsStateError);
    },
  );
  testWidgets('Type a pedigree and reuse its sire on the dam side', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: PedigreeEntryScreen(ringId: 'test', initialAnimals: []),
      ),
    );
    await tester.pumpAndSettle();
    Finder field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );
    await tester.enterText(field('Name'), 'Subject');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Sire'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Name'), 'Shared father');
    await tester.enterText(field('Ear number / tag'), 'DAD1');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Dam'));
    await tester.pumpAndSettle();
    await tester.enterText(field('Name'), 'Mother');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Dam’s sire'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.decoration?.labelText ==
                'Find existing or reuse an entered ancestor',
      ),
      'DAD1',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shared father • DAD1').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Repeated ancestor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
