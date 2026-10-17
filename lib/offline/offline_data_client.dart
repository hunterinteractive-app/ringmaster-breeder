import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Use the existing authenticated identity for local record requests without
/// making token refresh a prerequisite for reading the worker's private store.
/// Auth itself still belongs to the original client. The server always verifies
/// its JWT, and only a verified server snapshot renews the offline edit lease.
class OfflineDataClient extends SupabaseClient {
  final SupabaseClient sessionClient;
  OfflineDataClient({
    required String url,
    required String key,
    required this.sessionClient,
    required bool Function() localReady,
    http.Client? httpClient,
  }) : super(
         url,
         key,
         httpClient: httpClient,
         accessToken: () async {
           if (!localReady() &&
               sessionClient.auth.currentSession?.isExpired == true) {
             await sessionClient.auth.refreshSession();
           }
           return sessionClient.auth.currentSession?.accessToken;
         },
       );

  @override
  GoTrueClient get auth => sessionClient.auth;
}
