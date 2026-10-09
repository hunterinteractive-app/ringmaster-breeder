import 'package:supabase_flutter/supabase_flutter.dart';
import 'family_service.dart';

abstract interface class RecordImportGateway {
  Future<List<Map<String, dynamic>>> ownedRings();
  Future<Map<String, dynamic>> lookup();
  Future<Map<String, dynamic>> importRecords(Map<String, dynamic> selection);
}

class RecordImportService implements RecordImportGateway {
  final SupabaseClient client;
  RecordImportService(this.client);
  @override
  Future<List<Map<String, dynamic>>> ownedRings() async {
    await FamilyService.refresh();
    final owner = FamilyService.households.firstWhere(
      (h) => h['is_owner'] == true,
    )['owner_user_id'];
    return List<Map<String, dynamic>>.from(
      await client
          .from('farms')
          .select('id,name')
          .eq('owner_id', owner)
          .order('created_at'),
    );
  }

  @override
  Future<Map<String, dynamic>> lookup() async => Map<String, dynamic>.from(
    (await client.functions.invoke(
          'import-ringmaster-records',
          body: {'action': 'lookup'},
        )).data
        as Map,
  );
  @override
  Future<Map<String, dynamic>> importRecords(
    Map<String, dynamic> selection,
  ) async => Map<String, dynamic>.from(
    (await client.functions.invoke(
          'import-ringmaster-records',
          body: {...selection, 'action': 'import'},
        )).data
        as Map,
  );
}
