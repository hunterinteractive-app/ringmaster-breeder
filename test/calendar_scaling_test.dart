import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_breeder/services/pagination.dart';
import 'package:ringmaster_breeder/services/animal_service.dart';
import 'package:ringmaster_breeder/services/herd_calendar_service.dart';

void main() {
  for (final count in [0, 500, 1501, 300000]) {
    test(
      'pagination retains $count records with smaller server page cap',
      () async {
        final rows = await fetchAllPages(
          (from, to) async => [
            for (
              var i = from;
              i < math.min(count, math.min(to + 1, from + 127));
              i++
            )
              {'id': i},
          ],
        );
        expect(rows.length, count);
        expect(rows.map((r) => r['id']).toSet().length, count);
        if (count > 0) expect(rows.last['id'], count - 1);
      },
    );
  }
  test(
    'pagination propagates a later failure instead of returning partial history',
    () async {
      await expectLater(
        fetchAllPages((a, b) async {
          if (a > 0) throw StateError('Synthetic network failure');
          return [
            {'id': 'first'},
          ];
        }),
        throwsStateError,
      );
    },
  );
  test(
    'calendar query pages date-bounded history and retains old-record follow-ups',
    () async {
      final requests = <Uri>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final base = <String, dynamic>{
        'id': 'b',
        'dam': {'id': 'dam', 'name': 'Doe', 'species': 'rabbit'},
        'status': 'active',
        'breeding_date': '2026-08-01',
      };
      server.listen((req) async {
        requests.add(req.uri);
        final q = req.uri.queryParameters;
        final offset = int.parse(q['offset'] ?? '0');
        final table = req.uri.pathSegments.last;
        List<Map<String, dynamic>> data = [];
        if (table == 'breeding_settings' && offset == 0) {
          data = [
            {'species': 'rabbit', 'gestation_max': 365, 'weaning_max': 8},
          ];
        }
        if (table == 'breeding_records' && offset == 0) {
          data = [base];
        }
        if (table == 'breeding_tracking' && offset == 0) {
          data = [
            {
              'breeding': {
                ...base,
                'id': 'old',
                'breeding_date': '2001-01-01',
                'tracking': {'birth_date': '2026-08-25'},
              },
            },
          ];
        }
        if (table == 'animal_weights') {
          data = [
            for (var i = offset; i < math.min(1501, offset + 500); i++)
              {'id': 'w$i', 'weight': 4.5, 'recorded_at': '2026-10-01'},
          ];
        }
        if (table == 'animal_health_records') {
          data = [
            for (var i = offset; i < math.min(1501, offset + 500); i++)
              {
                'id': 'h$i',
                'animal': {'id': 'dam', 'name': 'Doe'},
                'title': 'Record $i',
                'administered_date': '2001-01-01',
                'readminister_date': '2026-10-10',
              },
          ];
        }
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(data));
        await req.response.close();
      });
      final client = SupabaseClient('http://127.0.0.1:${server.port}', 'test');
      try {
        final window = CalendarWindow.around(DateTime(2026, 10));
        final events = await HerdCalendarService(client).load('herd', window);
        expect(events.where((e) => e.category == 'Health').length, 1501);
        expect(events.every(window.includes), isTrue);
        expect(
          events.any(
            (e) => e.breeding?['id'] == 'old' && e.category == 'Weaning',
          ),
          isTrue,
        );
        expect(events.any((e) => e.title.contains('Record 1500')), isTrue);
        expect(events.any((e) => e.start.year == 2001), isFalse);
        final bred = requests
            .firstWhere((r) => r.pathSegments.last == 'breeding_records')
            .queryParameters;
        expect(bred['dam.ring_id'], 'eq.herd');
        expect(
          requests
              .firstWhere((r) => r.pathSegments.last == 'breeding_records')
              .queryParametersAll['breeding_date'],
          ['gte.2025-09-01', 'lt.2026-12-01'],
        );
        expect(bred['order'], startsWith('id.asc'));
        final health = requests
            .where((r) => r.pathSegments.last == 'animal_health_records')
            .toList();
        expect(health.map((r) => r.queryParameters['offset']), [
          '0',
          '500',
          '1000',
          '1500',
          '1501',
        ]);
        expect(
          health.first.queryParameters['or'],
          contains('readminister_date.gte.2026-09-01'),
        );
        expect(
          health.first.queryParameters['or'],
          contains('expires_date.lt.2026-12-01'),
        );
        final weights = await AnimalService.weights('dam', client: client);
        final records = await AnimalService.healthRecords(
          'dam',
          client: client,
        );
        expect(weights.length, 1501);
        expect(weights.last['id'], 'w1500');
        expect(records.length, 1501);
        final weightRequest = requests
            .firstWhere((r) => r.pathSegments.last == 'animal_weights')
            .queryParameters;
        expect(weightRequest['animal_id'], 'eq.dam');
        expect(weightRequest['order'], contains('id.desc'));
      } finally {
        await client.dispose();
        await server.close(force: true);
      }
    },
  );
}
