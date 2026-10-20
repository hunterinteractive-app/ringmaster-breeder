import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_breeder/services/global_pedigree_import_service.dart';

void main() {
  test(
    'client accumulates batches and sends credentials only on the first request',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <Map<String, dynamic>>[];
      server.listen((request) async {
        requests.add(
          Map<String, dynamic>.from(
            jsonDecode(await utf8.decoder.bind(request).join()) as Map,
          ),
        );
        final first = requests.length == 1;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'status': first ? 'collecting' : 'collected',
            'account': 'fixture',
            'animals': first
                ? []
                : [
                    {
                      'source_id': '1',
                      'name': 'Collected Rabbit',
                      'known_genotype': 'aa bb C_ dd E_',
                    },
                  ],
            'history': first
                ? []
                : [
                    {
                      'kind': 'weight',
                      'source_id': '1:123',
                      'animal_source_id': '1',
                      'weight': 4.5,
                      'recorded_date': '2025-05-15',
                    },
                  ],
            'history_complete': !first,
            'token': first ? 'encrypted-session' : null,
          }),
        );
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-key',
      );
      try {
        final result = await GlobalPedigreeImportService(
          client,
        ).collect('fixture', 'temporary');
        expect((result['animals'] as List).length, 1);
        expect(
          (result['animals'] as List).single['known_genotype'],
          'aa bb C_ dd E_',
        );
        expect(
          (result['history'] as List).single['recorded_date'],
          '2025-05-15',
        );
        expect(result['history_complete'], isTrue);
        expect(requests, [
          {'username': 'fixture', 'password': 'temporary'},
          {'token': 'encrypted-session'},
        ]);
      } finally {
        await client.dispose();
        await server.close(force: true);
      }
    },
  );
}
