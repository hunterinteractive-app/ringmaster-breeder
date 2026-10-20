import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/genetics/genotype_choices.dart';
import 'package:ringmaster_breeder/genetics/coat_rules.dart';

void main() {
  test(
    'Guided parsing handles compact, separated and partial source pairs',
    () {
      for (final text in ['aabbC_ddE_enenV-', 'aa bb C_ dd E_ enen V-']) {
        final parsed = GenotypeChoices.read(text)!;
        expect(parsed.pairs['A']!.first, 'a');
        expect(parsed.pairs['C']!.first, 'C');
        expect(parsed.pairs['C']!.second, isNull);
        expect(parsed.pairs['D']!.second, 'd');
        expect(parsed.pairs['En']!.first, 'en');
      }
      expect(GenotypeChoices.read('at? cchlc EsE')!.pairs['C']!.first, 'cchl');
    },
  );

  test('Every guided allele pair round-trips without guessing other genes', () {
    for (final entry in coatDomains.entries) {
      for (final first in [null, ...entry.value]) {
        for (final second in [null, ...entry.value]) {
          final text = GenotypeChoices.change('', entry.key, first, second);
          final parsed = GenotypeChoices.read(text)!;
          if (first == null && second == null) {
            expect(text, isEmpty);
            expect(parsed.pairs, isEmpty);
          } else {
            final pair = parsed.pairs[entry.key]!;
            expect(pair.first, first ?? second);
            expect(pair.second, first == null ? null : second);
            expect(parsed.pairs.length, 1);
          }
        }
      }
    }
  });

  test('Editing a locus preserves other spaces, case and unknown markers', () {
    const source = 'aa  bb C_\nD? E- enen';
    final changed = GenotypeChoices.change(source, 'B', 'b', 'B');
    expect(changed, 'aa  bB C_\nD? E- enen');
    expect(GenotypeChoices.change(changed, 'V', 'V', null), endsWith(' V-'));
    expect(GenotypeChoices.change('aa bb', 'A', null, null), 'bb');
  });

  test(
    'Unsupported, incomplete and duplicate notation stays Advanced-only',
    () {
      for (final text in [
        'aa bb Sa- L- wewe',
        'AA aa',
        '???',
        'C',
        'cchm-',
        'aa garbage',
        'A b',
        'cc cc',
      ]) {
        expect(GenotypeChoices.read(text), isNull, reason: text);
        expect(
          () => GenotypeChoices.change(text, 'B', 'b', 'b'),
          throwsFormatException,
        );
      }
      expect(
        () => GenotypeChoices.change('', 'B', 'A', null),
        throwsFormatException,
      );
    },
  );
}
