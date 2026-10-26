import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:ringmaster_breeder/theme/app_theme.dart';
import 'package:ringmaster_breeder/widgets/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/screens/rabbit_register_import_screen.dart';
import 'package:ringmaster_breeder/services/rabbit_register_import_service.dart';

class FakeRabbitRegister implements RabbitRegisterImportGateway {
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
    '<ExportedData><Animals><Record><CID>1</CID><Name>Sample</Name><Sex>?</Sex><Breed>Dutch</Breed><Weight>1814.368</Weight><Storage_Area>Active_I:Active</Storage_Area></Record></Animals>',
  ),
);
Future<void> open(
  WidgetTester t,
  FakeRabbitRegister gateway, {
  Uint8List? fileBytes,
  Future<({String name, Uint8List bytes})?> Function()? pickFile,
}) async {
  t.view.physicalSize = const Size(1200, 1800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => AppShell(child: child!),
      home: RabbitRegisterImportScreen(
        gateway: gateway,
        pickFile:
            pickFile ??
            () async => (name: 'Other.XML', bytes: fileBytes ?? bytes),
      ),
    ),
  );
  await t.pumpAndSettle();
  expect(find.byType(DropdownButtonFormField<bool>), findsNothing);
  expect(
    find.text(
      'Rabbit Register stores XML weights in grams. Breeder converts them to pounds automatically.',
    ),
    findsOneWidget,
  );
  await t.tap(find.text('Choose Rabbit Register XML'));
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
  for (final unreadable in [false, true]) {
    testWidgets(
      'a rejected replacement file cannot import the previous export (read failure: $unreadable)',
      (t) async {
        var picks = 0;
        final gateway = FakeRabbitRegister();
        await open(
          t,
          gateway,
          pickFile: () async {
            picks++;
            if (picks > 1 && unreadable) {
              throw const FormatException(
                'Unable to read this file. Choose it again.',
              );
            }
            return (
              name: picks == 1 ? 'Other.XML' : 'Rejected.XML',
              bytes: picks == 1
                  ? bytes
                  : Uint8List.fromList(utf8.encode('<Other/>')),
            );
          },
        );
        await ready(t);
        expect(gateway.previews, 1);
        await reveal(t, find.text('Choose Rabbit Register XML'));
        await t.tap(find.text('Choose Rabbit Register XML'));
        await t.pumpAndSettle();
        expect(
          find.text(
            unreadable
                ? 'Unable to read this file. Choose it again.'
                : 'Select a Rabbit Register ExportedData XML file.',
          ),
          findsOneWidget,
        );
        expect(find.text('Other.XML'), findsNothing);
        expect(find.text('Preview import'), findsNothing);
        expect(find.text('Import into herd'), findsNothing);
        expect(gateway.saves, 0);
      },
    );
  }
  testWidgets(
    'renamed archive storage reaches preview and imports as archived',
    (t) async {
      final gateway = FakeRabbitRegister();
      await open(
        t,
        gateway,
        fileBytes: Uint8List.fromList(
          utf8.encode(
            utf8
                .decode(bytes)
                .replaceAll('Active_I:Active', 'Arch._II:Arch._II'),
          ),
        ),
      );
      await ready(t);
      expect(gateway.previews, 1);
      expect(gateway.saves, 0);
      final animal = (gateway.data!['animals'] as List).single;
      expect(animal['status'], 'archived');
      expect(animal['raw']['Storage_Area'], 'Arch._II:Arch._II');
      await reveal(t, find.text('Import into herd'));
      await t.tap(find.text('Import into herd'));
      await t.pumpAndSettle();
      expect(gateway.saves, 1);
      expect(find.text('Import complete'), findsOneWidget);
    },
  );
  testWidgets(
    'file selection never saves; sex and warnings require review before save',
    (t) async {
      final gateway = FakeRabbitRegister();
      await open(t, gateway);
      expect(gateway.saves, 0);
      await ready(t);
      expect((gateway.data!['animals'] as List).single['sex'], 'Doe');
      expect((gateway.data!['animals'] as List).single['profile_weight'], 4);
      await reveal(t, find.text('Import into herd'));
      await t.tap(find.text('Import into herd'));
      await t.pumpAndSettle();
      expect(gateway.saves, 1);
      expect(gateway.source, 'my register');
      expect(find.text('Import complete'), findsOneWidget);
    },
  );
  testWidgets('source edits invalidate an approved preview', (t) async {
    final gateway = FakeRabbitRegister();
    await open(t, gateway);
    await ready(t);
    await t.ensureVisible(find.byType(TextField));
    await t.enterText(find.byType(TextField), 'another breeder');
    await t.pumpAndSettle();
    expect(find.text('Import into herd'), findsNothing);
    expect(gateway.saves, 0);
  });
  testWidgets('server issues block save', (t) async {
    final gateway = FakeRabbitRegister()..conflict = true;
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
    final gateway = FakeRabbitRegister();
    await open(t, gateway);
    gateway.fail = true;
    await ready(t);
    expect(find.textContaining('Unable to complete this step'), findsOneWidget);
    expect(find.text('Other.XML'), findsOneWidget);
    expect(gateway.saves, 0);
    gateway.fail = false;
    await reveal(t, find.text('Preview import'));
    await t.tap(find.text('Preview import'));
    await t.pumpAndSettle();
    expect((gateway.data!['animals'] as List).single['sex'], 'Doe');
    expect((gateway.data!['animals'] as List).single['profile_weight'], 4);
  });
  testWidgets('import review fits a narrow phone without layout overflow', (
    t,
  ) async {
    final gateway = FakeRabbitRegister();
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
    final gateway = FakeRabbitRegister()..matching = true;
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
