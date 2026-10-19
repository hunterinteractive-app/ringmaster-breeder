import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/imports/kintraks_csv.dart';

const headers = [
  'Id',
  'Fatherid',
  'Motherid',
  'Name',
  'Sex',
  'Dob',
  'Ear #',
  'Weight',
  'Deceased',
  'Sold',
  'Breed',
  'Colour',
  'Prefix',
  'Suffix',
  'Breeder',
  'Breeder',
  'Notes',
  'Registration #',
  'GC #',
  'Legs',
  'Custom vaccine',
];
String csv(List<List<String>> rows) => rows
    .map((r) => r.map((v) => '"${v.replaceAll('"', '""')}"').join(','))
    .join('\r\n');
List<String> rabbit(
  String id, {
  String name = 'Sample',
  String father = '',
  String mother = '',
  String sex = 'male',
  String dob = '',
  String weight = '3.10',
  String dead = 'False',
  String sold = 'False',
}) => [
  id,
  father,
  mother,
  name,
  sex,
  dob,
  'E$id',
  weight,
  dead,
  sold,
  'Dutch',
  'Black',
  "Breeder's",
  '',
  'True',
  'Example Breeder',
  'Line one\r\nLine "two", end',
  'REG',
  'GC',
  '3',
  'Batch 1',
];
KintraksExport parse(List<List<String>> rows) =>
    KintraksExport.parse(utf8.encode(csv([headers, ...rows])));

void main() {
  test(
    'preserves duplicate columns, custom fields, quoted notes and lb.oz text',
    () {
      final export = parse([rabbit('1')]);
      final a = export.animals.single;
      expect(a['name'], "Breeder's Sample");
      expect(a['raw']['Breeder [1]'], 'True');
      expect(a['raw']['Breeder [2]'], 'Example Breeder');
      expect(a['raw']['Custom vaccine'], 'Batch 1');
      expect(a['raw']['_csv_headers'], headers);
      expect(a['raw']['Notes'], 'Line one\r\nLine "two", end');
      expect(a['raw']['Weight'], '3.10');
      expect(a['profile_weight'], 3.625);
      expect(a['status'], 'archived');
      expect(a['pedigree_only'], true);
      expect(a['registration_number'], 'REG');
      expect(a['grand_champion_number'], 'GC');
    },
  );
  test('weight suffix is ounces without decimal scaling', () {
    for (final pair in {
      '3.13': 3.8125,
      '3.04': 3.25,
      '3.4': 3.25,
      '3.10': 3.625,
      '3.1': 3.0625,
      '4': 4.0,
      '4.00': 4.0,
    }.entries) {
      expect(KintraksExport.poundsAndOunces(pair.key), pair.value);
    }
    expect(KintraksExport.poundsAndOunces('0.0'), isNull);
    for (final bad in ['3.16', '3.99', '3.100', '-1', 'NaN', '1000', '3,4']) {
      expect(() => KintraksExport.poundsAndOunces(bad), throwsFormatException);
    }
  });
  test(
    'activation is explicit, respects sold/deceased, and retains all IDs',
    () {
      final e = parse([
        rabbit('1'),
        rabbit('2', sold: 'True'),
        rabbit('3', dead: 'True'),
        rabbit('4'),
      ]);
      final p =
          e.payload(activeIds: {'1', '2', '3'}, acknowledged: true)['animals']
              as List;
      expect(p.map((a) => a['status']), [
        'active',
        'sold',
        'deceased',
        'archived',
      ]);
      expect(p.map((a) => a['pedigree_only']), [false, false, false, true]);
    },
  );
  test(
    'links parents by source ID and flags chronology and missing references',
    () {
      final e = parse([
        rabbit('1', father: '2', mother: '99', dob: '2020-01-01'),
        rabbit('2', dob: '2021-01-01'),
      ]);
      expect(e.animals.first['sire_id'], '2');
      expect(e.warnings.any((w) => w.contains('on or before')), true);
      expect(e.warnings.any((w) => w.contains('missing dam 99')), true);
      final p = e.payload(omittedParents: {'1:sire_id'})['animals'] as List;
      expect(p.first['sire_id'], isNull);
      expect(p.first['raw']['Fatherid'], '2');
    },
  );
  test('cycles and wrong parent sex require explicit review', () {
    final e = parse([
      rabbit('1', father: '2'),
      rabbit('2', father: '1', sex: 'female'),
    ]);
    final problems = e.parentProblems({});
    expect(problems.any((p) => p['reason']!.contains('sex')), true);
    expect(problems.any((p) => p['reason']!.contains('cycle')), true);
  });
  test(
    'unknown sex is never guessed; repeat names and ear numbers never merge',
    () {
      final e = parse([rabbit('1', sex: '?'), rabbit('2', sex: '?')]);
      expect(e.animals.length, 2);
      expect(e.animals.first['sex'], isNull);
      final p =
          e.payload(
                sexes: {'1': 'Doe'},
                matches: {'1': 'new', '2': 'chosen'},
              )['animals']
              as List;
      expect(p.first['sex'], 'Doe');
      expect(p.first['keep_separate'], true);
      expect(p.last['existing_id'], 'chosen');
    },
  );
  test('invalid source leg counts remain raw and require review', () {
    final row = rabbit('1');
    row[19] = '4.03';
    final e = parse([row]);
    expect(e.animals.single['legs'], isNull);
    expect(e.animals.single['raw']['Legs'], '4.03');
    expect(e.warnings.any((w) => w.contains('non-integer leg count')), true);
  });
  test(
    'corrections revalidate dates and weight while keeping original cells',
    () {
      final row = rabbit('1', dob: '2001-01-01');
      row[19] = '4.03';
      row[7] = '';
      final e = parse([row]);
      final fixed = e.withCorrections({
        '1': {
          'Legs': '',
          'Weight': '4.03',
          'Dob': '2021-01-01',
          'Breed': 'Himalayan',
          'Custom vaccine': 'Corrected batch',
        },
      });
      final a = fixed.animals.single;
      expect(a['dob'], '2021-01-01');
      expect(a['profile_weight'], 4.1875);
      expect(a['legs'], isNull);
      expect(a['raw']['Legs'], '4.03');
      expect(a['raw']['Weight'], '');
      expect(a['raw']['Dob'], '2001-01-01');
      expect(a['corrections']['Weight'], '4.03');
      expect(a['breed'], 'Himalayan');
      expect(
        fixed.warnings.any((w) => w.contains('non-integer leg count')),
        false,
      );
      final reset = fixed.withCorrections({});
      expect(reset.animals.single['dob'], '2001-01-01');
      expect(reset.animals.single['profile_weight'], isNull);
      expect(
        () => e.withCorrections({
          '1': {'Id': '2'},
        }),
        throwsFormatException,
      );
      expect(
        () => e.withCorrections({
          '1': {'Weight': '4.16'},
        }),
        throwsFormatException,
      );
      expect(
        () => e.withCorrections({
          '1': {'Dob': '2020-02-30'},
        }),
        throwsFormatException,
      );
    },
  );
  test('rejects malformed files, repeated IDs, bad flags and dates', () {
    expect(() => parse([rabbit('1'), rabbit('1')]), throwsFormatException);
    expect(() => parse([rabbit('1', dead: 'maybe')]), throwsFormatException);
    expect(
      () => parse([rabbit('1', dob: '2020-02-30')]),
      throwsFormatException,
    );
    expect(
      () => parse([rabbit('1', dob: '2999-01-01')]),
      throwsFormatException,
    );
    for (final text in [
      '"unclosed',
      'Id;Name\n1;Example',
      csv([headers, rabbit('1').sublist(1)]),
      '"Id"x,"Name"',
    ]) {
      expect(
        () => KintraksExport.parse(utf8.encode(text)),
        throwsFormatException,
      );
    }
    expect(() => KintraksExport.parse([255]), throwsFormatException);
  });
}
