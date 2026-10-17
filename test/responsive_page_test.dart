import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/offline/offline_runtime.dart';
import 'package:ringmaster_breeder/screens/edit_animal_screen.dart';
import 'package:ringmaster_breeder/theme/app_theme.dart';
import 'package:ringmaster_breeder/widgets/app_shell.dart';
import 'package:ringmaster_breeder/widgets/ringmaster_page_shell.dart';
import 'package:ringmaster_breeder/widgets/sync_dialog.dart';

Finder field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

void main() {
  for (final (size, keyboard, scale) in [
    (const Size(360, 520), 260.0, 1.0),
    (const Size(320, 568), 280.0, 1.5),
    (const Size(844, 390), 180.0, 1.0),
  ]) {
    testWidgets('Edit form stays usable above the keyboard at $size / $scale', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: AppShell(child: child!),
          ),
          home: EditAnimalScreen(
            animalId: 'test-animal',
            loader: (_) async => {
              'name': 'Willow',
              'tattoo': 'W1',
              'species': 'rabbit',
              'breed': 'Dutch',
              'variety': 'Black',
              'sex': 'Doe',
              'status': 'active',
              'revision': 1,
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(field('Name'));
      await tester.enterText(field('Name'), 'Unsaved barn edit');
      final nameController = tester
          .widget<TextField>(field('Name'))
          .controller!;
      tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final viewport = find.byType(ListView).first;
      expect(tester.getSize(viewport).height, greaterThan(120));
      expect(find.textContaining('Version '), findsNothing);
      final nameEditable = find.descendant(
        of: field('Name'),
        matching: find.byType(EditableText),
      );
      expect(
        tester.widget<EditableText>(nameEditable).focusNode.hasFocus,
        isTrue,
      );
      expect(
        tester.widget<TextField>(field('Name')).controller!.text,
        'Unsaved barn edit',
      );
      final nameRect = tester.getRect(field('Name'));
      expect(nameRect.top, greaterThanOrEqualTo(0));
      expect(nameRect.bottom, lessThanOrEqualTo(size.height - keyboard));

      // Reach a field near the end of the actual form with the keyboard up.
      await tester.scrollUntilVisible(
        field('Registration Number').hitTestable(),
        120,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 40,
      );
      await Scrollable.ensureVisible(
        tester.element(field('Registration Number')),
        alignment: 0.5,
      );
      await tester.pumpAndSettle();
      await tester.tap(field('Registration Number'));
      await tester.enterText(field('Registration Number'), 'BARN-42');
      final registrationController = tester
          .widget<TextField>(field('Registration Number'))
          .controller!;
      await tester.pumpAndSettle();
      final registrationRect = tester.getRect(field('Registration Number'));
      expect(
        registrationRect.bottom,
        lessThanOrEqualTo(size.height - keyboard),
      );
      await tester.scrollUntilVisible(
        find.text('Save Changes').hitTestable(),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Save Changes').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Hide keyboard'));
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isFalse);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Version '),
        size.height >= 400 ? findsOneWidget : findsNothing,
      );
      expect(nameController.text, 'Unsaved barn edit');
      expect(registrationController.text, 'BARN-42');
    });
  }

  testWidgets('Browser viewport shrink preserves focus, edits and navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var refreshes = 0;
    var returns = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        routes: {
          '/account': (_) => const RingMasterPageShell(
            title: 'Account settings',
            isAccountPage: true,
            body: Text('Settings'),
          ),
        },
        builder: (_, child) => AppShell(child: child!),
        home: RingMasterPageShell(
          title: 'Edit Animal',
          onRefresh: () => refreshes++,
          onAccountReturn: () => returns++,
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [TextField(controller: controller)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('RingMaster Breeder'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Keep my draft');
    tester.view.physicalSize = const Size(390, 260);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(ListView)).height, greaterThan(160));
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isTrue,
    );
    expect(controller.text, 'Keep my draft');
    await tester.tap(find.byTooltip('Page menu'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Refresh'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(refreshes, 1);
    await tester.tap(find.byTooltip('Page menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(returns, 1);
    expect(controller.text, 'Keep my draft');
    tester.view.physicalSize = const Size(1280, 900);
    await tester.pumpAndSettle();
    expect(find.text('RingMaster Breeder'), findsOneWidget);
    expect(
      tester.getSize(find.byType(ListView)).width,
      lessThanOrEqualTo(1200),
    );
    expect(controller.text, 'Keep my draft');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Compact Sync keeps its count, attention state and status dialog',
    (tester) async {
      addTearDown(() => OfflineRuntime.workspaceStatus.value = {});
      OfflineRuntime.workspaceStatus.value = {
        'jobs': [
          {'state': 'needs_input'},
          {'state': 'queued'},
          {'state': 'complete'},
        ],
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: SyncHeaderButton(compact: true)),
        ),
      );
      expect(find.byTooltip('Sync (2)'), findsOneWidget);
      expect(find.byIcon(Icons.sync_problem), findsOneWidget);
      await tester.tap(find.byTooltip('Sync (2)'));
      await tester.pumpAndSettle();
      expect(find.text('Sync status'), findsOneWidget);
    },
  );
}
