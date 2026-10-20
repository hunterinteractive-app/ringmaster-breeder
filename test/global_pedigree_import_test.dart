import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/screens/global_pedigree_import_screen.dart';
import 'package:ringmaster_breeder/services/global_pedigree_import_service.dart';

class FakeGlobalPedigree implements GlobalPedigreeImportGateway {
  bool conflict = false, fail = false, unknown = false, duplicates = false;
  Map<String, dynamic>? draft;
  String? aliasChoice;
  String? reviewedSex;
  int commits = 0;
  final reviewedHerds = <String>[];
  @override
  Future<Map<String, dynamic>?> pendingDraft() async => draft;
  @override
  Future<void> discardDraft() async {}
  @override
  Future<List<Map<String, dynamic>>> ownedHerds() async => [
    {'id': 'one', 'name': 'First herd'},
    {'id': 'two', 'name': 'Second herd'},
  ];
  @override
  Future<Map<String, dynamic>> collect(String username, String password) async {
    if (fail) throw const FormatException('Sign-in failed.');
    return {
      'account': 'fixture',
      'animals': [
        {
          'source_id': '10',
          'name': 'Fixture Rabbit',
          'sex': unknown ? null : 'Buck',
          'tattoo': 'SAME',
          'breed': 'Mini Rex',
        },
        if (duplicates)
          {
            'source_id': '11',
            'name': 'Fixture Rabbit',
            'sex': 'Buck',
            'tattoo': 'SAME',
            'breed': 'Mini Rex',
          },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> review(
    String herd,
    Map<String, dynamic> data,
  ) async {
    reviewedHerds.add(herd);
    reviewedSex = (data['animals'] as List).first['sex'] as String?;
    if (duplicates) {
      aliasChoice = (data['animals'] as List)[1]['same_as'] as String?;
    }
    return {
      'duplicate_groups': duplicates ? [data['animals']] : [],
      'status': 'preview',
      'animals_added': 1,
      'animals_existing': 0,
      'issues':
          duplicates &&
              (data['animals'] as List).any(
                (a) => a['keep_separate'] != true && a['same_as'] == null,
              )
          ? ['Review possible duplicate.']
          : conflict
          ? ['Missing sire record.']
          : reviewedSex == null
          ? ['Unknown sex.']
          : <String>[],
      'rows': [
        {
          'source_id': '10',
          'name': 'Fixture Rabbit',
          'sex': 'Buck',
          'action': 'New record',
          'known_genotype': 'aa bb C_ dd E_',
          'genotype_action': 'Genotype saved as imported reference',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> save(
    String herd,
    Map<String, dynamic> data,
  ) async {
    commits++;
    return {'status': 'imported', 'animals_added': 1, 'animals_existing': 0};
  }
}

Future<void> connect(WidgetTester tester, FakeGlobalPedigree gateway) async {
  await tester.pumpWidget(
    MaterialApp(home: GlobalPedigreeImportScreen(gateway: gateway)),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField).at(0), 'fixture');
  await tester.enterText(
    find.byType(TextFormField).at(1),
    'temporary-password',
  );
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.text('Connect and preview'),
    200,
    scrollable: find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Connect and preview'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('collection only previews; user must explicitly commit', (
    tester,
  ) async {
    final gateway = FakeGlobalPedigree();
    await connect(tester, gateway);
    expect(gateway.commits, 0);
    expect(find.text('Fixture Rabbit'), findsOneWidget);
    expect(
      find.textContaining('Source genotype: aa bb C_ dd E_'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Import into herd'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import into herd'));
    await tester.pumpAndSettle();
    expect(gateway.commits, 1);
    expect(find.text('Import complete'), findsOneWidget);
  });
  testWidgets('conflicts prevent import', (tester) async {
    final gateway = FakeGlobalPedigree()..conflict = true;
    await connect(tester, gateway);
    expect(find.text('Missing sire record.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Import into herd'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Import into herd'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
    expect(gateway.commits, 0);
  });
  testWidgets('failed connection clears password and displays useful error', (
    tester,
  ) async {
    final gateway = FakeGlobalPedigree()..fail = true;
    await connect(tester, gateway);
    expect(find.text('Sign-in failed.'), findsOneWidget);
    final field = tester.widget<TextFormField>(
      find.byType(TextFormField).at(1),
    );
    expect(field.controller!.text, isEmpty);
    expect(gateway.commits, 0);
  });
  testWidgets('changing destination invalidates preview', (tester) async {
    final gateway = FakeGlobalPedigree();
    await connect(tester, gateway);
    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('First herd'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second herd').last);
    await tester.pumpAndSettle();
    expect(find.text('Import into herd'), findsNothing);
    await tester.tap(find.text('Review import'));
    await tester.pumpAndSettle();
    expect(gateway.reviewedHerds, ['one', 'two']);
  });
  testWidgets('unknown sex correction requires a fresh preview', (
    tester,
  ) async {
    final gateway = FakeGlobalPedigree()..unknown = true;
    await connect(tester, gateway);
    final sex = find.byKey(const ValueKey('sex-10'));
    await tester.ensureVisible(sex);
    await tester.pumpAndSettle();
    await tester.tap(sex);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Doe').last);
    await tester.pumpAndSettle();
    expect(find.text('Import into herd'), findsNothing);
    await tester.ensureVisible(find.text('Review import'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review import'));
    await tester.pumpAndSettle();
    expect(gateway.reviewedSex, 'Doe');
    expect(gateway.reviewedHerds.length, 2);
    expect(gateway.commits, 0);
  });
  testWidgets(
    'explicit duplicate choice invalidates preview and keeps source IDs',
    (tester) async {
      final gateway = FakeGlobalPedigree()..duplicates = true;
      await connect(tester, gateway);
      final decision = find.byKey(const ValueKey('duplicates-10'));
      await tester.ensureVisible(decision);
      await tester.pumpAndSettle();
      await tester.tap(decision);
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .text('Keep record 10 and merge the other record • DOB unknown')
            .last,
      );
      await tester.pumpAndSettle();
      expect(find.text('Import into herd'), findsNothing);
      await tester.ensureVisible(find.text('Review import'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review import'));
      await tester.pumpAndSettle();
      expect(gateway.aliasChoice, '10');
      expect(gateway.commits, 0);
    },
  );
  testWidgets('a private draft restores without collecting again', (
    tester,
  ) async {
    final gateway = FakeGlobalPedigree()
      ..draft = {
        'ring_id': 'one',
        'account': 'fixture',
        'animals': [
          {'source_id': '10', 'name': 'Restored Rabbit', 'sex': 'Buck'},
        ],
      };
    await tester.pumpWidget(
      MaterialApp(home: GlobalPedigreeImportScreen(gateway: gateway)),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 rabbits and ancestors collected.'), findsOneWidget);
    expect(find.text('Connect and preview'), findsNothing);
    expect(gateway.reviewedHerds, ['one']);
    expect(gateway.commits, 0);
  });
  for (final contradictory in [false, true]) {
    testWidgets(
      'parent-role evidence is a suggestion, not an automatic sex: $contradictory',
      (tester) async {
        final gateway = FakeGlobalPedigree()
          ..draft = {
            'ring_id': 'one',
            'account': 'fixture',
            'animals': [
              {
                'source_id': '10',
                'name': 'Unknown Parent',
                'sex': null,
                'dob': '2022-03-10',
              },
              {
                'source_id': '20',
                'name': 'Child',
                'sex': 'Doe',
                'sire_id': '10',
              },
              if (contradictory)
                {
                  'source_id': '21',
                  'name': 'Other Child',
                  'sex': 'Buck',
                  'dam_id': '10',
                },
            ],
          };
        await tester.pumpWidget(
          MaterialApp(home: GlobalPedigreeImportScreen(gateway: gateway)),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('sex-10')),
          200,
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            contradictory
                ? 'Listed as both sire and dam. Check the source before choosing.'
                : 'Listed as sire of 1 records — suggests Buck. Please confirm.',
          ),
          findsOneWidget,
        );
        final field = tester.widget<DropdownButtonFormField<String>>(
          find.byKey(const ValueKey('sex-10')),
        );
        expect(field.initialValue, isNull);
        expect(gateway.reviewedSex, isNull);
        expect(gateway.commits, 0);
      },
    );
  }
}
