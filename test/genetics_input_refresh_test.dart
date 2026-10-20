import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/genetics/color_prediction.dart';
import 'package:ringmaster_breeder/screens/genetics_screen.dart';
import 'package:ringmaster_breeder/widgets/genetics_prediction_results.dart';

void main() {
  testWidgets(
    'Changed parent facts clear estimates and carriers; removed or inactive parents clear selection',
    (tester) async {
      final animals = <Map<String, dynamic>>[
        {
          'id': 'buck',
          'name': 'Buck',
          'species': 'rabbit',
          'sex': 'M',
          'status': 'active',
          'breed': 'Tan',
          'variety': 'Black',
        },
        {
          'id': 'doe',
          'name': 'Doe',
          'species': 'rabbit',
          'sex': 'F',
          'status': 'active',
          'breed': 'Tan',
          'variety': 'Black',
        },
      ];
      Future<void> render() async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: GeneticsPreviewForm(animals: animals),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> choose(Finder field, String label) async {
        await tester.ensureVisible(field);
        await tester.tap(field);
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
      }

      Future<void> calculate() async {
        final button = find.text('See Possible Colors');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.byType(GeneticsPredictionResults), findsOneWidget);
      }

      await render();
      await choose(find.byType(DropdownButtonFormField<String>).first, 'Buck');
      await choose(find.byType(DropdownButtonFormField<String>).last, 'Doe');
      final optional = find.text('Optional: known carrier information').first;
      await tester.ensureVisible(optional);
      await tester.tap(optional);
      await tester.pumpAndSettle();
      await choose(
        find.byKey(const ValueKey('buck-true-v')),
        'Yes — known carrier',
      );
      await calculate();

      // An unrelated label edit leaves the calculation and temporary facts alone.
      animals[0]['name'] = 'Renamed buck';
      await render();
      expect(find.byType(GeneticsPredictionResults), findsOneWidget);

      // The same map/list can be mutated by refresh; compare retained values,
      // rather than oldWidget.animals (which now points to the changed objects).
      animals[0]['variety'] = 'Blue';
      await render();
      expect(find.byType(GeneticsPredictionResults), findsNothing);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>).first,
            )
            .initialValue,
        'buck',
      );
      final refreshedOptional = find
          .text('Optional: known carrier information')
          .first;
      await tester.ensureVisible(refreshedOptional);
      await tester.tap(refreshedOptional);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButtonFormField<CarrierKnowledge>>(
              find.byKey(const ValueKey('buck-true-v')),
            )
            .initialValue,
        CarrierKnowledge.unknown,
      );
      await calculate();

      animals[0]['genotype'] = {'notation': 'dd', 'basis': 'breeder_entered'};
      await render();
      expect(find.byType(GeneticsPredictionResults), findsNothing);
      await calculate();
      (animals[0]['genotype'] as Map)['notation'] = 'DD';
      await render();
      expect(find.byType(GeneticsPredictionResults), findsNothing);
      expect(find.text('Prediction unavailable'), findsOneWidget);
      animals[0].remove('genotype');
      await render();
      await calculate();

      animals[0]['color_details'] = {'base_color': 'Blue'};
      await render();
      expect(find.byType(GeneticsPredictionResults), findsNothing);
      await calculate();
      (animals[0]['color_details'] as Map)['base_color'] = 'Black';
      await render();
      expect(find.byType(GeneticsPredictionResults), findsNothing);
      expect(find.text('Prediction unavailable'), findsOneWidget);

      animals[0]['status'] = 'sold';
      await render();
      expect(find.byType(GeneticsPredictionResults), findsNothing);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>).first,
            )
            .initialValue,
        isNull,
      );
      expect(
        find.text('Choose a buck and a doe to see possible colors.'),
        findsOneWidget,
      );
      animals.removeAt(1);
      await render();
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>).last,
            )
            .initialValue,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
