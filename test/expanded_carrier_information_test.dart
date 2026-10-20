import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/genetics/color_prediction.dart';
import 'package:ringmaster_breeder/screens/genetics_screen.dart';

Map<String, dynamic> rabbit(
  String id,
  String sex, {
  String breed = 'Tan',
  String variety = 'Black',
}) => {
  'id': id,
  'name': id,
  'sex': sex,
  'species': 'rabbit',
  'status': 'active',
  'breed': breed,
  'variety': variety,
};
Map<String, (double, double)> ranges(ColorPrediction p) => {
  for (final c in p.colors) c.label: (c.minimum, c.maximum),
};

void main() {
  test(
    'Albino and Vienna facts independently narrow white masking without record writes',
    () {
      final r = rabbit('Buck', 'M'), before = jsonEncode(r);
      ColorPrediction predict(ColorCarrierDetails facts) =>
          RabbitColorPredictions.predict(
            sire: r,
            dam: r,
            sireCarriers: facts,
            damCarriers: facts,
          );
      final unknown = predict(const ColorCarrierDetails());
      expect(ranges(unknown)['White (eye color not predicted)'], (0, 7 / 16));
      final both = predict(
        const ColorCarrierDetails(
          albino: CarrierKnowledge.yes,
          vienna: CarrierKnowledge.yes,
        ),
      );
      expect(ranges(both)['White (eye color not predicted)'], (7 / 16, 7 / 16));
      final albino = predict(
        const ColorCarrierDetails(
          albino: CarrierKnowledge.yes,
          vienna: CarrierKnowledge.no,
        ),
      );
      expect(ranges(albino)['White (eye color not predicted)'], (.25, .25));
      final neither = predict(
        const ColorCarrierDetails(
          albino: CarrierKnowledge.no,
          vienna: CarrierKnowledge.no,
        ),
      );
      expect(
        ranges(neither).containsKey('White (eye color not predicted)'),
        false,
      );
      for (final p in [both, albino, neither]) {
        expect(p.scenarioCount, lessThan(unknown.scenarioCount));
        for (final c in p.colors) {
          final bounds = ranges(unknown)[c.label]!;
          expect(c.minimum, greaterThanOrEqualTo(bounds.$1));
          expect(c.maximum, lessThanOrEqualTo(bounds.$2));
        }
      }
      expect(
        both.unresolvedInformation.join(' '),
        isNot(contains('Vienna-white')),
      );
      expect(
        both.parentInterpretations.join(' '),
        contains('modeled as black otter'),
      );
      expect(jsonEncode(r), before);
    },
  );

  test(
    'Self and Harlequin carrier facts narrow their own traits and retain other unknowns',
    () {
      final r = rabbit('Buck', 'M');
      final normal = RabbitColorPredictions.predict(sire: r, dam: r);
      final noSelf = RabbitColorPredictions.predict(
        sire: r,
        dam: r,
        sireCarriers: const ColorCarrierDetails(
          selfPattern: CarrierKnowledge.no,
        ),
        damCarriers: const ColorCarrierDetails(
          selfPattern: CarrierKnowledge.no,
        ),
      );
      expect(noSelf.colors.where((c) => c.label == 'Black'), isEmpty);
      expect(
        noSelf.unresolvedInformation.join(' '),
        isNot(contains('pattern genes')),
      );
      final noHarlequin = RabbitColorPredictions.predict(
        sire: r,
        dam: r,
        sireCarriers: const ColorCarrierDetails(harlequin: CarrierKnowledge.no),
        damCarriers: const ColorCarrierDetails(harlequin: CarrierKnowledge.no),
      );
      expect(
        noHarlequin.colors.where(
          (c) => RegExp('Harlequin|harlequin|Magpie').hasMatch(c.label),
        ),
        isEmpty,
      );
      expect(noHarlequin.scenarioCount, lessThan(normal.scenarioCount));
      expect(noHarlequin.hasRanges, true);
      final yes = RabbitColorPredictions.predict(
        sire: r,
        dam: r,
        sireCarriers: const ColorCarrierDetails(
          harlequin: CarrierKnowledge.yes,
        ),
        damCarriers: const ColorCarrierDetails(harlequin: CarrierKnowledge.yes),
      );
      expect(
        yes.colors.any((c) => c.label.contains('Harlequin') && c.maximum > 0),
        true,
      );
    },
  );

  test('Contradictory temporary E carrier facts fail with useful guidance', () {
    final r = rabbit('Buck', 'M');
    const conflict = ColorCarrierDetails(
      tortoise: CarrierKnowledge.yes,
      harlequin: CarrierKnowledge.yes,
    );
    for (final male in [true, false]) {
      final issue = RabbitColorPredictions.carrierIssue(
        r,
        r,
        sireCarriers: male ? conflict : const ColorCarrierDetails(),
        damCarriers: male ? const ColorCarrierDetails() : conflict,
      );
      expect(issue, startsWith(male ? 'Buck:' : 'Doe:'));
      expect(issue, contains('support@ringmasterone.com'));
      expect(
        () => RabbitColorPredictions.predict(
          sire: r,
          dam: r,
          sireCarriers: male ? conflict : const ColorCarrierDetails(),
          damCarriers: male ? const ColorCarrierDetails() : conflict,
        ),
        throwsArgumentError,
      );
    }
    expect(
      RabbitColorPredictions.carrierIssue(
        r,
        r,
        sireCarriers: const ColorCarrierDetails(
          harlequin: CarrierKnowledge.yes,
        ),
      ),
      isNull,
    );
  });

  test('New questions are absent for fixed, masked or restricted traits', () {
    final self = rabbit('B', 'M', breed: 'Havana');
    expect(RabbitColorPredictions.carrierLoci(self), isNot(contains('a')));
    final rew = rabbit('B', 'M', breed: 'Polish', variety: 'Ruby Eyed White');
    expect(RabbitColorPredictions.carrierLoci(rew), isEmpty);
    final hotot = rabbit('B', 'M', breed: 'Dwarf Hotot');
    expect(RabbitColorPredictions.carrierLoci(hotot), {'B', 'D'});
    const first = ColorCarrierDetails(
      albino: CarrierKnowledge.yes,
      vienna: CarrierKnowledge.no,
      selfPattern: CarrierKnowledge.yes,
      harlequin: CarrierKnowledge.no,
    );
    final copied = first.copyWith(dilute: CarrierKnowledge.yes);
    expect(copied.albino, first.albino);
    expect(copied.vienna, first.vienna);
    expect(copied.selfPattern, first.selfPattern);
    expect(copied.harlequin, first.harlequin);
  });

  testWidgets(
    'Mobile carrier conflicts block calculation and parent changes reset all facts',
    (tester) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final animals = [
        rabbit('Buck', 'M'),
        rabbit('Doe', 'F'),
        rabbit('Other buck', 'M'),
      ];
      final before = jsonEncode(animals);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: GeneticsPreviewForm(animals: animals),
              ),
            ),
          ),
        ),
      );
      Future<void> choose(Finder field, String label) async {
        await tester.ensureVisible(field);
        await tester.tap(field);
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }

      await choose(find.byType(DropdownButtonFormField<String>).first, 'Buck');
      await choose(find.byType(DropdownButtonFormField<String>).last, 'Doe');
      final optional = find.text('Optional: known carrier information').first;
      await tester.ensureVisible(optional);
      await tester.tap(optional);
      await tester.pumpAndSettle();
      await choose(
        find.byKey(const ValueKey('Buck-true-ej')),
        'Yes — known carrier',
      );
      await choose(
        find.byKey(const ValueKey('Buck-true-E')),
        'Yes — known carrier',
      );
      final calculate = find.byWidgetPredicate((w) => w is FilledButton);
      expect(tester.widget<FilledButton>(calculate).onPressed, isNull);
      expect(
        find.textContaining('selected known carrier information conflicts'),
        findsOneWidget,
      );
      await choose(find.byKey(const ValueKey('Buck-true-E')), 'Unknown');
      await choose(
        find.byKey(const ValueKey('Buck-true-v')),
        'No — known non-carrier',
      );
      await tester.ensureVisible(calculate);
      await tester.tap(calculate);
      await tester.pumpAndSettle();
      expect(find.text('Tan coat-color estimates'), findsOneWidget);
      expect(
        find.textContaining('A color family groups related appearances'),
        findsOneWidget,
      );
      final explanation = find.text('What affects these estimates?');
      await tester.ensureVisible(explanation);
      await tester.tap(explanation);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Buck: Tan — Black; modeled as'),
        findsOneWidget,
      );
      expect(find.textContaining('remain unknown.'), findsNWidgets(2));
      await choose(
        find.byType(DropdownButtonFormField<String>).first,
        'Other buck',
      );
      expect(find.text('Tan coat-color estimates'), findsNothing);
      final other = find.text('Optional: known carrier information').first;
      await tester.ensureVisible(other);
      await tester.tap(other);
      await tester.pumpAndSettle();
      final dropdown = tester.widget<DropdownButtonFormField<CarrierKnowledge>>(
        find.byKey(const ValueKey('Other buck-true-v')),
      );
      expect(dropdown.initialValue, CarrierKnowledge.unknown);
      expect(jsonEncode(animals), before);
      expect(tester.takeException(), isNull);
    },
  );
}
