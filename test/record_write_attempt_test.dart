import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_breeder/services/record_write_attempt.dart';
import 'package:ringmaster_breeder/services/animal_service.dart';

void main() {
  test(
    'committed save with lost acknowledgement is confirmed on retry; changed payload is rejected',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final stored = <String, Map<String, dynamic>>{};
      var writes = 0;
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.method == 'GET') {
          request.response.write(jsonEncode(stored.values.toList()));
        } else {
          writes++;
          final rows =
              jsonDecode(await utf8.decoder.bind(request).join()) as List;
          for (final row in rows) {
            stored[row['id']] = Map<String, dynamic>.from(row);
          }
          // The server committed, but the client receives a transport-like failure.
          request.response.statusCode = 503;
          request.response.write('{"message":"response lost"}');
        }
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'fixture',
      );
      try {
        final attempt = RecordWriteAttempt('animal_weights', [
          {
            'animal_id': 'a',
            'weight': 4.5,
            'recorded_at': '2026-10-16T12:00:00.000Z',
          },
        ]);
        await expectLater(
          attempt.save(client: client),
          throwsA(isA<PostgrestException>()),
        );
        expect(stored.length, 1);
        stored.values.single['recorded_at'] = '2026-10-16T12:00:00+00:00';
        await attempt.save(client: client);
        expect(writes, 1);
        final changed = RecordWriteAttempt('animal_weights', [
          {...attempt.rows.single, 'weight': 5.0},
        ]);
        await expectLater(changed.save(client: client), throwsStateError);
        expect(stored.values.single['weight'], 4.5);
      } finally {
        await client.dispose();
        await server.close(force: true);
      }
    },
  );
  test(
    'animal update uses the loaded revision and reports a conflict on zero updated rows',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      Uri? uri;
      server.listen((request) async {
        uri = request.uri;
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write('[]');
        await request.response.close();
      });
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'fixture',
      );
      try {
        await expectLater(
          AnimalService.update(
            'animal',
            {'name': 'Draft'},
            expectedRevision: 7,
            client: client,
          ),
          throwsA(isA<AnimalEditConflict>()),
        );
        expect(uri!.queryParameters['revision'], 'eq.7');
        expect(uri!.queryParameters['id'], 'eq.animal');
      } finally {
        await client.dispose();
        await server.close(force: true);
      }
    },
  );
}
