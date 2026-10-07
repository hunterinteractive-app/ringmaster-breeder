import 'package:supabase_flutter/supabase_flutter.dart';

class VarietyService {
  static Future<List<String>> fetchVarieties({
    required String breedName,
    required String species,
  }) async {
    if (breedName.isEmpty) return [];

    final client = Supabase.instance.client;

    // 1️⃣ Get breed ID
    final breed = await client
        .from('breeds')
        .select('id')
        .eq('name', breedName)
        .eq('species', species.toLowerCase())
        .maybeSingle();

    if (breed == null) return [];

    final breedId = breed['id'];

    // 2️⃣ Get varieties for that breed
    final response = await client
        .from('varieties')
        .select('name')
        .eq('breed_id', breedId)
        .order('name');

    return response.map<String>((v) => v['name'] as String).toList();
  }
}