import 'package:supabase_flutter/supabase_flutter.dart';

class ParentService {
  static final _supabase = Supabase.instance.client;

  static Future<List<Map<String, dynamic>>> fetchSires({
    required String ringId,
    required String species,
  }) async {
    final res = await _supabase
        .from('animals')
        .select('id, name, tattoo')
        .eq('ring_id', ringId)
        .eq('species', species)
        .eq('sex', 'M')
        .neq('status', 'deceased')
        .order('name');

    return List<Map<String, dynamic>>.from(res);
  }

  static Future<List<Map<String, dynamic>>> fetchDams({
    required String ringId,
    required String species,
  }) async {
    final res = await _supabase
        .from('animals')
        .select('id, name, tattoo')
        .eq('ring_id', ringId)
        .eq('species', species)
        .eq('sex', 'F')
        .neq('status', 'deceased')
        .order('name');

    return List<Map<String, dynamic>>.from(res);
  }
}