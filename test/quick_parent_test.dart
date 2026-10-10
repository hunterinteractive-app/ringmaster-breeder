import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/widgets/parent_picker.dart';

void main() {
  testWidgets(
    'Quick parent stages core details, reuses duplicates and cancels safely',
    (tester) async {
      Map<String, dynamic>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text('Open'),
                onPressed: () async {
                  result = await showDialog<Map<String, dynamic>>(
                    context: context,
                    builder: (_) => QuickParentDialog(
                      label: 'Sire',
                      species: 'cavy',
                      sex: 'Boar',
                      breed: 'Abyssinian',
                      existing: const [
                        {'id': 'old', 'name': null, 'tattoo': 'EAR1'},
                      ],
                      loadOptions: (_, __) async => [],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Cavy • Boar'), findsOneWidget);
      await tester.tap(find.text('Use sire'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a name or ear number.'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ear number / tag'),
        'NEW1',
      );
      await tester.tap(find.text('Use sire'));
      await tester.pumpAndSettle();
      expect(result?['tattoo'], 'NEW1');
      expect(result?['sex'], 'Boar');
      expect(result?['breed'], 'Abyssinian');
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Ear number / tag'),
        'ear1',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use sire'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.ensureVisible(find.text('Use existing EAR1'));
      await tester.tap(find.text('Use existing EAR1'));
      await tester.pumpAndSettle();
      expect(result?['existing_id'], 'old');
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    },
  );
}
