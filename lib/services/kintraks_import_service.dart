import 'package:supabase_flutter/supabase_flutter.dart';
import '../offline/offline_runtime.dart';
import 'record_import_service.dart';

abstract interface class KintraksImportGateway {
  Future<List<Map<String, dynamic>>> ownedHerds();
  Future<List<String>> sources(String herd);
  Future<Map<String, dynamic>> run(
    String herd,
    String source,
    Map<String, dynamic> data, {
    bool commit = false,
  });
}

class KintraksImportService implements KintraksImportGateway {
  final SupabaseClient client;
  KintraksImportService(this.client);

  @override
  Future<List<Map<String, dynamic>>> ownedHerds() async {
    final herds = await RecordImportService(client).ownedRings();
    if (herds.isEmpty) return [];
    return List<Map<String, dynamic>>.from(
      await client
          .from('farms')
          .select('id,name')
          .inFilter('id', herds.map((h) => h['id']).toList())
          .eq('is_demo', false)
          .order('created_at'),
    );
  }

  @override
  Future<List<String>> sources(String herd) async {
    final rows = await client
        .from('kintraks_sources')
        .select('source')
        .eq('ring_id', herd)
        .order('source');
    return rows.map((r) => r['source'] as String).toList();
  }

  @override
  Future<Map<String, dynamic>> run(
    String herd,
    String source,
    Map<String, dynamic> data, {
    bool commit = false,
  }) async => OfflineRuntime.serviceResult(
    await client.rpc(
      'import_kintraks',
      params: {
        'p_ring': herd,
        'p_source': source,
        'p_data': data,
        'p_commit': commit,
      },
    ),
  );
}
