import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_breeder/services/animal_service.dart';

void main() {
  for (final conflict in [false, true]) {
    test(
      'Genotype update uses only its row and expected revision; conflict=$conflict',
      () async {
        final changes = {
          'genotype': {'notation': 'aa bb C-', 'basis': 'breeder_entered'},
        };
        var calls = 0;
        final db = SupabaseClient(
          'https://genotype-save.invalid',
          'fixture',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
            calls++;
            expect(request.method, 'PATCH');
            expect(request.url.path, '/rest/v1/animals');
            expect(request.url.queryParameters['id'], 'eq.animal-id');
            expect(request.url.queryParameters['revision'], 'eq.7');
            expect(jsonDecode(request.body), changes);
            return http.Response(
              conflict ? '[]' : '[{"id":"animal-id"}]',
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        );
        final save = AnimalService.update(
          'animal-id',
          changes,
          expectedRevision: 7,
          client: db,
        );
        if (conflict) {
          await expectLater(save, throwsA(isA<AnimalEditConflict>()));
        } else {
          await save;
        }
        expect(calls, 1);
        await db.dispose();
      },
    );
  }
}
