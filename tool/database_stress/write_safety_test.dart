// Explicit local integration test; not part of the portable test/ suite.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_breeder/services/animal_service.dart';
import 'package:ringmaster_breeder/services/record_write_attempt.dart';
import 'package:ringmaster_breeder/services/sales_service.dart';

void main() {
  test(
    'real database prevents duplicate retries, payload changes, and stale animal edits',
    () async {
      const token = String.fromEnvironment('TEST_DATABASE_TOKEN');
      const actor = 'e1000000-0000-4000-8000-000000000001';
      expect(
        token,
        isNotEmpty,
        reason: 'Run through the local database test harness.',
      );
      final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final http = HttpClient();
      proxy.listen((incoming) async {
        final path = incoming.uri.toString().replaceFirst('/rest/v1/', '/');
        final target = Uri.parse('http://127.0.0.1:56433$path');
        final outgoing = await http.openUrl(incoming.method, target);
        incoming.headers.forEach((name, values) {
          if (name.toLowerCase() != 'host') outgoing.headers.set(name, values);
        });
        await outgoing.addStream(incoming);
        final response = await outgoing.close();
        incoming.response.statusCode = response.statusCode;
        response.headers.forEach((name, values) {
          if (name != 'transfer-encoding') {
            incoming.response.headers.set(name, values);
          }
        });
        await response.pipe(incoming.response);
      });
      final db = SupabaseClient(
        'http://127.0.0.1:${proxy.port}',
        'local-fixture',
        headers: {'Authorization': 'Bearer $token'},
      );
      final evidence = <String, dynamic>{'actor': actor};
      try {
        final animal = (await db
            .from('animals')
            .select('id,revision')
            .eq('tattoo', 'SCALE-4')
            .single());
        final id = animal['id'] as String;
        final attempt = RecordWriteAttempt(
          'animal_weights',
          List.generate(
            1001,
            (i) => {
              'animal_id': id,
              'weight': 4.5,
              'recorded_at': '2026-10-16T12:00:00.000Z',
            },
          ),
        );
        await attempt.save(
          client: db,
        ); // Commit happened; its acknowledgement is considered lost.
        await attempt.save(client: db); // Same pending UI save is retried.
        final weights = await AnimalService.weights(id, client: db);
        final ids = attempt.rows.map((r) => r['id']).toSet();
        expect(weights.where((r) => ids.contains(r['id'])).length, 1001);
        expect(
          weights.length,
          1181,
        ); // Existing 180 plus exactly one 1001-record save.
        evidence['bulk_records_after_retry'] = 1001;
        evidence['complete_weight_history'] = weights.length;
        final altered = RecordWriteAttempt('animal_weights', [
          {...attempt.rows.first, 'weight': 9.5},
        ]);
        await expectLater(altered.save(client: db), throwsStateError);
        evidence['changed_retry_payload'] = 'rejected';
        final race = RecordWriteAttempt('animal_weights', [
          {
            'id': SalesService.newId(),
            'animal_id': id,
            'weight': 4.6,
            'recorded_at': '2026-10-16T12:00:01Z',
          },
        ]);
        await Future.wait([race.save(client: db), race.save(client: db)]);
        final raced = await db
            .from('animal_weights')
            .select('id')
            .eq('id', race.rows.single['id']);
        expect(raced.length, 1);
        evidence['concurrent_retry_records'] = raced.length;
        final revision = (animal['revision'] as num).toInt();
        Future<Object?> edit(String name) async {
          try {
            await AnimalService.update(
              id,
              {'name': name},
              expectedRevision: revision,
              client: db,
            );
            return null;
          } catch (e) {
            return e;
          }
        }

        final edits = await Future.wait([
          edit('Verified editor A'),
          edit('Verified editor B'),
        ]);
        expect(edits.whereType<AnimalEditConflict>().length, 1);
        expect(edits.where((e) => e == null).length, 1);
        final updated = await db
            .from('animals')
            .select('revision')
            .eq('id', id)
            .single();
        expect(updated['revision'], revision + 1);
        evidence['animal_edit_successes'] = 1;
        evidence['animal_edit_conflicts'] = 1;
        // The database ignores attempts to forge the revision value itself.
        await db.from('animals').update({'revision': 99999}).eq('id', id);
        final protected = await db
            .from('animals')
            .select('revision')
            .eq('id', id)
            .single();
        expect(protected['revision'], revision + 2);
        evidence['forged_revision'] = 'ignored; server incremented';
        evidence['passed'] = true;
      } finally {
        await db.dispose();
        await proxy.close(force: true);
        http.close(force: true);
        final out = File('deliverables/database-write-fix-results.json');
        await out.parent.create(recursive: true);
        await out.writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(evidence)}\n',
        );
      }
    },
  );
}
