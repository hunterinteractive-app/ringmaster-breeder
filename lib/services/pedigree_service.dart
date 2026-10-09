import 'package:supabase_flutter/supabase_flutter.dart';

class PedigreeService {
  static Future<Map<String, dynamic>> build(String animalId) async =>
      Map<String, dynamic>.from(
        await Supabase.instance.client.rpc(
              'breeder_pedigree_snapshot',
              params: {'p_animal_id': animalId},
            )
            as Map,
      );
}
