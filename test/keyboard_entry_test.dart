import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/widgets/catalog_field.dart';
import 'package:ringmaster_breeder/widgets/dob_field.dart';
import 'package:ringmaster_breeder/widgets/sex_field.dart';

void main() {
  for (final breed in [null, 'Mini Lop']) {
    testWidgets(
      'Arrows and Enter select highlighted ${breed == null ? 'breed' : 'variety'}',
      (tester) async {
        String selected = '';
        final nextFocus = FocusNode();
        addTearDown(nextFocus.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  CatalogField(
                    species: 'rabbit',
                    breed: breed,
                    value: '',
                    onChanged: (v) => selected = v,
                    loadOptions: (_, __) async => List.generate(
                      20,
                      (i) => {'name': 'Choice $i', 'is_recognized': true},
                    ),
                  ),
                  TextField(focusNode: nextFocus),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(TextFormField));
        await tester.enterText(find.byType(TextFormField), 'Choice');
        await tester.pumpAndSettle();
        for (var i = 0; i < 8; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
        }
        expect(
          tester
              .widget<ListTile>(find.widgetWithText(ListTile, 'Choice 8'))
              .selected,
          isTrue,
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(selected, 'Choice 8');
        expect(nextFocus.hasFocus, isTrue);
        expect(find.byType(ListTile), findsNothing);
      },
    );
  }
  testWidgets('Sex supports arrow selection and Enter', (tester) async {
    String selected = 'Buck';
    final nextFocus = FocusNode();
    addTearDown(nextFocus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SexField(
                species: 'rabbit',
                value: selected,
                onChanged: (v) => selected = v,
              ),
              TextField(focusNode: nextFocus),
            ],
          ),
        ),
      ),
    );
    tester
        .widget<TextField>(find.byType(TextField).first)
        .focusNode!
        .requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(selected, 'Doe');
    expect(nextFocus.hasFocus, isTrue);
  });
  testWidgets(
    'DOB inserts slashes, rejects impossible dates and supports calendar',
    (tester) async {
      String value = '';
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DobField(value: '', onChanged: (v) => value = v),
          ),
        ),
      );
      await tester.enterText(find.byType(TextFormField), '02292024');
      await tester.pumpAndSettle();
      expect(find.text('02/29/2024'), findsOneWidget);
      expect(value, '2024-02-29');
      await tester.enterText(find.byType(TextFormField), '02302024');
      await tester.pumpAndSettle();
      expect(find.text('Enter a valid date as MM/DD/YYYY'), findsOneWidget);
      await tester.tap(find.byTooltip('Choose date of birth'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(dobError(value), isNull);
    },
  );
  test(
    'DOB formatter supports backspace over separator and mid-text edits',
    () {
      final f = DobFormatter();
      expect(
        f
            .formatEditUpdate(
              const TextEditingValue(text: '12/31/2020'),
              const TextEditingValue(
                text: '1231/2020',
                selection: TextSelection.collapsed(offset: 2),
              ),
            )
            .text,
        '13/12/020',
      );
      expect(
        f
            .formatEditUpdate(
              TextEditingValue.empty,
              const TextEditingValue(
                text: '01012020',
                selection: TextSelection.collapsed(offset: 8),
              ),
            )
            .text,
        '01/01/2020',
      );
      expect(dobError('02/29/2023'), isNotNull);
    },
  );
}
