import '../offline/offline_runtime.dart';
import 'family_service.dart';
import '../utils/show_results.dart';
import '../utils/production_measurements.dart';

class PedigreeService {
  static Future<Map<String, dynamic>> seller() async {
    final client = OfflineRuntime.client;
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Not logged in');
    final profile = await client
        .from('users')
        .select()
        .eq('id', FamilyService.ownerId ?? user.id)
        .single();
    return {
      'name': [
        profile['rabbitry_name'],
        profile['display_name'],
      ].whereType<String>().where((v) => v.trim().isNotEmpty).join(' · '),
      'address': profile['address'],
      'city': profile['city'],
      'state': profile['state'],
      'zip': profile['zip'],
      'contact': [
        profile['phone'],
        profile['email'],
      ].whereType<String>().where((v) => v.isNotEmpty).join(' • '),
    };
  }

  static Future<Map<String, dynamic>> build(String animalId) async =>
      withShowWins(
        Map<String, dynamic>.from(
          await OfflineRuntime.client.rpc(
                'breeder_pedigree_snapshot',
                params: {'p_animal_id': animalId},
              )
              as Map,
        ),
      );
  static Future<Map<String, dynamic>> withShowWins(
    Map<String, dynamic> pedigree,
  ) async {
    final ids = pedigree.values
        .whereType<Map>()
        .map((a) => a['id'] ?? a['existing_id'])
        .whereType<String>()
        .toSet()
        .toList();
    if (ids.isEmpty) return pedigree;
    final rows = <Map<String, dynamic>>[];
    for (var start = 0; ; start += 500) {
      final page = await OfflineRuntime.client
          .from('breeder_show_history')
          .select('animal_id,record,source_available')
          .inFilter('animal_id', ids)
          .eq('source_available', true)
          .order('id')
          .range(start, start + 499);
      rows.addAll(page);
      if (page.length < 500) break;
    }
    rows.sort(
      (a, b) => (b['record']['shows']?['start_date'] ?? '')
          .toString()
          .compareTo((a['record']['shows']?['start_date'] ?? '').toString()),
    );
    attachPedigreeWins(pedigree, rows);
    try {
      final animals = await OfflineRuntime.client
          .from('animals')
          .select('id,ring_id')
          .inFilter('id', ids);
      final herds = animals
          .map((a) => a['ring_id'])
          .whereType<String>()
          .toSet()
          .toList();
      if (herds.isNotEmpty) {
        final settings = await OfflineRuntime.client
            .from('wool_settings')
            .select()
            .inFilter('ring_id', herds)
            .eq('show_on_pedigree', true);
        if (settings.isNotEmpty) {
          final wool = <Map<String, dynamic>>[];
          for (var start = 0; ; start += 500) {
            final page = await OfflineRuntime.client
                .from('animal_wool_records')
                .select(
                  'animal_id,recorded_date,fleece_grams,measurements,voided',
                )
                .inFilter('animal_id', ids)
                .eq('voided', false)
                .order('id')
                .range(start, start + 499);
            wool.addAll(page);
            if (page.length < 500) break;
          }
          attachWoolPedigreeSummary(pedigree, animals, settings, wool);
        }
      }
    } catch (e) {
      if (!isOfflineTransportError(e)) rethrow;
      // Optional production summaries do not block an otherwise usable pedigree
      // when their online-only records are unavailable.
    }
    return pedigree;
  }
}
