import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_breeder/services/record_import_service.dart';

void main() {
  for (final onboarding in [false, true]) {
    test(
      'Onboarding $onboarding preserves the correct offline request path',
      () async {
        final requests = <http.Request>[];
        final client = SupabaseClient(
          'https://example.supabase.co',
          'test-key',
          accessToken: () async => 'test-token',
          httpClient: MockClient((request) async {
            requests.add(request);
            final body = jsonDecode(request.body) as Map;
            return http.Response(
              jsonEncode(
                body['action'] == 'lookup'
                    ? {'status': 'matches', 'matches': []}
                    : {'status': 'imported', 'profiles_selected': 1},
              ),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        final gateway = RecordImportService(
          client,
          requireServerConfirmation: onboarding,
        );
        await gateway.lookup();
        final result = await gateway.importRecords({
          'source': 'show',
          'profile_ids': ['profile'],
          'include_animals': false,
          'include_entries': true,
        });
        expect(result['status'], 'imported');
        expect(requests.length, 2);
        for (final request in requests) {
          expect(
            request.url.queryParameters['__breeder_network'],
            onboarding ? '1' : isNull,
          );
          expect(request.headers['Authorization'], 'Bearer test-token');
        }
        await client.dispose();
      },
    );
  }
}
