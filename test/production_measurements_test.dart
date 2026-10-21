import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/imports/rabbit_register_xml.dart';
import 'package:ringmaster_breeder/screens/production_measurements_screen.dart';
import 'package:ringmaster_breeder/screens/breeding_tracker_screen.dart';
import 'package:ringmaster_breeder/utils/production_measurements.dart';
import 'package:ringmaster_breeder/utils/herd_calendar.dart';
import 'package:ringmaster_breeder/widgets/wool_production_summary.dart';
import 'package:ringmaster_breeder/screens/rabbit_register_history_screen.dart';

void main() {
  test('Field-guide spelling aliases can be corrected or cleared', () {
    final canonical = canonicalWool({
      'FELTEDSTAINDED': 4,
      'VEFGMATTERBASE': 2,
      'Unknown': 'Keep',
    });
    expect(canonical, {
      'FELTEDSTAINED': 4,
      'VEGMATTERBASE': 2,
      'Unknown': 'Keep',
    });
    canonical.remove('FELTEDSTAINED');
    expect(canonicalWool(canonical).containsKey('FELTEDSTAINED'), false);
  });

  testWidgets(
    'Pounds and ounces entry converts to grams and permits text input',
    (t) async {
      Map<String, dynamic>? saved;
      await t.pumpWidget(
        MaterialApp(
          home: ProductionMeasurementsScreen(
            recordId: 'rabbit',
            wool: true,
            loader: () async => [],
            writer: (r) async => saved = r,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byType(FloatingActionButton));
      await t.pumpAndSettle();
      await t.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'Grams'),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Pounds & ounces').last);
      await t.pumpAndSettle();
      final fleece = find.widgetWithText(
        TextField,
        'Total fleece weight (lb & oz) · optional',
      );
      expect(t.widget<TextField>(fleece).keyboardType, TextInputType.text);
      await t.enterText(fleece, '1 lb 4 oz');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(saved?['fleece_grams'], closeTo(566.99, 0.000001));
      expect(t.takeException(), isNull);
    },
  );

  test('Exact original XML survives decoding, recovery and import decisions', () {
    const source =
        '\ufeff<ExportedData><Header><ProgramVersion>15.test</ProgramVersion><Custom>öÉ</Custom></Header><Animals><Record><CID>1</CID><Name>  Name  </Name><Sex>Buck</Sex><Breed>Dutch</Breed><Storage_Area>I:Active</Storage_Area><Extra> Keep whitespace </Extra></Record></Animals>\r\n';
    final parsed = RabbitRegisterExport.parse(utf8.encode(source));
    expect(parsed.recovered, isTrue);
    expect(
      base64Decode(
        parsed.payload(filename: 'Original.XML')['original_file_base64'],
      ),
      utf8.encode(source),
    );
    expect(parsed.header['Custom'], 'öÉ');
    expect(
      parsed.payload()['animals'].single['raw']['Extra'],
      'Keep whitespace',
    );
  });
  test('Judging edits preserve unknown XML and escape breeder text', () {
    const original =
        '<JudgingInfo><EvalDate>0100-01-03</EvalDate><Judge>Original</Judge><Extra><Value>Keep</Value></Extra></JudgingInfo>';
    expect(woolJudging({'XMLDATA': original})['EvalDate'], '');
    final edited = updateWoolJudging({
      'Judge': 'A & B',
      'WoolPerf': 'Good <fine>',
    }, original);
    expect(edited, contains('<Value>Keep</Value>'));
    expect(woolJudging({'XMLDATA': edited})['Judge'], 'A & B');
    expect(woolJudging({'XMLDATA': edited})['WoolPerf'], 'Good <fine>');
    expect(
      woolJudging({
        'XMLDATA':
            '<!DOCTYPE x [<!ENTITY e SYSTEM "file:///etc/passwd">]><JudgingInfo/>',
      }),
      isEmpty,
    );
  });
  test(
    'Cumulative feed is a reading; missing/zero live weight has no ratio',
    () {
      expect(feedWeightRatio(12, 4), 3);
      expect(feedWeightRatio(0, 4), 0);
      expect(feedWeightRatio(12, 0), isNull);
      expect(feedWeightRatio(null, 4), isNull);
      expect(
        gradedWoolTotal({
          'PRIME': 20,
          'GRADE2': 10,
          'COMBINGS': 5,
          'FELTEDSTAINED': 4,
        }),
        39,
      );
      expect(gradedWoolTotal({}), isNull);
    },
  );
  test('Wool yields, calendar summaries and units share one calculation', () {
    final rows = <Map<String, dynamic>>[
      {
        'animal_id': 'rabbit',
        'recorded_date': '2026-10-01',
        'measurements': {
          'PRIME': 20,
          'GRADE2': 10,
          'COMBINGS': 4,
          'FELTEDSTAINED': 4,
        },
      },
      {
        'animal_id': 'rabbit',
        'recorded_date': '2026-10-02',
        'measurements': {'PRIME': 10},
      },
      {
        'animal_id': 'rabbit',
        'recorded_date': null,
        'measurements': {'PRIME': 100},
      },
      {
        'animal_id': 'rabbit',
        'recorded_date': '2026-10-03',
        'voided': true,
        'measurements': {'PRIME': 100},
      },
      {
        'animal_id': 'rabbit',
        'recorded_date': '2027-01-01',
        'measurements': {'PRIME': 100},
      },
    ];
    expect(woolYield(rows.first, 'gross', {}), 38);
    expect(
      woolYield(rows.first, 'adjusted', defaultWoolSettings['factors']),
      29.5,
    );
    final config = {...defaultWoolSettings, 'metric': 'adjusted'};
    expect(woolSummary(rows, config, now: DateTime(2026, 10, 21)), {
      '2026-10': 39.5,
    });
    expect(woolEntryGrams('1 lb 4 oz', 'lb_oz'), closeTo(566.99, 0.00001));
    expect(() => woolEntryGrams('1 lb 16 oz', 'lb_oz'), throwsFormatException);
    for (final unit in ['g', 'kg', 'oz', 'lb']) {
      expect(
        woolEntryGrams(woolEntryText(123.456, unit), unit),
        closeTo(123.456, 0.000001),
      );
    }
    final pedigree = <String, dynamic>{
      'animal': {'id': 'rabbit'},
    };
    attachWoolPedigreeSummary(
      pedigree,
      [
        {'id': 'rabbit', 'ring_id': 'herd'},
      ],
      [
        {...config, 'ring_id': 'herd', 'show_on_pedigree': true},
      ],
      rows,
      now: DateTime(2026, 10, 21),
    );
    expect(pedigree['animal']['wool_summary'], contains('39.5 g'));
  });
  testWidgets(
    'Wool preferences persist reviewed factors and optional integrations',
    (t) async {
      Map<String, dynamic> current = {...defaultWoolSettings};
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: WoolProductionSummary(
                animalId: 'rabbit',
                records: const [],
                loader: () async => current,
                writer: (data, revision) async => current = Map.of(data),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Wool settings'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Include wool summary on pedigrees'));
      await t.tap(find.text('Include wool summary on pedigrees'));
      await t.ensureVisible(
        find.text('Add harvest body weights to Weight History'),
      );
      await t.tap(find.text('Add harvest body weights to Weight History'));
      await t.tap(find.text('Save settings'));
      await t.pumpAndSettle();
      expect(current['show_on_pedigree'], true);
      expect(current['update_body_weight'], true);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('Unresolved wool is linked only after choosing its rabbit', (
    t,
  ) async {
    String? linked;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LinkWoolRabbitDialog(
            animals: const [
              {'id': 'one', 'name': 'Maple', 'tattoo': 'M1', 'breed': 'Dutch'},
            ],
            writer: (id) async => linked = id,
          ),
        ),
      ),
    );
    expect(find.text('Link selected rabbit'), findsOneWidget);
    await t.tap(find.text('Maple · M1'));
    await t.pump();
    await t.tap(find.text('Link selected rabbit'));
    await t.pumpAndSettle();
    expect(linked, 'one');
  });
  test(
    'Unknown breeding date and completed nest chores work in the calendar',
    () {
      final record = <String, dynamic>{
        'id': 'litter',
        'breeding_date': null,
        'status': 'active',
        'dam': {'id': 'doe', 'name': 'Doe', 'species': 'rabbit'},
        'tracking': {
          'paired_date': '2026-01-01',
          'split_date': '2026-01-02',
          'scheduled_breeding_date': '2026-03-01',
          'rebreeding_enabled': true,
        },
      };
      final events = herdCalendarEvents([record], {}, []);
      expect(
        events.map((e) => e.title),
        containsAll(['Paired', 'Separated / split', 'Scheduled rebreeding']),
      );
      expect(events.any((e) => e.title.contains('Expected birth')), isFalse);
      final nested = herdCalendarEvents(
        [
          {
            ...record,
            'breeding_date': '2026-01-01',
            'tracking': {'nest_installed': true},
          },
        ],
        {},
        [],
      );
      expect(nested.any((e) => e.title == 'Add nesting box'), isFalse);
    },
  );
  for (final width in [390.0, 1200.0]) {
    testWidgets(
      'Feed-only entry saves without a body-weight chart value at $width',
      (t) async {
        t.view.physicalSize = Size(width, 1200);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        Map<String, dynamic>? saved;
        await t.pumpWidget(
          MaterialApp(
            home: ProductionMeasurementsScreen(
              recordId: 'animal',
              animalFeed: true,
              loader: () async => [],
              writer: (row) async => saved = Map.of(row),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.byType(FloatingActionButton));
        await t.pumpAndSettle();
        await t.enterText(
          find.widgetWithText(TextField, 'Cumulative feed (lb) · optional'),
          '12',
        );
        await t.tap(find.text('Save'));
        await t.pumpAndSettle();
        expect(saved?['feed_weight'], 12);
        expect(saved?['weight'], isNull);
        expect(t.takeException(), isNull);
      },
    );
    testWidgets(
      'Advanced wool corrections retain judging and unrecognized measurements at $width',
      (t) async {
        t.view.physicalSize = Size(width, 1300);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        Map<String, dynamic>? saved;
        await t.pumpWidget(
          MaterialApp(
            home: ProductionMeasurementsScreen(
              recordId: 'animal',
              wool: true,
              loader: () async => [
                {
                  'id': 'wool',
                  'recorded_date': null,
                  'measurements': {
                    'CF': 90,
                    'SD': 2,
                    'UnknownLabValue': 'Keep',
                    'XMLDATA':
                        '<JudgingInfo><Judge>Original</Judge><Extra>Keep too</Extra></JudgingInfo>',
                  },
                  'notes': '',
                  'revision': 1,
                },
              ],
              writer: (row) async => saved = Map.of(row),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.byType(ExpansionTile).first);
        await t.pumpAndSettle();
        await t.tap(find.text('Edit measurement'));
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('Fiber quality'));
        await t.tap(find.text('Fiber quality'));
        await t.pumpAndSettle();
        final cf = find.widgetWithText(TextField, 'Comfort factor (%)');
        await t.ensureVisible(cf);
        await t.enterText(cf, '101');
        await t.tap(find.text('Save'));
        await t.pumpAndSettle();
        expect(saved, isNull);
        await t.ensureVisible(cf);
        await t.enterText(cf, '95');
        await t.tap(find.text('Save'));
        await t.pumpAndSettle();
        expect(saved?['measurements']['CF'], 95);
        expect(saved?['measurements']['UnknownLabValue'], 'Keep');
        expect(
          saved?['measurements']['XMLDATA'],
          contains('<Extra>Keep too</Extra>'),
        );
        expect(saved?['recorded_date'], isNull);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Litter details continue tracking imported counts without inventing sex stages',
    (t) async {
      t.view.physicalSize = const Size(1000, 1600);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      Map<String, dynamic>? saved;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LitterTrackingDialog(
              record: {
                'id': 'litter',
                'import_source': 'fixture',
                'breeding_date': null,
                'status': 'active',
                'dam': {'species': 'rabbit'},
                'tracking': {
                  'cage': 'A1',
                  'added': 2,
                  'bucks': 3,
                  'does': 1,
                  'nest_installed': true,
                  'nest_removed': false,
                  'custom_fields': {'Litter note': 'Keep'},
                },
                'offspring': [],
              },
              writer: (d) async => saved = Map.of(d),
            ),
          ),
        ),
      );
      await t.tap(find.text('Additional litter details'));
      await t.pumpAndSettle();
      final field = find.widgetWithText(TextFormField, 'Kept');
      await t.ensureVisible(field);
      await t.enterText(field, '2');
      await t.tap(find.text('Save tracking'));
      await t.pumpAndSettle();
      expect(saved?['kept'], 2);
      expect(saved?['bucks'], 3);
      expect(saved?['weaned_males'], isNull);
      expect(saved?['nest_installed'], true);
      expect(t.takeException(), isNull);
    },
  );
}
