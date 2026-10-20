import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/genetics/coat_rules.dart';
import 'package:ringmaster_breeder/genetics/color_prediction.dart';
import 'package:ringmaster_breeder/genetics/hotot_colors.dart';
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
  'status': 'active',
  if (details != null) 'color_details': details,
};
Map<String, (double, double)> chances(ColorPrediction p) => {
  for (final c in p.colors) c.label: (c.minimum, c.maximum),
};
const breeds = ['Dwarf Hotot', 'Blanc de Hotot'];

void main() {
  test(
    'Hotot B/D crosses agree with direct allele-copy inheritance for all 81 known pairs',
    () {
      const bs = ['BB', 'Bb', 'bb'], ds = ['DD', 'Dd', 'dd'];
      String color(String b, String d) => b == 'bb'
          ? d == 'dd'
                ? 'Lilac'
                : 'Chocolate'
          : d == 'dd'
          ? 'Blue'
          : 'Black';
      CarrierKnowledge knowledge(String gene) =>
          gene[0] != gene[1] ? CarrierKnowledge.yes : CarrierKnowledge.no;
      for (final breed in breeds) {
        for (final sb in bs) {
          for (final sd in ds) {
            for (final db in bs) {
              for (final dd in ds) {
                final s = rabbit(breed, color(sb, sd)),
                    d = rabbit(breed, color(db, dd));
                final expected = <String, double>{};
                for (final b1 in sb.split('')) {
                  for (final b2 in db.split('')) {
                    for (final d1 in sd.split('')) {
                      for (final d2 in dd.split('')) {
                        final b = ([b1, b2]..sort()).join();
                        final dense = ([d1, d2]..sort()).join();
                        expected.update(
                          '${color(b, dense)} base pigment',
                          (v) => v + 1 / 16,
                          ifAbsent: () => 1 / 16,
                        );
                      }
                    }
                  }
                }
                final sc = ColorCarrierDetails(
                  chocolate: knowledge(sb),
                  dilute: knowledge(sd),
                );
                final dc = ColorCarrierDetails(
                  chocolate: knowledge(db),
                  dilute: knowledge(dd),
                );
                final result = RabbitColorPredictions.predict(
                  sire: s,
                  dam: d,
                  sireCarriers: sc,
                  damCarriers: dc,
                );
                expect(chances(result), {
                  for (final e in expected.entries) e.key: (e.value, e.value),
                });
                expect(result.colors.fold(0.0, (sum, c) => sum + c.maximum), 1);
                expect(
                  chances(result),
                  chances(
                    RabbitColorPredictions.predict(
                      sire: d,
                      dam: s,
                      sireCarriers: dc,
                      damCarriers: sc,
                    ),
                  ),
                );
                expect(result.markings, isEmpty);
                expect(result.limitation, HototColorRules.limitation);
              }
            }
          }
        }
      }
    },
  );

  test(
    'Unknown carriers stay ranges and even a certain pigment makes no marking promise',
    () {
      for (final breed in breeds) {
        final black = rabbit(breed, 'Black');
        expect(
          chances(RabbitColorPredictions.predict(sire: black, dam: black)),
          {
            'Black base pigment': (9 / 16, 1.0),
            'Blue base pigment': (0.0, .25),
            'Chocolate base pigment': (0.0, .25),
            'Lilac base pigment': (0.0, 1 / 16),
          },
        );
        final lilac = rabbit(breed, 'Lilac');
        final result = RabbitColorPredictions.predict(sire: lilac, dam: lilac);
        expect(chances(result), {'Lilac base pigment': (1.0, 1.0)});
        expect(
          result.scope,
          contains('does not predict whether eye bands will appear'),
        );
        expect(
          result.scope,
          contains('100% pigment result does not guarantee'),
        );
        expect(result.markings, isEmpty);
        expect(RabbitColorPredictions.carrierLoci(black), {'B', 'D'});
        expect(RabbitColorPredictions.carrierLoci(lilac), isEmpty);
        expect(
          CoatRules.resolve(black),
          isNull,
        ); // Full-coat fallback stays guarded.
      }
    },
  );

  test(
    'Standard and group labels are explicit pigment interpretations without rewriting records',
    () {
      final standard = rabbit('Blanc de Hotot', 'Standard');
      final black = rabbit('Blanc de Hotot', 'Black');
      expect(
        chances(RabbitColorPredictions.predict(sire: standard, dam: standard)),
        chances(RabbitColorPredictions.predict(sire: black, dam: black)),
      );
      expect(
        RabbitColorPredictions.scopeFor(standard, standard),
        contains('Standard: black eye-band base pigment only'),
      );
      for (final label in ['White', 'Standard', 'Black/Blue/Chocolate/Lilac']) {
        final r = rabbit('Dwarf Hotot', label, {
          'color': 'Blue',
          'pattern': 'Hotot',
          'eye_color': 'Blue Gray',
        });
        final before = jsonEncode(r);
        final plain = rabbit('Dwarf Hotot', 'Blue');
        expect(
          chances(RabbitColorPredictions.predict(sire: r, dam: r)),
          chances(RabbitColorPredictions.predict(sire: plain, dam: plain)),
        );
        expect(jsonEncode(r), before);
        expect(
          RabbitColorPredictions.inputIssue(
            rabbit('Dwarf Hotot', label),
            plain,
          ),
          isNotNull,
        );
      }
      final alias = rabbit(' DWARF HOTOT (COD) ', 'Blue Eye Bands (COD)');
      expect(
        RabbitColorPredictions.inputIssue(alias, rabbit('Dwarf Hotot', 'Blue')),
        isNull,
      );
      final audit = classifyChecklistEntry('Blanc de Hotot', 'Standard');
      expect(audit['status'], 'eyeband_pigment_only');
      expect(audit['marking_predictions_available'], false);
      expect(audit['breed_validation_complete'], false);
      expect(audit['interpreted_pigment_label'], 'black');
      expect(
        classifyChecklistEntry(
          'Dwarf Hotot',
          'Black/Blue/Chocolate/Lilac',
        )['status'],
        'needs_details',
      );
    },
  );

  test(
    'Pattern and blue-eye annotations do not imply English spotting, Dutch or Vienna genotypes',
    () {
      final plain = rabbit('Dwarf Hotot', 'Black');
      for (final pattern in [
        'Hotot',
        'Eye bands',
        'Solid',
        'Spotted',
        'Charlie',
        'Dutch',
      ]) {
        final r = rabbit('Dwarf Hotot', 'Black', {
          'pattern': pattern,
          'eye_color': 'Blue',
        });
        final result = RabbitColorPredictions.predict(sire: r, dam: r);
        expect(
          chances(result),
          chances(RabbitColorPredictions.predict(sire: plain, dam: plain)),
        );
        expect(result.markings, isEmpty);
        expect(result.colors.any((c) => c.label.contains('White')), false);
        expect(CoatRules.resolve(r), isNull);
      }
    },
  );

  test(
    'Contradictory, missing, unsupported and mixed records show an error instead of a coat fallback',
    () {
      final invalid = [
        rabbit('Dwarf Hotot', ''),
        rabbit('Dwarf Hotot', 'White'),
        rabbit('Dwarf Hotot', 'Ruby Eyed White'),
        rabbit('Dwarf Hotot', 'Broken Black'),
        rabbit('Dwarf Hotot', 'Tortoise'),
        rabbit('Hotot', 'Black'),
        rabbit('Dwarf Hotot', 'Black', {'color': 'Blue'}),
        rabbit('Dwarf Hotot', 'Black', {'color': 'White'}),
        rabbit('Blanc de Hotot', 'Standard', {'base_color': 'Chocolate'}),
        rabbit('Dwarf Hotot', 'Black/Blue/Chocolate/Lilac', {
          'color': 'Blue',
          'base_color': 'Chocolate',
        }),
        rabbit('Dwarf Hotot', 'Black', {'pattern': 'Tortoise'}),
        rabbit('Dwarf Hotot', 'Black', {'eye_color': 'Red'}),
        rabbit('Dwarf Hotot', 'Black', {'tipping': 'Silver'}),
        {...rabbit('Dwarf Hotot', 'Black'), 'species': 'cavy'},
      ];
      for (final r in invalid) {
        expect(
          RabbitColorPredictions.inputIssue(r, r),
          isNotNull,
          reason: '$r',
        );
        expect(
          () => RabbitColorPredictions.predict(sire: r, dam: r),
          throwsArgumentError,
        );
      }
      expect(
        RabbitColorPredictions.inputIssue(
          rabbit('Dwarf Hotot', 'Black'),
          rabbit('Blanc de Hotot', 'Standard'),
        ),
        isNotNull,
      );
    },
  );

  testWidgets(
    'Mobile pigment cards keep the limitation visible at 100%; missing pigment shows support',
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
                    ...rabbit('Dwarf Hotot', 'Lilac'),
                    'id': 'b',
                    'sex': 'M',
                    'name': 'Lilac Buck',
                  },
                  {
                    ...rabbit('Dwarf Hotot', 'Lilac'),
                    'id': 'd',
                    'sex': 'F',
                    'name': 'Lilac Doe',
                  },
                  {
                    ...rabbit('Dwarf Hotot', 'White'),
                    'id': 'u',
                    'sex': 'F',
                    'name': 'Missing Pigment',
                  },
                ],
              ),
            ),
          ),
        ),
      );
      for (final i in [0, 1]) {
        final field = find.byType(DropdownButtonFormField<String>).at(i);
        await tester.ensureVisible(field);
        await tester.tap(field);
        await tester.pumpAndSettle();
        await tester.tap(find.text(i == 0 ? 'Lilac Buck' : 'Lilac Doe').last);
        await tester.pumpAndSettle();
      }
      expect(
        find.textContaining('does not predict whether eye bands will appear'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('See Possible Colors'));
      await tester.tap(find.text('See Possible Colors'));
      await tester.pumpAndSettle();
      expect(
        find.text('Dwarf Hotot eye-band pigment estimates'),
        findsOneWidget,
      );
      expect(find.text('Eye-band pigment only'), findsOneWidget);
      expect(find.text(HototColorRules.limitation), findsOneWidget);
      expect(find.text('Lilac base pigment'), findsOneWidget);
      expect(find.text('100%'), findsWidgets);
      expect(find.text('Spotting inheritance'), findsNothing);
      expect(find.textContaining('not guarantees'), findsWidgets);
      final doe = find.byType(DropdownButtonFormField<String>).last;
      await tester.ensureVisible(doe);
      await tester.tap(doe);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Missing Pigment').last);
      await tester.pumpAndSettle();
      expect(find.text('Prediction unavailable'), findsOneWidget);
      expect(find.textContaining('support@ringmasterone.com'), findsOneWidget);
      expect(find.text('Lilac base pigment'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
