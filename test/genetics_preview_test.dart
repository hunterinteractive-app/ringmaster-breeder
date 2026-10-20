import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/config/genetics_preview.dart';
import 'package:ringmaster_breeder/screens/animal_list_screen.dart';
import 'package:ringmaster_breeder/screens/genetics_screen.dart';

void main() {
  test('Genetics preview allows only the designated signed-in email', () {
    expect(GeneticsPreview.allowsEmail('zaynetort2@gmail.com'), isTrue);
    expect(GeneticsPreview.allowsEmail(' ZayneTort2@Gmail.com '), isTrue);
    for (final email in [
      null,
      '',
      'other@gmail.com',
      'zaynetort2@gmail.com.evil',
    ]) {
      expect(GeneticsPreview.allowsEmail(email), isFalse);
    }
  });

  for (final allowed in [false, true]) {
    testWidgets('Actions Genetics visibility: $allowed', (tester) async {
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimalBrowser(
              animals: const [],
              onAdd: () {},
              onRefresh: () {},
              onOpen: (_) {},
              onGenetics: allowed ? () => opened = true : null,
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Actions'));
      await tester.pumpAndSettle();
      expect(find.text('Genetics'), allowed ? findsOneWidget : findsNothing);
      if (allowed) {
        await tester.tap(find.text('Genetics'));
        await tester.pumpAndSettle();
        expect(opened, isTrue);
      }
    });
  }

  testWidgets(
    'Preview calculates Tan colors with visible scope and uncertainty',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, dynamic> rabbit(String id, String sex) => {
        'id': id,
        'name': id,
        'sex': sex,
        'species': 'rabbit',
        'status': 'active',
        'breed': 'Tan',
        'variety': 'Chocolate',
        'dob': '2025-04-03',
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: GeneticsPreviewForm(
                  animals: [
                    rabbit('Buck', 'M'),
                    rabbit('Doe', 'F'),
                    {...rabbit('Other breed', 'M'), 'breed': 'Rex'},
                    rabbit('Unknown sex', ''),
                    {...rabbit('Cavy', 'M'), 'species': 'cavy'},
                    {...rabbit('Sold', 'M'), 'status': 'sold'},
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text(GeneticsPreview.disclaimer), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.byWidgetPredicate((w) => w is FilledButton),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      expect(find.text('Breed: Tan • Variety: Chocolate'), findsWidgets);
      expect(find.text('DOB: 04/03/2025'), findsWidgets);
      expect(find.text('Rabbit • Buck • Active'), findsWidgets);
      expect(find.text('Unknown sex'), findsNothing);
      expect(find.text('Cavy'), findsNothing);
      expect(find.text('Sold'), findsNothing);
      await tester.tap(find.text('Buck').last);
      await tester.pumpAndSettle();
      expect(find.text('Breed: Tan • Variety: Chocolate'), findsOneWidget);
      await tester.ensureVisible(
        find.byType(DropdownButtonFormField<String>).last,
      );
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Doe').last);
      await tester.pumpAndSettle();
      expect(find.text('Breed: Tan • Variety: Chocolate'), findsNWidgets(2));
      expect(find.text('Rabbit • Doe • Active'), findsOneWidget);
      final calculate = find.text('See Possible Colors');
      await tester.ensureVisible(calculate);
      await tester.tap(calculate);
      await tester.pumpAndSettle();
      expect(find.text('Tan coat-color estimates'), findsOneWidget);
      expect(find.text('Otter / tan pattern (chocolate base)'), findsOneWidget);
      expect(find.text('White (eye color not predicted)'), findsOneWidget);
      expect(find.textContaining('not fixed odds'), findsOneWidget);
      expect(find.text(GeneticsPreview.disclaimer), findsNWidgets(2));

      // Known dilute carriers still leave other hidden genes unknown; editing
      // either parent must invalidate the old prediction.
      final optional = find.text('Optional: known carrier information');
      for (final index in [0, 1]) {
        await tester.ensureVisible(optional.at(index));
        await tester.tap(optional.at(index));
        await tester.pumpAndSettle();
        final carrierField = find.byKey(
          ValueKey('${index == 0 ? 'Buck' : 'Doe'}-${index == 0}-D'),
        );
        await tester.ensureVisible(carrierField);
        await tester.tap(carrierField);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Yes — known carrier').last);
        await tester.pumpAndSettle();
        expect(find.text('Tan coat-color estimates'), findsNothing);
      }
      await tester.ensureVisible(calculate);
      await tester.tap(calculate);
      await tester.pumpAndSettle();
      expect(find.text('White (eye color not predicted)'), findsOneWidget);
      expect(find.textContaining('not fixed odds'), findsOneWidget);
      expect(find.text('75%'), findsNothing);

      // Selecting an unsupported parent must clear the old estimate and block
      // recalculation rather than silently applying the Tan rules.
      final buckField = find.byType(DropdownButtonFormField<String>).first;
      await tester.ensureVisible(buckField);
      await tester.tap(buckField);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other breed').last);
      await tester.pumpAndSettle();
      expect(find.text('Tan coat-color estimates'), findsNothing);
      expect(find.text('Prediction unavailable'), findsOneWidget);
      expect(find.textContaining('support@ringmasterone.com'), findsOneWidget);
      expect(
        find.textContaining('Mixed-breed predictions are not available yet.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byWidgetPredicate((w) => w is FilledButton),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
