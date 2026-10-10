import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/legal_config.dart';

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
    final row = await client
        .from('breeder_legal_acceptances')
        .select('accepted_at')
        .eq('user_id', userId)
        .eq('terms_version', LegalConfig.termsVersion)
        .eq('privacy_version', LegalConfig.privacyVersion)
        .maybeSingle();
    return row != null;
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
  }

  @override
  Future<void> signOut() => client.auth.signOut();
}
