import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/utils/show_results.dart';
import 'package:ringmaster_breeder/models/pedigree_layout.dart';

void main() {
  Map<String, dynamic> result({bool available = true, bool dq = false}) => {
    'animal_id': 'animal-1',
    'source_available': available,
    'record': {
      'is_shown': true,
      'is_disqualified': dq,
      'shows': {'name': 'Autumn Show', 'start_date': '2026-10-11'},
      'entry_awards': [
        {'award_code': 'Best In Show'},
        {'award_code': 'BIS'},
        {'award_code': 'BOB'},
      ],
    },
  };
  test(
    'Major wins are separate, deduplicated and present for repeated ancestors',
    () {
      final p = <String, dynamic>{
        'animal': {'id': 'animal-1', 'leg_details': 'Hand-entered award'},
        'sire': {'existing_id': 'animal-1'},
      };
      attachPedigreeWins(p, [result(), result()]);
      expect(p['animal']['leg_details'], 'Hand-entered award');
      expect(
        p['animal']['synced_show_details'],
        'BIS, BOB • 10/11/2026 • Autumn Show',
      );
      expect(
        p['sire']['synced_show_details'],
        p['animal']['synced_show_details'],
      );
      expect(
        PedigreeLayout(p).details.first.join(' '),
        contains('Autumn Show'),
      );
      attachPedigreeWins(p, []);
      expect(p['animal']['synced_show_details'], '');
      expect(p['animal']['leg_details'], 'Hand-entered award');
    },
  );
  test(
    'Withdrawn, disqualified and no-show results cannot add pedigree wins',
    () {
      expect(pedigreeWins(result(available: false)), isEmpty);
      expect(pedigreeWins(result(dq: true)), isEmpty);
      final r = result();
      r['record']['is_shown'] = false;
      expect(pedigreeWins(r), isEmpty);
    },
  );
  test(
    'Legacy results supply placing and normalized awards, not invented values',
    () {
      final r = <String, dynamic>{
        'result_details': [
          {'placing_label': '2', 'award': 'Best In Show'},
        ],
      };
      expect(showPlacement(r), '2');
      expect(showAwards(r), ['BIS']);
      expect(placingLabel('11'), '11th place');
      expect(placingLabel('22'), '22nd place');
      expect(placingLabel(showPlacement({})), 'Not recorded');
      expect(showAwards({}), isEmpty);
    },
  );
}
