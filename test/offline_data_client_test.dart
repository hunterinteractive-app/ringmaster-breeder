import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_breeder/offline/offline_data_client.dart';

String token(int expires) =>
    '${base64Url.encode(utf8.encode('{}')).replaceAll('=', '')}.${base64Url.encode(utf8.encode(jsonEncode({'sub': '11111111-1111-4111-8111-111111111111', 'exp': expires}))).replaceAll('=', '')}.fixture';
void main() {
  test(
    'expired login can read downloaded records without pretending the login was refreshed',
    () async {
      final expired = token(
        DateTime.now().millisecondsSinceEpoch ~/ 1000 - 3600,
      );
      var refreshes = 0;
      String? authorization;
      final transport = MockClient((request) async {
        if (request.url.path.startsWith('/auth/')) {
          refreshes++;
          throw http.ClientException('Offline');
        }
        authorization = request.headers['Authorization'];
        return http.Response(
          '[{"id":"animal"}]',
          200,
          headers: {'Content-Type': 'application/json'}, request:request,
        );
      });
      final session = SupabaseClient(
        'https://fixture.invalid',
        'fixture',
        httpClient: transport,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      // ignore: invalid_use_of_internal_member
      await session.auth.setInitialSession(
        jsonEncode({
          'access_token': expired,
          'refresh_token': 'fixture',
          'token_type': 'bearer',
          'user': {
            'id': '11111111-1111-4111-8111-111111111111',
            'app_metadata': {},
            'user_metadata': {},
            'aud': 'authenticated',
            'created_at': '2026-01-01T00:00:00Z',
          },
        }),
      );
      final local = OfflineDataClient(
        url: 'https://fixture.invalid',
        key: 'fixture',
        sessionClient: session,
        localReady: () => true,
        httpClient: transport,
      );
      expect((await local.from('animals').select()).single['id'], 'animal');
      expect(refreshes, 0);
      expect(authorization, 'Bearer $expired');
      expect(session.auth.currentSession!.isExpired, isTrue);
      expect(identical(local.auth, session.auth), isTrue);
      await local.dispose();
      await session.dispose();
    },
  );
}
