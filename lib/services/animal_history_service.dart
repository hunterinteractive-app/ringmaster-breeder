import 'package:supabase_flutter/supabase_flutter.dart';
import '../offline/offline_runtime.dart';

enum AnimalHistorySource { globalPedigree, rabbitRegister, kintraks }

class AnimalHistoryService {
  static Future<Set<AnimalHistorySource>> sources(
    String animalId, {
    SupabaseClient? client,
  }) async {
    Future<Map<String, dynamic>> fetch() async {
      final db = client ?? OfflineRuntime.client;
      // Match the history screens, including records linked through the sire.
      final rows = await Future.wait([
        db
            .from('global_pedigree_history')
            .select('id')
            .or('animal_id.eq.$animalId,sire_id.eq.$animalId')
            .limit(1),
        db
            .from('rabbit_register_animals')
            .select('animal_id')
            .eq('animal_id', animalId)
            .limit(1),
        db
            .from('rabbit_register_records')
            .select('animal_id')
            .or('animal_id.eq.$animalId,sire_id.eq.$animalId')
            .limit(1),
        db
            .from('kintraks_animals')
            .select('animal_id')
            .eq('animal_id', animalId)
            .limit(1),
      ]);
      return {
        'globalPedigree': rows[0].isNotEmpty,
        'rabbitRegister': rows[1].isNotEmpty || rows[2].isNotEmpty,
        'kintraks': rows[3].isNotEmpty,
      };
    }

    final flags = client != null
        ? await fetch()
        : await OfflineRuntime.readThrough(
            'animal-import-history:$animalId',
            fetch,
          );
    return {
      for (final source in AnimalHistorySource.values)
        if (flags[source.name] == true) source,
    };
  }
}
