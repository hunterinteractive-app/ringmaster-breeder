import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/legal_config.dart';
import '../offline/offline_runtime.dart';

abstract class LegalGateway {
  Future<bool> hasAccepted();
  Future<void> accept();
  Future<void> signOut();
}

class LegalService implements LegalGateway {
  final SupabaseClient client;
  final String userId;
  LegalService(this.client, this.userId);
  @override
  Future<bool> hasAccepted() async {
    final result = await OfflineRuntime.readThrough(
      'legal:${LegalConfig.termsVersion}:${LegalConfig.privacyVersion}',
      () async {
        final row = await client
            .from('breeder_legal_acceptances')
            .select('accepted_at')
            .eq('user_id', userId)
            .eq('terms_version', LegalConfig.termsVersion)
            .eq('privacy_version', LegalConfig.privacyVersion)
            .maybeSingle();
        return {'accepted': row != null};
      },
    );
    return result['accepted'] == true;
  }

  @override
  Future<void> accept() async {
    // Another tab may already have saved this version; avoid changing its timestamp.
    try {
      await client.from('breeder_legal_acceptances').insert({
        'user_id': userId,
        'terms_version': LegalConfig.termsVersion,
        'privacy_version': LegalConfig.privacyVersion,
      });
    } on PostgrestException catch (error) {
      if (error.code != '23505' || !await hasAccepted()) rethrow;
    }
    await OfflineRuntime.engine?.cache(
      'legal:${LegalConfig.termsVersion}:${LegalConfig.privacyVersion}',
      {'accepted': true},
    );
  }

  @override
  Future<void> signOut() => client.auth.signOut();
}
