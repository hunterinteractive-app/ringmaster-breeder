import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/genetics/breed_color_contexts.dart';
import 'package:ringmaster_breeder/genetics/coat_rules.dart';
import 'package:ringmaster_breeder/genetics/coat_solver.dart';
import 'package:ringmaster_breeder/genetics/color_prediction.dart';
import 'package:ringmaster_breeder/genetics/mendelian.dart';
import 'package:ringmaster_breeder/screens/genetics_screen.dart';
import '../tool/genetics_coverage_checklist.dart';

Map<String, dynamic> rabbit(String color, [Map<String, String>? details]) => {
  'species': 'rabbit',
  'breed': 'Flemish Giant',
  'variety': color,
  if (details != null) 'color_details': details,
};
Map<String, (double, double)> ranges(ColorPrediction p) => {
  for (final c in p.colors) c.label: (c.minimum, c.maximum),
};
Map<String, (double, double)> solved(SharedCoatPrediction p) => {
  for (final c in p.colors) c.outcome.label: (c.minimum, c.maximum),
};

void main() {
  test('Light Gray is conditional chinchilla with hidden genes unresolved', () {
    final r = rabbit('Light Gray');
    final input = CoatRules.resolve(r)!;
    expect(input.family, 'chinchilla');
    expect(input.loci['A']!.map((p) => p.key), ['A/A', 'A/at', 'A/a']);
    expect(input.loci['B']!.map((p) => p.key), ['B/B', 'B/b']);
    expect(input.loci['C']!.map((p) => p.key), [
      'cchd/cchd',
      'cchd/cchl',
      'cchd/ch',
      'c/cchd',
    ]);
    expect(input.loci['D']!.length, 2);
    expect(input.loci['E']!.length, 3);
    final prediction = RabbitColorPredictions.predict(sire: r, dam: r);
    expect(prediction.colors.any((c) => c.label.startsWith('White')), true);
    expect(prediction.colors.any((c) => c.minimum < c.maximum), true);
    expect(
      classifyChecklistEntry('Flemish Giant', 'Light Gray')['status'],
      'shared_estimate',
    );
    expect(
      ranges(
        RabbitColorPredictions.predict(sire: rabbit('Light Grey'), dam: r),
      ),
      ranges(prediction),
    );
  });

  test(
    'Explicit Evans sire comparison and albino-carrier cross are conditional',
    () {
      final input = CoatRules.resolve(rabbit('Light Gray'))!;
      final specified = <String, List<AllelePair>>{
        'A': [const AllelePair('A', 'A')],
        'B': [const AllelePair('B', 'B')],
        'C': [const AllelePair('cchd', 'cchd')],
        'D': [const AllelePair('D', 'D')],
        'E': [const AllelePair('E', 'E')],
        'V': [const AllelePair('V', 'V')],
      };
      for (final e in specified.entries) {
        expect(
          input.loci[e.key]!.map((p) => p.key),
          contains(e.value.single.key),
        );
      }
      final sire = CoatInput('explicit reference sire', {
        ...input.loci,
        ...specified,
      }, input.family);
      // Evans omits Vienna in this reference: one known VV parent prevents
      // its white effect here. These genes are test inputs, never record defaults.
      expect(solved(solveCoats(sire, input)), {'Chinchilla': (1.0, 1.0)});
      final carrier = CoatInput('albino carrier', {
        ...sire.loci,
        'C': [const AllelePair('cchd', 'c')],
      }, input.family);
      final albino = CoatInput('explicit albino', {
        ...sire.loci,
        'C': [const AllelePair('c', 'c')],
      }, 'white');
      expect(solved(solveCoats(carrier, albino)), {
        'Chinchilla': (.5, .5),
        'White (eye color not predicted)': (.5, .5),
      });
    },
  );

  test(
    'Supported Flemish crosses retain source records and either-parent notice',
    () {
      final light = rabbit('Light Gray');
      for (final other in [
        rabbit('Black'),
        rabbit('Blue'),
        rabbit('Fawn'),
        light,
        rabbit('White', {'eye_color': 'Red'}),
      ]) {
        final before = jsonEncode([light, other]);
        final forward = RabbitColorPredictions.predict(sire: light, dam: other);
        final reverse = RabbitColorPredictions.predict(sire: other, dam: light);
        expect(ranges(forward), ranges(reverse));
        for (final p in [forward, reverse]) {
          expect(p.scope, contains('black chinchilla family'));
          expect(p.limitation, BreedColorContexts.lightGrayLimitation);
        }
        expect(jsonEncode([light, other]), before);
      }
    },
  );

  test(
    'Contradictions block estimates and Flemish family limits stay explicit',
    () {
      for (final details in [
        {'color': 'Blue'},
        {'base_color': 'Chocolate'},
        {'pattern': 'Self'},
        {'color': 'Steel'},
        {'wideband': 'ww'},
      ]) {
        final r = rabbit('Light Gray', details), before = jsonEncode(details);
        expect(CoatRules.resolve(r), isNull);
        expect(
          () => RabbitColorPredictions.predict(sire: r, dam: r),
          throwsArgumentError,
        );
        expect(jsonEncode(details), before);
      }
      expect(
        CoatRules.resolve({...rabbit('Light Gray'), 'breed': 'Mini Rex'}),
        isNull,
      );
      for (final name in ['Sandy', 'Steel Gray']) {
        final r = rabbit(name);
        expect(CoatRules.resolve(r), isNotNull);
        expect(RabbitColorPredictions.inputIssue(r, r), isNull);
        expect(
          RabbitColorPredictions.predict(sire: r, dam: r).limitation,
          name == 'Sandy'
              ? BreedColorContexts.sandyLimitation
              : BreedColorContexts.steelLimitation,
        );
      }
      expect(
        CoatRules.resolve(rabbit('Light Gray', {'color': 'Light Gray'})),
        isNotNull,
      );
    },
  );

  testWidgets(
    'Light Gray appearance limit is visible before and after prediction',
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
                    ...rabbit('Light Gray'),
                    'id': 'b',
                    'name': 'Buck',
                    'sex': 'M',
                    'status': 'active',
                  },
                  {
                    ...rabbit('Black'),
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
        final selector = find.byType(DropdownButtonFormField<String>).at(i);
        await tester.ensureVisible(selector);
        await tester.tap(selector);
        await tester.pumpAndSettle();
        await tester.tap(find.textContaining(i == 0 ? 'Buck' : 'Doe').last);
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('ring definition'), findsOneWidget);
      final button = find.text('See Possible Colors');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text(BreedColorContexts.lightGrayLimitation), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
