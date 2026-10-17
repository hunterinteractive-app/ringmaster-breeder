import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/screens/animal_list_screen.dart';
import 'package:ringmaster_breeder/theme/app_theme.dart';
import 'package:ringmaster_breeder/widgets/app_shell.dart';
import 'package:ringmaster_breeder/widgets/ringmaster_page_shell.dart';

final animals = List.generate(
  4,
  (i) => <String, dynamic>{
    'id': '$i',
    'name': 'Animal $i',
    'tattoo': 'TAG$i',
    'species': 'rabbit',
    'breed': 'Dutch',
    'variety': 'Chocolate',
    'sex': 'Doe',
    'status': i == 3 ? 'sold' : 'active',
    'sale_status': i == 0 ? 'for_sale' : null,
    'dob': '2025-02-19',
  },
);

Widget page({ValueChanged<Map<String, dynamic>>? onOpen, double scale = 1}) =>
    MaterialApp(
      theme: AppTheme.light.copyWith(
        textTheme: AppTheme.light.textTheme.apply(fontFamily: 'BreederSans'),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: AppShell(child: child!),
      ),
      home: RingMasterPageShell(
        title: 'Test herd',
        body: AnimalBrowser(
          animals: animals,
          onAdd: () {},
          onRefresh: () {},
          onOpen: onOpen ?? (_) {},
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Measure density with the same bundled font used by the offline PWA.
    final font = FontLoader('BreederSans')
      ..addFont(rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    await font.load();
  });
  for (final (size, scale) in [
    (const Size(360, 520), 1.0),
    (const Size(320, 568), 1.5),
    (const Size(640, 360), 1.0),
  ]) {
    testWidgets('Phone shows animals immediately at $size / text $scale', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? opened;
      await tester.pumpWidget(
        page(scale: scale, onOpen: (animal) => opened = animal['id'] as String),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.byTooltip('Filters'), findsOneWidget);
      expect(find.text('3 of 4 animals'), findsOneWidget);
      final cards = find.byType(AnimalRecordCard);
      final first = tester.getRect(cards.first);
      final viewport = tester.getRect(find.byType(CustomScrollView));
      expect(first.top, lessThan(220 * scale));
      expect(first.bottom, lessThanOrEqualTo(viewport.bottom));
      expect(first.height, lessThan(scale == 1 ? 180 : 240));
      if (size.width == 360) {
        expect(
          tester.getRect(cards.at(1)).bottom,
          lessThanOrEqualTo(viewport.bottom),
        );
      }
      expect(find.text('For Sale'), findsOneWidget);
      expect(find.text('DOB: 02/19/2025'), findsWidgets);
      await tester.tap(find.text('Animal 0 • TAG0'));
      expect(opened, '0');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Collapsed filters retain selections and query across screen sizes',
    (tester) async {
      tester.view.physicalSize = const Size(360, 620);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
      final status = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Status',
      );
      await tester.tap(status);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sold').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Hide filters'));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('1 of 4 animals'), findsOneWidget);
      final badge = tester.widget<Badge>(
        find.descendant(
          of: find.byTooltip('Filters'),
          matching: find.byType(Badge),
        ),
      );
      expect(badge.isLabelVisible, isTrue);
      expect(find.text('Animal 3 • TAG3'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'TAG3');
      final controller = tester
          .widget<TextField>(find.byType(TextField))
          .controller!;

      // Widening restores the full toolbar and card without discarding the draft query.
      tester.view.physicalSize = const Size(1280, 900);
      await tester.pumpAndSettle();
      expect(controller.text, 'TAG3');
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .focusNode
            .hasFocus,
        isTrue,
      );
      expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(3));
      expect(
        tester.widget<AnimalRecordCard>(find.byType(AnimalRecordCard)).compact,
        isFalse,
      );
      expect(find.text('View details'), findsOneWidget);
      expect(find.text('1 of 4 animals'), findsOneWidget);

      tester.view.physicalSize = const Size(360, 620);
      await tester.pumpAndSettle();
      expect(controller.text, 'TAG3');
      expect(find.byTooltip('Filters'), findsOneWidget);
      expect(find.text('1 of 4 animals'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reset filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Hide filters'));
      await tester.pumpAndSettle();
      expect(find.text('3 of 4 animals'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
