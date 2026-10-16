import 'package:supabase_flutter/supabase_flutter.dart';
import 'sales_service.dart';

/// One immutable save, retained until its outcome is known. A retry confirms
/// existing IDs before writing, so a lost acknowledgement cannot duplicate it.
class RecordWriteAttempt {
  final String table;
  final List<Map<String, dynamic>> rows;
  RecordWriteAttempt(this.table, List<Map<String, dynamic>> values)
    : rows = List.unmodifiable(
        values.map(
          (row) => Map<String, dynamic>.unmodifiable({
            ...row,
            'id': row['id'] ?? SalesService.newId(),
          }),
        ),
      ) {
    if (!['animal_weights', 'animal_health_records'].contains(table)) {
      throw ArgumentError('Unsupported record table');
    }
  }

  static bool _same(dynamic actual, dynamic expected, String field) {
    if (actual is num && expected is num) return actual == expected;
    if (actual is String && expected is String && field == 'recorded_at') {
      return DateTime.parse(actual).isAtSameMomentAs(DateTime.parse(expected));
    }
    return actual == expected;
  }

  Future<List<Map<String, dynamic>>> _missing(SupabaseClient db) async {
    final missing = <Map<String, dynamic>>[];
    for (var offset = 0; offset < rows.length; offset += 100) {
      final batch = rows.skip(offset).take(100).toList();
      final found = await db
          .from(table)
          .select()
          .inFilter('id', batch.map((r) => r['id']).toList());
      final saved = {for (final row in found) row['id']: row};
      for (final row in batch) {
        final existing = saved[row['id']];
        if (existing == null) {
          missing.add(row);
        } else if (row.entries.any(
          (e) => !_same(existing[e.key], e.value, e.key),
        )) {
          throw StateError(
            'A saved record differs from this attempt. Refresh before making another entry.',
          );
        }
      }
    }
    return missing;
  }

  Future<void> save({SupabaseClient? client}) async {
    final db = client ?? Supabase.instance.client;
    final missing = await _missing(db);
    if (missing.isEmpty) return;
    try {
      await db.from(table).insert(missing);
    } on PostgrestException catch (error) {
      // Two retries can race after both observe missing IDs. Confirm that the
      // other transaction saved this exact payload; never overwrite a record.
      if (error.code != '23505' || (await _missing(db)).isNotEmpty) rethrow;
    }
  }
}
