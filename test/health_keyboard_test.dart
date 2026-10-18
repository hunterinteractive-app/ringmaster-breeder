import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/screens/health_records_screen.dart';
import 'package:ringmaster_breeder/theme/app_theme.dart';
import 'package:ringmaster_breeder/widgets/app_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('BreederSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    await font.load();
  });

  for (final keyboard in [249.0, 313.0]) {
    testWidgets('Health notes and Save stay above a $keyboard pixel keyboard', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 512);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light.copyWith(
            textTheme: AppTheme.light.textTheme.apply(
              fontFamily: 'BreederSans',
            ),
          ),
          builder: (_, child) => AppShell(child: child!),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) =>
                      const HealthRecordModal(animalId: 'test-animal'),
                ),
                child: const Text('Open health form'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open health form'));
      await tester.pumpAndSettle();
      final title = find.widgetWithText(TextField, 'Title');
      await tester.tap(title);
      await tester.enterText(title, 'Unsaved health draft');
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      await tester.pumpAndSettle();
      final scrollable = find
          .descendant(
            of: find.byType(HealthRecordModal),
            matching: find.byType(Scrollable),
          )
          .first;
      final notes = find.widgetWithText(TextField, 'Notes');
      await tester.scrollUntilVisible(
        notes.hitTestable(),
        60,
        scrollable: scrollable,
      );
      await Scrollable.ensureVisible(tester.element(notes), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(notes);
      await tester.enterText(notes, 'Unsaved health notes');
      final save = find.text('Save Record');
      await tester.scrollUntilVisible(
        save.hitTestable(),
        60,
        scrollable: scrollable,
      );
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      expect(tester.getRect(save).bottom, lessThanOrEqualTo(512 - keyboard));
      final titleController = tester.widget<TextField>(title).controller!;
      final notesController = tester.widget<TextField>(notes).controller!;
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(titleController.text, 'Unsaved health draft');
      expect(notesController.text, 'Unsaved health notes');
      expect(tester.takeException(), isNull);
    });
  }
}
