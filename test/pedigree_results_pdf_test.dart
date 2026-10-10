import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/services/pedigree_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('render partial pedigree with results', () async {
    final bytes = await PedigreePdfService.generate(
      pedigree: {
        'animal': {
          'name': "HENRY'S HH9",
          'tattoo': 'HH9',
          'species': 'rabbit',
          'legs': 4,
          'leg_details':
              'BOB 05/13/17-LIVINGSTONCORBA\nPlaced: 1/10 05/06/17-TNS\nBOV 04/01/17-GPRBA\nBOS 02/18/17-PaRBA-B',
        },
      },
    );
    expect(bytes.length, greaterThan(1000));
  });
}
