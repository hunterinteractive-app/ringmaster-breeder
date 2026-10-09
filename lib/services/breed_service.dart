import 'package:supabase_flutter/supabase_flutter.dart';

class BreedService {
  static Future<List<String>> fetchBreeds(String species) async {
    final response = await Supabase.instance.client
        .from('breeds')
        .select('name')
        .eq('species', species)
        .order('name');

    return response.map<String>((e) => e['name'] as String).toList();
  }
}
