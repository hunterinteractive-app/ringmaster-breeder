import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/utils/offspring_names.dart';

void main() {
  test('Short tattoos follow the name and skip herd and litter collisions', () {
    final result = generateOffspringNames(
      [
        {'name': 'Maple', 'tattoo': ''},
        {'name': 'Maple', 'tattoo': ''},
        {'name': 'Typed name', 'tattoo': 'MPL3'},
      ],
      [
        {'tattoo': ' mpl '},
        {'tattoo': 'MPL2'},
      ],
      random: Random(1),
    );
    expect(result[0]['tattoo'], 'MPL4');
    expect(result[1]['tattoo'], 'MPL5');
    expect(result[2], {'name': 'Typed name', 'tattoo': 'MPL3'});
    expect(shortenedTattoo('Jasper'), 'JSP');
    expect(shortenedTattoo('Clover'), 'CLV');
  });
  test(
    'Large litters remain unique and repeated generation preserves values',
    () {
      final empty = List.generate(
        100,
        (_) => <String, dynamic>{'name': '', 'tattoo': '', 'sex': 'F'},
      );
      final generated = generateOffspringNames(empty, [], random: Random(2));
      expect(generated.map((a) => a['tattoo']).toSet().length, 100);
      expect(generated.map((a) => a['name']).toSet().length, 100);
      expect(generated.every((a) => a['sex'] == 'F'), isTrue);
      expect(
        generateOffspringNames(generated, [], random: Random(3)),
        generated,
      );
      expect(empty.first['name'], '');
    },
  );
  test('A typed tattoo is preserved while a missing name is generated', () {
    final result = generateOffspringNames([
      {'name': '', 'tattoo': 'CUSTOM'},
    ], []);
    expect(result.single['tattoo'], 'CUSTOM');
    expect(result.single['name'], isNotEmpty);
  });
}
