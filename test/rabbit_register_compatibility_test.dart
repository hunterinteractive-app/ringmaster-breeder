import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/imports/rabbit_register_xml.dart';

void main() {
  final bytes = File(
    'test/fixtures/rabbit_register_documented.xml',
  ).readAsBytesSync();
  final source = utf8.decode(bytes);
  RabbitRegisterExport parse(String value) =>
      RabbitRegisterExport.parse(utf8.encode(value));

  test('documented fields import alongside observed export spellings', () {
    final export = RabbitRegisterExport.parse(bytes);
    expect(export.animals.length, 2);
    expect(export.records.length, 12);
    expect(export.animals.first['tattoo'], 'D1');
    expect(export.animals.first['grand_champion_number'], 'GC1');
    expect(export.animals.first['sire_id'], '2');
    expect(export.animals.last['status'], 'deceased');
    final show = export.records.singleWhere((r) => r['kind'] == 'show');
    expect(show['source_id'], '1');
    expect(show['animal_source_id'], '1');
    final litter = export.records.singleWhere((r) => r['kind'] == 'litter');
    expect(litter['animal_source_id'], '1');
    expect(litter['sire_source_id'], '2');
    final weight = export.records.singleWhere((r) => r['kind'] == 'weight');
    expect(weight['animal_source_id'], '1');
    expect(weight['weight'], 4);
    expect(weight['recorded_date'], '2014-04-01');
    expect(
      export.records.singleWhere(
        (r) => r['kind'] == 'litter_weight',
      )['litter_source_id'],
      '1',
    );
    expect(
      export.records.singleWhere(
        (r) => r['kind'] == 'picture',
      )['animal_source_id'],
      '1',
    );
    expect(export.animals.first['raw']['Ear_Number'], 'D1');
    expect(export.animals.first['raw'].containsKey('Ear_Num'), false);
    expect(weight['raw']['CritterWt'], '1814.368');
    expect(weight['raw'].containsKey('CRITTERWT'), false);
    expect(base64Decode(export.originalFileBase64), bytes);
  });

  test(
    'field capitalization and punctuation do not change normalized records',
    () {
      final normal = parse(source);
      final varied = parse(
        source.replaceAllMapped(
          RegExp(r'<(/?)([A-Za-z_][A-Za-z0-9_.-]*)(?=[\s>])'),
          (m) {
            final name = m[2]!;
            if (name == 'ExportedData' ||
                name == 'Record' ||
                name == 'Header' ||
                RabbitRegisterExport.sections.containsKey(name)) {
              return m[0]!;
            }
            return '<${m[1]}${name.toLowerCase()}';
          },
        ),
      );
      Map<String, dynamic> normalized(Map<String, dynamic> row) =>
          {...row}..remove('raw');
      expect(varied.animals.map(normalized), normal.animals.map(normalized));
      expect(varied.records.map(normalized), normal.records.map(normalized));
    },
  );

  test(
    'blank and equivalent aliases are accepted; conflicting aliases block import',
    () {
      expect(
        parse(
          source.replaceFirst(
            '<Ear_Number>D1</Ear_Number>',
            '<Ear_Num/><Ear_Number>D1</Ear_Number>',
          ),
        ).animals.first['tattoo'],
        'D1',
      );
      expect(
        parse(
          source.replaceFirst('<WID>1</WID>', '<ID>1</ID><WID>1</WID>'),
        ).records.singleWhere((r) => r['kind'] == 'show')['source_id'],
        '1',
      );
      for (final (before, after) in [
        (
          '<Ear_Number>D1</Ear_Number>',
          '<Ear_Num>OTHER</Ear_Num><Ear_Number>D1</Ear_Number>',
        ),
        ('<WID>1</WID>', '<ID>99</ID><WID>1</WID>'),
        (
          '<CritterWt>1814.368</CritterWt>',
          '<CRITTERWT>907.184</CRITTERWT><CritterWt>1814.368</CritterWt>',
        ),
      ]) {
        expect(
          () => parse(source.replaceFirst(before, after)),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('Conflicting values'),
            ),
          ),
        );
      }
    },
  );

  test('non-rabbit headers are rejected before rabbits can be created', () {
    expect(
      () => parse(
        source.replaceFirst(
          '<Species>Rabbit</Species>',
          '<Species>Cavy</Species>',
        ),
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Select a Rabbit Register rabbit export'),
        ),
      ),
    );
    expect(
      parse(
        source.replaceFirst(
          '<Species>Rabbit</Species>',
          '<Species> rabbit </Species>',
        ),
      ).animals.length,
      2,
    );
  });

  test(
    'missing root close recovers after empty sections and trailing comments',
    () {
      for (final ending in [
        '<Journal/>',
        '<Journal />\n<!-- Export finished -->',
      ]) {
        final incomplete =
            source
                .replaceFirst('</ExportedData>', '')
                .replaceFirst(RegExp(r'<Journal>.*?</Journal>'), '') +
            ending;
        final export = parse(incomplete);
        expect(export.recovered, true);
        expect(export.animals.length, 2);
        expect(export.records.length, 11);
        expect(
          utf8.decode(base64Decode(export.originalFileBase64)),
          incomplete,
        );
      }
      expect(
        () => parse('<ExportedData><Animals><Record><CID>1</CID>'),
        throwsFormatException,
      );
      expect(
        () => parse(source.replaceFirst('</Record>', '')),
        throwsFormatException,
      );
    },
  );
}
