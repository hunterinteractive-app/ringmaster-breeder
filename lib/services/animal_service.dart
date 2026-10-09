import 'package:supabase_flutter/supabase_flutter.dart';

class AnimalService {
  static SupabaseClient get _client => Supabase.instance.client;
  static Future<Map<String, dynamic>> get(String id) =>
      _client.from('animals').select().eq('id', id).single();
  static Future<Map<String, dynamic>?> parent(String? id) async {
    if (id == null) return null;
    return _client
        .from('animals')
        .select('name, tattoo')
        .eq('id', id)
        .maybeSingle();
  }

  static Future<List<Map<String, dynamic>>> list(String ringId) async =>
      List<Map<String, dynamic>>.from(
        await _client
            .from('animals')
            .select()
            .eq('ring_id', ringId)
            .order('created_at'),
      );
  static Future<List<Map<String, dynamic>>> weights(String animalId) async =>
      List<Map<String, dynamic>>.from(
        await _client
            .from('animal_weights')
            .select()
            .eq('animal_id', animalId)
            .order('recorded_at', ascending: false),
      );
  static Future<double?> latestWeight(String animalId) async {
    final rows = await _client
        .from('animal_weights')
        .select('weight')
        .eq('animal_id', animalId)
        .order('recorded_at', ascending: false)
        .limit(1);
    return rows.isEmpty ? null : (rows.first['weight'] as num).toDouble();
  }

  static Future<void> addWeight(String animalId, double weight) async {
    if (!weight.isFinite || weight <= 0) {
      throw ArgumentError('Weight must be positive');
    }
    await _client.from('animal_weights').insert({
      'animal_id': animalId,
      'weight': weight,
    });
  }

  static Future<void> update(String id, Map<String, dynamic> changes) async {
    await _client.from('animals').update(changes).eq('id', id);
  }
}
