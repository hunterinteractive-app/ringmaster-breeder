import 'package:supabase_flutter/supabase_flutter.dart';
import '../offline/offline_runtime.dart';
import 'record_import_service.dart';

abstract interface class RabbitRegisterImportGateway {
  Future<List<Map<String, dynamic>>> ownedHerds();
  Future<List<String>> sources(String herd);
  Future<Map<String, dynamic>> run(
    String herd,
    String source,
    Map<String, dynamic> data, {
    bool commit = false,
  });
}

class RabbitRegisterImportService implements RabbitRegisterImportGateway {
  final SupabaseClient client;
  RabbitRegisterImportService(this.client);

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
        .from('rabbit_register_sources')
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
      'import_rabbit_register',
      params: {
        'p_ring': herd,
        'p_source': source,
        'p_data': data,
        'p_commit': commit,
      },
    ),
  );
}
