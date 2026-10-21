import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/imports/rabbit_register_xml.dart';

String animal({
  String id = '1',
  String sex = 'Buck',
  String extra = '',
  bool unnamed = false,
}) =>
    '<Record><CID>$id</CID><Breed>Dutch</Breed><Storage_Area>Active_I:Active</Storage_Area>${unnamed ? '' : '<Name>Test &amp; Rabbit</Name><Ear_Num>T1</Ear_Num>'}<Sex>$sex</Sex>$extra</Record>';
RabbitRegisterExport parse(String s) =>
    RabbitRegisterExport.parse(utf8.encode(s));
String xml(String animals, {String history = '', bool close = true}) =>
    '<ExportedData><Animals>$animals</Animals>$history${close ? '</ExportedData>' : ''}';

void main() {
  test('reads source identities, entities, fields, parent links and grams', () {
    final e = parse(
      xml(
        '${animal(extra: '<SireKey>2</SireKey><DOB>2014-01-03</DOB><Weight>1814.368</Weight><Legs>2</Legs><Reg_>R1</Reg_>')}${animal(id: '2')}',
      ),
    );
    expect(e.animals.first['name'], 'Test & Rabbit');
    expect(e.animals.first['profile_weight'], 4);
    expect(e.animals.first['sire_id'], '2');
    expect(e.animals.first['registration_number'], 'R1');
    expect(e.animals.first['raw']['Weight'], '1814.368');
    expect(e.recovered, false);
  });
  test(
    'recovers only the missing root closing tag and requires acknowledgment',
    () {
      final e = parse(xml(animal(), close: false));
      expect(e.recovered, true);
      expect(e.payload()['warnings_acknowledged'], false);
      expect(e.warnings.any((w) => w.contains('did not finish')), true);
      expect(
        () => parse('<ExportedData><Animals>${animal()}<Record><CID>2'),
        throwsFormatException,
      );
      expect(
        () => parse('<ExportedData><Animals>${animal()}'),
        throwsFormatException,
      );
    },
  );
  test(
    'preserves archives and missing references without inventing ancestors',
    () {
      final e = parse(
        xml(
          animal(
            extra: '<DamKey>99</DamKey>',
          ).replaceAll('Active_I:Active', 'Arch._II:Archive'),
        ),
      );
      expect(e.animals.single['status'], 'archived');
      expect(e.animals.single['dam_id'], '99');
      expect(e.warnings.any((w) => w.contains('missing dam 99')), true);
      expect(e.animals.length, 1);
    },
  );
  test('unknown sex is explicit and unnamed animals use source ID label', () {
    final e = parse(xml(animal(sex: '?', unnamed: true)));
    expect(e.animals.single['sex'], isNull);
    expect(e.animals.single['name'], 'Rabbit Register #1');
    final payload = e.payload(sexes: {'1': 'Doe'});
    expect((payload['animals'] as List).single['sex'], 'Doe');
    expect(e.animals.single['raw']['Sex'], '?');
  });
  test(
    'rejects duplicate IDs, duplicate fields, unknown sections and XML entities',
    () {
      expect(() => parse(xml('${animal()}${animal()}')), throwsFormatException);
      expect(
        () => parse(xml(animal(extra: '<CID>2</CID>'))),
        throwsFormatException,
      );
      expect(
        () => parse(xml(animal(), history: '<Expenses/>')),
        throwsFormatException,
      );
      expect(
        () => parse(
          '<!DOCTYPE x [<!ENTITY secret SYSTEM "file:///etc/passwd">]>${xml(animal())}',
        ),
        throwsFormatException,
      );
      expect(() => parse('<Other/>'), throwsFormatException);
    },
  );
  test(
    'retains all history and nested contact fields, normalizes dated weights',
    () {
      final e = parse(
        xml(
          animal(),
          history:
              '<Contacts><Record><ID>1</ID><Categories><Cats><Cat>Buyer</Cat></Cats></Categories></Record></Contacts><Winnings><Record><ID>1</ID><CID>1</CID><WINS>BOB</WINS></Record></Winnings><Litters><Record><ID>1</ID><DAMIDKEY>1</DAMIDKEY><DATEWEANED>0100-01-01</DATEWEANED></Record></Litters><CritterWeights><Record><ID>1</ID><CRITTERKEY>1</CRITTERKEY><CRITTERWT>1814.368</CRITTERWT><WEIGHINGDATE>2014-02-07</WEIGHINGDATE></Record></CritterWeights>',
        ),
      );
      expect(e.records.length, 4);
      expect(
        e.records.first['raw']['Categories'],
        contains('<Cat>Buyer</Cat>'),
      );
      expect(e.records.last['weight'], 4);
      expect(e.records.last['recorded_date'], '2014-02-07');
      expect(e.records[2]['raw']['DATEWEANED'], '0100-01-01');
    },
  );
  test(
    'reads expanded sections without turning blank or zero weights into chart values',
    () {
      final e = parse(
        xml(
          animal(),
          history:
              '<CritterWeights><Record><ID>1</ID><CRITTERKEY>1</CRITTERKEY><CRITTERWT>0</CRITTERWT><WEIGHINGDATE>0100-01-02</WEIGHINGDATE><FEEDWT>-1.5</FEEDWT></Record></CritterWeights>'
              '<LitterWeights><Record><ID>2</ID><LITTERKEY>3</LITTERKEY><LITTERWT>24</LITTERWT></Record></LitterWeights>'
              '<Wool><Record><WID>4</WID><CID>1</CID><PRIME>20</PRIME></Record></Wool>'
              '<PictureMap><Record><PID>5</PID><CRITTERKEY>1</CRITTERKEY><FILENAME>photo.jpg</FILENAME></Record></PictureMap>'
              '<Mileage><Record><MIID>6</MIID><MILEAGEIN>12.3</MILEAGEIN></Record></Mileage>',
        ),
      );
      expect(e.records.map((r) => r['kind']), [
        'weight',
        'litter_weight',
        'wool',
        'picture',
        'mileage',
      ]);
      expect(e.records.first['weight'], isNull);
      expect(e.records.first['recorded_date'], isNull);
      expect(e.records.first['raw']['FEEDWT'], '-1.5');
      expect(e.records[1]['litter_source_id'], '3');
      expect(e.records[2]['animal_source_id'], '1');
      expect(e.warnings.any((w) => w.contains('source history only')), isTrue);
    },
  );
  test('empty date sentinel stays missing and dates cannot roll over', () {
    for (final date in [
      '0100-01-01',
      '0100-01-02',
      '0100-01-03',
      '2100-12-12',
    ]) {
      final e = parse(
        xml(
          animal(
            extra: '<DOB>$date</DOB><DOD>$date</DOD><DateSold>$date</DateSold>',
          ),
          history:
              '<CritterWeights><Record><ID>1</ID><CRITTERKEY>1</CRITTERKEY><CRITTERWT>1814.368</CRITTERWT><WEIGHINGDATE>$date</WEIGHINGDATE></Record></CritterWeights>',
        ),
      );
      expect(e.animals.single['dob'], isNull);
      for (final field in ['DOB', 'DOD', 'DateSold']) {
        expect(e.animals.single['raw'][field], date);
      }
      expect(e.records.single['recorded_date'], isNull);
      expect(e.records.single['raw']['WEIGHINGDATE'], date);
      final archived = parse(
        xml(
          animal(
            extra: '<DOD>$date</DOD><DateSold>$date</DateSold>',
          ).replaceAll('Active_I:Active', 'Arch._I:Archive'),
        ),
      );
      expect(archived.animals.single['status'], 'archived');
    }
    for (final date in ['0100-01-04', '2014-02-30', '2999-01-01', 'garbage']) {
      expect(
        () => parse(xml(animal(extra: '<DOB>$date</DOB>'))),
        throwsFormatException,
      );
    }
  });
  test(
    'weights always convert from grams and invalid measurements are rejected',
    () {
      expect(
        parse(
          xml(animal(extra: '<Weight>1927.766</Weight>')),
        ).animals.single['profile_weight'],
        4.25,
      );
      for (final w in ['-1', 'NaN', 'Infinity', 'bad']) {
        expect(
          () => parse(xml(animal(extra: '<Weight>$w</Weight>'))),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'existing choices are explicit and source records remain unmodified',
    () {
      final e = parse(xml(animal()));
      expect(
        (e.payload(matches: {'1': 'new'})['animals'] as List)
            .single['keep_separate'],
        true,
      );
      expect(
        (e.payload(matches: {'1': 'existing-id'})['animals'] as List)
            .single['existing_id'],
        'existing-id',
      );
      expect(e.animals.single.containsKey('existing_id'), false);
    },
  );
  test('cycles need explicit omissions and retain original parent IDs', () {
    final e = parse(
      xml(
        '${animal(extra: '<SireKey>2</SireKey>')}${animal(id: '2', extra: '<SireKey>1</SireKey>')}',
      ),
    );
    final problems = e.parentProblems({});
    expect(problems.length, 1);
    expect(problems.single['reason'], contains('cycle'));
    final p = problems.single;
    final payload = e.payload(omittedParents: {p['key']!});
    final corrected = (payload['animals'] as List).singleWhere(
      (a) => a['source_id'] == p['source_id'],
    );
    expect(corrected[p['side']], isNull);
    expect(corrected['raw']['SireKey'], p['parent_id']);
    expect(e.animals.every((a) => a['sire_id'] != null), true);
  });
  test('parent sex conflicts are surfaced for explicit review', () {
    final e = parse(
      xml(
        '${animal(extra: '<SireKey>2</SireKey>')}${animal(id: '2', sex: 'Doe')}',
      ),
    );
    expect(e.parentProblems({}).single['reason'], contains('sex'));
    expect(e.parentProblems({'2': 'Buck'}), isEmpty);
  });
}
