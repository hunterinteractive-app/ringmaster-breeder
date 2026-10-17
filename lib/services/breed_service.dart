import '../offline/offline_runtime.dart';

class BreedService {
  static Future<List<String>> fetchBreeds(String species) async {
    final response = await OfflineRuntime.client
        .from('breeds')
        .select('name')
        .eq('species', species)
        .order('name');

    return response.map<String>((e) => e['name'] as String).toList();
  }
}
