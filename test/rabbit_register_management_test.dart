import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/theme/app_theme.dart';
import 'package:ringmaster_breeder/widgets/app_shell.dart';
import 'package:ringmaster_breeder/widgets/animal_management_section.dart';
import 'package:ringmaster_breeder/widgets/breeding_dashboard.dart';
import 'package:ringmaster_breeder/screens/production_measurements_screen.dart';
import 'package:ringmaster_breeder/screens/show_reports_screen.dart';

Widget host(Widget child) => MaterialApp(
  theme: AppTheme.light,
  home: AppShell(child: child),
);
void main() {
  for (final width in [390.0, 1200.0]) {
    testWidgets('Imported litter keeps unknown sire/date usable at $width', (
      t,
    ) async {
      t.view.physicalSize = Size(width, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        host(
          Scaffold(
            body: BreedingDashboard(
              records: [
                {
                  'id': 'litter',
                  'import_source': 'old database',
                  'import_record': {'DIED': '2'},
                  'status': 'completed',
                  'breeding_date': null,
                  'dam': {'name': 'Doe', 'species': 'rabbit'},
                  'sire': null,
                  'offspring': [],
                  'tracking': {'status': 'completed', 'weaned': 3},
                },
              ],
              settings: const {},
              filter: 'All',
              onFilter: (_) {},
              onEdit: (_) {},
              onOffspring: (_) {},
              onOpen: (_) {},
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Unknown sire'), findsOneWidget);
      expect(find.text('Not recorded'), findsOneWidget);
      expect(find.text('Litter weights & feed'), findsOneWidget);
      expect(find.text('Create offspring records'), findsNothing);
      expect(t.takeException(), isNull);
    });
    testWidgets('Wool harvest is separate from body weights at $width', (
      t,
    ) async {
      t.view.physicalSize = Size(width, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        host(
          ProductionMeasurementsScreen(
            recordId: 'animal',
            wool: true,
            loader: () async => [
              {
                'id': 'one',
                'recorded_date': null,
                'fleece_grams': null,
                'measurements': {'PRIME': '20', 'AFD': '12'},
                'notes': 'Imported harvest',
                'import_source': 'source',
              },
            ],
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.textContaining('Total fleece weight unknown'),
        findsOneWidget,
      );
      await t.ensureVisible(find.byType(ExpansionTile));
      await t.pumpAndSettle();
      await t.tap(find.byType(ExpansionTile));
      await t.pumpAndSettle();
      expect(find.text('Prime wool: 20 g'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'Management custom fields preserve labels and buyer/seller links',
    (t) async {
      t.view.physicalSize = const Size(1000, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        host(
          Scaffold(
            body: ListView(
              children: [
                AnimalManagementSection(
                  animalId: 'animal',
                  loader: () async => {
                    'data': {
                      'cage': 'A12',
                      'custom_fields': {'Mane type': 'Double'},
                      'death_date': '2014-01-01',
                      'seller_contact_id': 'person',
                    },
                    'contacts': [
                      {
                        'id': 'person',
                        'name': 'Breeder',
                        'rabbitry': 'Angora farm',
                      },
                    ],
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byType(ExpansionTile));
      await t.pumpAndSettle();
      expect(find.text('Cage / housing: A12'), findsOneWidget);
      expect(find.text('Mane type: Double'), findsOneWidget);
      expect(find.text('Seller: Breeder · Angora farm'), findsOneWidget);
      expect(find.text('Death date: 2014-01-01'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('Wool save retry reuses the same source operation', (t) async {
    t.view.physicalSize = const Size(1000, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final calls = <Map<String, dynamic>>[];
    await t.pumpWidget(
      host(
        ProductionMeasurementsScreen(
          recordId: 'animal',
          wool: true,
          loader: () async => [],
          writer: (row) async {
            calls.add(Map.of(row));
            if (calls.length == 1) throw Exception('Lost response');
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byType(FloatingActionButton));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).at(1), '50');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(calls.length, 2);
    expect(calls[0], calls[1]);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'Imported show exposes judge and leg without counting a payment',
    (t) async {
      t.view.physicalSize = const Size(390, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        host(
          Scaffold(
            body: ListView(
              children: [
                ShowResultCard(
                  row: {
                    'animal_id': 'animal',
                    'record': {
                      'animal_name': 'Rabbit',
                      'shows': {'name': 'Show', 'start_date': '2014-01-01'},
                      'judge': 'Judge A',
                      'is_leg': true,
                      'placement': '1',
                      'special_awards': 'BOB',
                      'source': 'Rabbit Register',
                    },
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Judge: Judge A'), findsOneWidget);
      expect(find.text('ARBA leg recorded'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
