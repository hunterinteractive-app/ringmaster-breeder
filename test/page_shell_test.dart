import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/theme/app_theme.dart';
import 'package:ringmaster_breeder/widgets/ringmaster_page_shell.dart';

void main() {
  for (final width in [320.0, 700.0, 1280.0]) {
    testWidgets('Long page titles and dashboard actions fit at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: RingMasterPageShell(
            title: 'Imported profiles and show history',
            actions: List.generate(
              5,
              (i) => IconButton(
                tooltip: 'Action $i',
                onPressed: () {},
                icon: const Icon(Icons.settings),
              ),
            ),
            body: const ListViewContent(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('RingMaster Breeder'), findsOneWidget);
      for (var i = 0; i < 5; i++) {
        expect(find.byTooltip('Action $i'), findsOneWidget);
      }
    });
  }
  testWidgets('Back and Home return to the dashboard', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => RingMasterPageShell(
            title: 'My Rings',
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const RingMasterPageShell(
                    title: 'Animal Details',
                    body: Text('Animal'),
                  ),
                ),
              ),
              child: const Text('Open animal'),
            ),
          ),
        ),
      ),
    );
    for (final navigation in ['Back', 'Home']) {
      await tester.tap(find.text('Open animal'));
      await tester.pumpAndSettle();
      if (navigation == 'Back') {
        await tester.tap(find.byIcon(Icons.arrow_back));
      } else {
        await tester.tap(find.byTooltip('Home').last);
      }
      await tester.pumpAndSettle();
      expect(find.text('My Rings'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}

class ListViewContent extends StatelessWidget {
  const ListViewContent({super.key});
  @override
  Widget build(BuildContext context) =>
      ListView(children: const [Text('Records')]);
}
