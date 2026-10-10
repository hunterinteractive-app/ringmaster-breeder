import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/models/pedigree_entry.dart';
import 'package:ringmaster_breeder/services/pedigree_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Draft snapshot preserves repeated ancestors and all export details',
    () async {
      final entry = PedigreeEntry();
      entry.nodes[entry.root]!.addAll({
        'name': 'HH77',
        'tattoo': '77',
        'breed': 'Tan',
      });
      entry.ensure(1);
      entry.ensure(2);
      final shared = entry.ensure(3);
      entry.nodes[shared]!.addAll({
        'name': "Daly's Viper",
        'tattoo': 'VIP',
        'dob': '2015-07-15',
        'registration_number': 'F803P',
        'grand_champion_number': 'M826',
        'legs': 13,
        'weight': 5.01,
        'variety': 'Black',
        'leg_details': 'BOB 02/11/17-HHR',
      });
      entry.link(5, shared);
      final snapshot = entry.snapshot();
      expect(snapshot.keys, PedigreeEntry.snapshotSlots);
      expect(snapshot['sire_sire'], snapshot['dam_sire']);
      expect(snapshot['sire_sire']['leg_details'], 'BOB 02/11/17-HHR');
      expect(snapshot['animal']['species'], 'rabbit');
      expect(snapshot['gg1'], isNull);
      final pdf = await PedigreePdfService.generate(
        pedigree: snapshot,
        seller: {'name': 'Example Breeder'},
      );
      expect(pdf.length, greaterThan(1000));
    },
  );
}
