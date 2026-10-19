import 'package:supabase_flutter/supabase_flutter.dart';
import 'family_service.dart';
import '../offline/offline_runtime.dart';

abstract interface class RecordImportGateway {
  Future<List<Map<String, dynamic>>> ownedRings();
  Future<Map<String, dynamic>> lookup();
  Future<Map<String, dynamic>> importRecords(Map<String, dynamic> selection);
}

abstract interface class ProfileOnboardingGateway {
  Future<bool> needsReview();
}

class ProfileOnboardingService implements ProfileOnboardingGateway {
  final SupabaseClient client;
  ProfileOnboardingService(this.client);

  @override
  Future<bool> needsReview() async {
    await FamilyService.refresh();
    final owner = FamilyService.households.firstWhere(
      (h) => h['is_owner'] == true,
    )['owner_user_id'];
    final status = await OfflineRuntime.readThrough(
      'profile-onboarding:$owner',
      () async {
        final profiles = await client
            .from('breeder_exhibitor_profiles')
            .select('id')
            .eq('owner_id', owner)
            .limit(1);
        final herds = await client
            .from('farms')
            .select('id')
            .eq('owner_id', owner)
            .eq('is_demo', false)
            .limit(1);
        return {'needed': profiles.isEmpty && herds.isEmpty};
      },
    );
    return status['needed'] == true;
  }
}

class RecordImportService implements RecordImportGateway {
  final SupabaseClient client;
  final bool requireServerConfirmation;
  RecordImportService(this.client, {this.requireServerConfirmation = false});

  // Onboarding must confirm the import now. The normal offline import flow
  // saves a job for later, which cannot complete this first-login step.
  Map<String, dynamic>? get _queryParameters =>
      requireServerConfirmation ? {'__breeder_network': '1'} : null;
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
  Future<Map<String, dynamic>> lookup() async => OfflineRuntime.serviceResult(
    (await client.functions.invoke(
          'import-ringmaster-records',
          body: {'action': 'lookup'},
          queryParameters: _queryParameters,
        )).data
        as Map,
  );
  @override
  Future<Map<String, dynamic>> importRecords(
    Map<String, dynamic> selection,
  ) async => OfflineRuntime.serviceResult(
    (await client.functions.invoke(
          'import-ringmaster-records',
          body: {...selection, 'action': 'import'},
          queryParameters: _queryParameters,
        )).data
        as Map,
  );
}
