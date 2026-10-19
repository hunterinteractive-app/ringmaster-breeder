import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:ringmaster_breeder/theme/app_theme.dart';
import 'package:ringmaster_breeder/widgets/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/screens/kintraks_import_screen.dart';
import 'package:ringmaster_breeder/services/kintraks_import_service.dart';

class FakeKintraks implements KintraksImportGateway {
  int saves = 0, previews = 0;
  bool fail = false, conflict = false, matching = false;
  String? source, herd;
  Map<String, dynamic>? data;
  @override
  Future<List<Map<String, dynamic>>> ownedHerds() async => [
    {'id': 'one', 'name': 'My herd'},
    {'id': 'two', 'name': 'Second herd'},
  ];
  @override
  Future<List<String>> sources(String herd) async => ['my register'];
  @override
  Future<Map<String, dynamic>> run(
    String herd,
    String source,
    Map<String, dynamic> data, {
    bool commit = false,
  }) async {
    this.herd = herd;
    this.source = source;
    this.data = data;
    if (fail) throw Exception('Network lost');
    if (commit) {
      saves++;
      return {
        'status': 'imported',
        'animals_added': 1,
        'animals_existing': 0,
        'history_added': 0,
      };
    }
    previews++;
    final sex = (data['animals'] as List).single['sex'];
    return {
      'status': 'preview',
      'animals_added': 1,
      'animals_existing': 0,
      'history_count': 0,
      'issues': [
        if (sex == null) 'Choose sex',
        if (data['warnings_acknowledged'] != true) 'Review warnings',
        if (conflict) 'Server conflict',
        if (matching &&
            (data['animals'] as List).single['existing_id'] == null &&
            (data['animals'] as List).single['keep_separate'] != true)
          'Review existing matches',
      ],
      'rows': [
        {
          'source_id': '1',
          'name': 'Sample',
          'action': 'New rabbit',
          'candidates': [
            if (matching)
              {
                'id': 'existing-id',
                'name': 'Sample',
                'tattoo': 'T1',
                'status': 'active',
              },
          ],
        },
      ],
    };
  }
}

final bytes = Uint8List.fromList(
  utf8.encode(
    'Id,Fatherid,Motherid,Name,Sex,Dob,Ear #,Weight,Deceased,Sold,Breed\n1,,,Sample,?,,T1,3.13,False,False,Dutch',
  ),
);
Future<void> open(WidgetTester t, FakeKintraks gateway) async {
  t.view.physicalSize = const Size(1200, 1800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => AppShell(child: child!),
      home: KintraksImportScreen(
        gateway: gateway,
        pickFile: () async => (name: 'Export.csv', bytes: bytes),
      ),
    ),
  );
  await t.pumpAndSettle();
  expect(find.byType(DropdownButtonFormField<bool>), findsNothing);
  expect(
    find.text(
      'Kintraks CSV weights use pounds and ounces: 3.13 means 3 lb 13 oz. Breeder converts these to pounds automatically and preserves the original text.',
    ),
    findsOneWidget,
  );
  await t.tap(find.text('Choose Kintraks CSV'));
  await t.pumpAndSettle();
  await t.enterText(find.byType(TextField), 'my register');
  await t.pumpAndSettle();
}

Future<void> reveal(WidgetTester t, Finder finder) async {
  await t.scrollUntilVisible(
    finder,
    180,
    scrollable: find.byType(Scrollable).first,
  );
  await t.pumpAndSettle();
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
}

Future<void> ready(WidgetTester t) async {
  await reveal(t, find.byType(CheckboxListTile));
  await t.tap(find.byType(CheckboxListTile));
  await t.pumpAndSettle();
  await t.ensureVisible(find.byKey(const ValueKey('sex-1-1')));
  await t.pumpAndSettle();
  await t.tap(find.byKey(const ValueKey('sex-1-1')));
  await t.pumpAndSettle();
  await t.tap(find.text('Doe').last);
  await t.pumpAndSettle();
  await reveal(t, find.text('Preview import'));
  await t.tap(find.text('Preview import'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'file selection never saves; sex and warnings require review before save',
    (t) async {
      final gateway = FakeKintraks();
      await open(t, gateway);
      expect(gateway.saves, 0);
      await ready(t);
      expect((gateway.data!['animals'] as List).single['sex'], 'Doe');
      expect(
        (gateway.data!['animals'] as List).single['profile_weight'],
        3.8125,
      );
      await reveal(t, find.text('Import into herd'));
      await t.tap(find.text('Import into herd'));
      await t.pumpAndSettle();
      expect(gateway.saves, 1);
      expect(gateway.source, 'my register');
      expect((gateway.data!['animals'] as List).single['status'], 'archived');
      expect((gateway.data!['animals'] as List).single['pedigree_only'], true);
      expect(find.text('Import complete'), findsOneWidget);
    },
  );
  testWidgets('current herd selection is explicit and invalidates preview', (
    t,
  ) async {
    final gateway = FakeKintraks();
    await open(t, gateway);
    await ready(t);
    await reveal(t, find.text('Choose current herd (0 selected)'));
    await t.tap(find.text('Choose current herd (0 selected)'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('active-1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('active-1')));
    await t.pumpAndSettle();
    expect(find.text('Import into herd'), findsNothing);
    await t.tap(find.text('Choose current herd (1 selected)'));
    await t.pumpAndSettle();
    await reveal(t, find.text('Preview import'));
    await t.tap(find.text('Preview import'));
    await t.pumpAndSettle();
    expect((gateway.data!['animals'] as List).single['status'], 'active');
    expect((gateway.data!['animals'] as List).single['pedigree_only'], false);
    expect(gateway.saves, 0);
  });
  testWidgets('correction editor preserves originals and invalidates preview', (
    t,
  ) async {
    final gateway = FakeKintraks();
    await open(t, gateway);
    await ready(t);
    await reveal(t, find.text('Review and edit rabbits (0 corrected)'));
    await t.tap(find.text('Review and edit rabbits (0 corrected)'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('edit-1')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('edit-1')));
    await t.pumpAndSettle();
    final birth = find.byKey(const ValueKey('field-Dob'));
    await t.ensureVisible(birth);
    await t.pumpAndSettle();
    await t.enterText(birth, '2020-02-30');
    await t.tap(find.byKey(const ValueKey('apply-corrections')));
    await t.pumpAndSettle();
    expect(find.textContaining('birth date is invalid'), findsOneWidget);
    await t.enterText(birth, '2020-01-02');
    await t.tap(find.byKey(const ValueKey('apply-corrections')));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Import into herd'), findsNothing);
    await t.tap(find.text('Review and edit rabbits (1 corrected)'));
    await t.pumpAndSettle();
    // Editing also resets acknowledgment and unknown-sex decisions for this animal.
    await ready(t);
    final a = (gateway.data!['animals'] as List).single;
    expect(a['dob'], '2020-01-02');
    expect(a['raw']['Dob'], '');
    expect(a['corrections']['Dob'], '2020-01-02');
    expect(gateway.saves, 0);
  });
  testWidgets('source edits invalidate an approved preview', (t) async {
    final gateway = FakeKintraks();
    await open(t, gateway);
    await ready(t);
    await t.ensureVisible(find.byType(TextField));
    await t.enterText(find.byType(TextField), 'another breeder');
    await t.pumpAndSettle();
    expect(find.text('Import into herd'), findsNothing);
    expect(gateway.saves, 0);
  });
  testWidgets('server issues block save', (t) async {
    final gateway = FakeKintraks()..conflict = true;
    await open(t, gateway);
    await ready(t);
    final button = t.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Import into herd'),
    );
    expect(button.onPressed, isNull);
    expect(gateway.saves, 0);
  });
  testWidgets('failed review retains file and corrections for retry', (
    t,
  ) async {
    final gateway = FakeKintraks();
    await open(t, gateway);
    gateway.fail = true;
    await ready(t);
    expect(find.textContaining('Unable to complete this step'), findsOneWidget);
    expect(find.text('Export.csv'), findsOneWidget);
    expect(gateway.saves, 0);
    gateway.fail = false;
    await reveal(t, find.text('Preview import'));
    await t.tap(find.text('Preview import'));
    await t.pumpAndSettle();
    expect((gateway.data!['animals'] as List).single['sex'], 'Doe');
    expect((gateway.data!['animals'] as List).single['profile_weight'], 3.8125);
  });
  testWidgets('import review fits a narrow phone without layout overflow', (
    t,
  ) async {
    final gateway = FakeKintraks();
    await open(t, gateway);
    t.view.physicalSize = const Size(390, 844);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    final sexField = find.byKey(const ValueKey('sex-1-1'));
    await t.scrollUntilVisible(
      sexField,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    await t.ensureVisible(sexField);
    await t.pumpAndSettle();
    await t.tap(sexField);
    await t.pumpAndSettle();
    await t.tap(find.text('Doe').last);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.ensureVisible(find.byType(CheckboxListTile));
    await t.pumpAndSettle();
    await reveal(t, find.byType(CheckboxListTile));
    await t.tap(find.byType(CheckboxListTile));
    await t.pumpAndSettle();
    await reveal(t, find.text('Preview import'));
    await t.pumpAndSettle();
    await t.tap(find.text('Preview import'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('existing match choice needs another preview before saving', (
    t,
  ) async {
    final gateway = FakeKintraks()..matching = true;
    await open(t, gateway);
    await ready(t);
    await reveal(t, find.byKey(const ValueKey('match-1-null')));
    await t.tap(find.byKey(const ValueKey('match-1-null')));
    await t.pumpAndSettle();
    await t.tap(find.text('Keep as a separate new rabbit').last);
    await t.pumpAndSettle();
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Import into herd'),
          )
          .onPressed,
      isNull,
    );
    await reveal(t, find.text('Preview import'));
    await t.tap(find.text('Preview import'));
    await t.pumpAndSettle();
    expect((gateway.data!['animals'] as List).single['keep_separate'], true);
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Import into herd'),
          )
          .onPressed,
      isNotNull,
    );
  });
}
