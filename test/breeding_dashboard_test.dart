import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/widgets/breeding_dashboard.dart';
import 'package:ringmaster_breeder/theme/app_theme.dart';

void main() {
  final records = <Map<String, dynamic>>[
    {
      'id': 'a',
      'status': 'active',
      'breeding_date': '2026-10-01',
      'dam': {
        'name': 'A long rabbit name for testing',
        'tattoo': 'TEST-01',
        'species': 'rabbit',
        'breed': 'Dutch',
      },
      'sire': {'name': 'Test sire', 'tattoo': 'TEST-02'},
      'tracking': null,
      'offspring': [],
      'notes': 'Sample notes are hidden until expanded.',
    },
    {
      'id': 'b',
      'status': 'active',
      'breeding_date': '2026-08-01',
      'dam': {
        'name': 'Cavy litter',
        'tattoo': 'C1',
        'species': 'cavy',
        'breed': 'Abyssinian',
      },
      'sire': {'name': 'Cavy sire', 'tattoo': 'C2'},
      'tracking': {'birth_date': '2026-10-01', 'born_alive': 3, 'born_dead': 0},
      'offspring': [],
    },
  ];
  for (final width in [320.0, 800.0, 1400.0]) {
    testWidgets('Dashboard fits $width and keeps tracking actions', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? edited;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: BreedingDashboard(
              records: records,
              settings: const {},
              filter: 'Active',
              onFilter: (_) {},
              onEdit: (r) => edited = r['id'],
              onOffspring: (_) {},
              onOpen: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Your breeding overview'), findsOneWidget);
      expect(find.text('Nursing litters'), findsOneWidget);
      final button = find.text('Update tracking').first;
      await tester.ensureVisible(button);
      await tester.tap(button);
      expect(edited, 'b');
      expect(tester.takeException(), isNull);
    });
  }
}
