import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/genetics/breed_color_contexts.dart';
import 'package:ringmaster_breeder/genetics/coat_rules.dart';
import 'package:ringmaster_breeder/genetics/color_prediction.dart';
import 'package:ringmaster_breeder/genetics/silvered_breeds.dart';
import 'package:ringmaster_breeder/screens/genetics_screen.dart';
import '../tool/genetics_coverage_checklist.dart';

Map<String, dynamic> rabbit(
  String breed,
  String variety, [
  Map<String, String>? details,
]) => {
  'species': 'rabbit',
  'breed': breed,
  'variety': variety,
  if (details != null) 'color_details': details,
};
Map<String, (double, double)> colors(ColorPrediction p) => {
  for (final c in p.colors) c.label: (c.minimum, c.maximum),
};
void main() {
  test('Rufus uses a conditional agouti background, not nonextension red', () {
    final r = rabbit('Belgian Hare', 'Rufus');
    final genes = CoatRules.resolve(r)!;
    expect(genes.family, 'agouti');
    for (final l in ['A', 'B', 'C', 'D', 'E']) {
      expect(genes.loci[l]!.every((p) => p.first == l), true);
    }
    expect(genes.loci['B']!.length, 2);
    final p = RabbitColorPredictions.predict(sire: r, dam: r);
    expect(p.limitation, BreedColorContexts.rufusLimitation);
    expect(p.scope, contains('wideband/rufus'));
    expect(
      classifyChecklistEntry('Belgian Hare', 'Rufus')['status'],
      'shared_estimate',
    );
    expect(CoatRules.resolve(rabbit('Mini Rex', 'Rufus')), isNull);
  });

  test(
    'Tan and Californian groups require the actual pigment; all four contexts are checked',
    () {
      for (final (breed, variety, family) in [
        ('Belgian Hare', 'Tan', 'otter'),
        ('Satin', 'Californian', 'pointed white'),
      ]) {
        final group = rabbit(breed, variety);
        expect(
          RabbitColorPredictions.inputIssue(group, group),
          contains('actual color'),
        );
        expect(
          classifyChecklistEntry(breed, variety)['status'],
          'needs_details',
        );
        for (final base in ['Black', 'Blue', 'Chocolate', 'Lilac']) {
          final r = rabbit(breed, variety, {'color': base});
          final before = jsonEncode(r);
          final input = CoatRules.resolve(r)!;
          expect(input.family, family);
          if (base == 'Chocolate' || base == 'Lilac') {
            expect(input.loci['B']!.single.key, 'b/b');
          }
          if (base == 'Blue' || base == 'Lilac') {
            expect(input.loci['D']!.single.key, 'd/d');
          }
          final p = RabbitColorPredictions.predict(sire: r, dam: r);
          expect(p.scope, contains('uses the saved color details'));
          expect(p.colors, isNotEmpty);
          expect(jsonEncode(r), before);
        }
      }
      expect(
        CoatRules.resolve(
          rabbit('Belgian Hare', 'Tan', {'color': 'Blue Tan'}),
        )!.family,
        'otter',
      );
      expect(
        CoatRules.resolve(
          rabbit('Satin', 'Californian', {
            'color': 'Chocolate Himalayan',
            'pattern': 'Californian',
          }),
        )!.family,
        'pointed white',
      );
    },
  );

  test(
    'Conflicting descriptions cannot silently override the saved variety',
    () {
      for (final r in [
        rabbit('Belgian Hare', 'Rufus', {'color': 'Red'}),
        rabbit('Belgian Hare', 'Rufus', {'base_color': 'Blue'}),
        rabbit('Belgian Hare', 'Tan', {'color': 'Black', 'base_color': 'Blue'}),
        rabbit('Belgian Hare', 'Tan', {'color': 'Chestnut'}),
        rabbit('Satin', 'Californian', {
          'color': 'Black',
          'base_color': 'Blue',
        }),
        rabbit('Satin', 'Californian', {'color': 'Red'}),
        rabbit('Belgian Hare', 'Rufus', {'wideband': 'ww'}),
      ]) {
        expect(CoatRules.resolve(r), isNull, reason: '$r');
        expect(
          RabbitColorPredictions.inputIssue(r, r),
          isNotNull,
          reason: '$r',
        );
      }
      expect(
        CoatRules.resolve(rabbit('Satin', 'Siamese', {'color': 'Black'})),
        isNull,
      );
      expect(
        CoatRules.resolve(
          rabbit('Mini Rex', 'Californian', {'color': 'Black'}),
        ),
        isNull,
      );
    },
  );

  test(
    'Champagne applies only to the named Dwarf context and keeps a warning whichever parent has it',
    () {
      final champagne = rabbit('Netherland Dwarf', 'Champagne (COD)', {
        'color': 'Champagne',
        'pattern': 'Silvered',
      });
      final black = rabbit('Netherland Dwarf', 'Black');
      final before = jsonEncode(champagne);
      expect(SilveredBreedRules.appliesTo(champagne), true);
      expect(SilveredBreedRules.appliesTo(black), false);
      expect(CoatRules.resolve(champagne)!.family, 'self');
      final p = RabbitColorPredictions.predict(sire: champagne, dam: black);
      final reciprocal = RabbitColorPredictions.predict(
        sire: black,
        dam: champagne,
      );
      expect(colors(p), colors(reciprocal));
      expect(p.limitation, SilveredBreedRules.limitation);
      expect(reciprocal.limitation, SilveredBreedRules.limitation);
      expect(reciprocal.scope, contains('No silvering genotype is inferred'));
      expect(
        p.colors.every((c) => c.label.contains('silvering not predicted')),
        true,
      );
      expect(jsonEncode(champagne), before);
      final audit = classifyChecklistEntry(
        'Netherland Dwarf',
        'Champagne (COD)',
      );
      expect(audit['status'], 'silver_family_only');
      expect(audit['silvering_predictions_available'], false);
      expect(CoatRules.resolve(rabbit('Mini Rex', 'Champagne')), isNull);
      expect(
        CoatRules.resolve(
          rabbit('Netherland Dwarf', 'Champagne', {'base_color': 'Blue'}),
        ),
        isNull,
      );
      expect(
        RabbitColorPredictions.predict(sire: black, dam: black).limitation,
        isNull,
      );
    },
  );

  testWidgets(
    'Rufus warning is visible before and after calculation on mobile',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: GeneticsPreviewForm(
                animals: [
                  {
                    ...rabbit('Belgian Hare', 'Rufus'),
                    'id': 'b',
                    'name': 'Buck',
                    'sex': 'M',
                    'status': 'active',
                  },
                  {
                    ...rabbit('Belgian Hare', 'Tan', {'color': 'Chocolate'}),
                    'id': 'd',
                    'name': 'Doe',
                    'sex': 'F',
                    'status': 'active',
                  },
                ],
              ),
            ),
          ),
        ),
      );
      for (final i in [0, 1]) {
        final f = find.byType(DropdownButtonFormField<String>).at(i);
        await tester.ensureVisible(f);
        await tester.tap(f);
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining(i == 0 ? 'Buck' : 'Doe').last);
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('wideband/rufus'), findsOneWidget);
      final button = find.text('See Possible Colors');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text(BreedColorContexts.rufusLimitation), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
