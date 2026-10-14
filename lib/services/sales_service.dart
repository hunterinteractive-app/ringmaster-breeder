import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/sale_record.dart';

class SalesService {
  static SupabaseClient get client => Supabase.instance.client;
  static String newId() {
    final bytes = List.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static Future<List<Map<String, dynamic>>> _all(
    String table,
    String field,
    List<String> ids,
  ) async {
    if (ids.isEmpty) return [];
    final rows = <Map<String, dynamic>>[];
    for (var start = 0; start < ids.length; start += 100) {
      final batch = ids.sublist(start, min(start + 100, ids.length));
      for (var offset = 0; ; offset += 500) {
        final page = List<Map<String, dynamic>>.from(
          await client
              .from(table)
              .select()
              .inFilter(field, batch)
              .order('id')
              .range(offset, offset + 499),
        );
        rows.addAll(page);
        if (page.length < 500) break;
      }
    }
    return rows;
  }

  static Future<List<SaleRecord>> list(String owner, {String? ringId}) async {
    final farms = List<Map<String, dynamic>>.from(
      await client.from('farms').select('id').eq('owner_id', owner),
    );
    final ids = farms
        .map((f) => f['id'] as String)
        .where((id) => ringId == null || id == ringId)
        .toList();
    final rows = await _all('animal_sales', 'ring_id', ids);
    final payments = await _all(
      'animal_sale_payments',
      'sale_id',
      rows.map((r) => r['id'] as String).toList(),
    );
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final p in payments) {
      grouped.putIfAbsent(p['sale_id'], () => []).add(p);
    }
    rows.sort(
      (a, b) =>
          (b['created_at'] as String).compareTo(a['created_at'] as String),
    );
    return rows.map((r) => SaleRecord(r, grouped[r['id']] ?? [])).toList();
  }

  static Future<Map<String, String>> tags(String ringId) async {
    final rows = await _all('animal_sales', 'ring_id', [ringId]);
    return {
      for (final row in rows)
        if (['for_sale', 'reserved'].contains(row['status']))
          row['animal_id'] as String: row['status'] as String,
    };
  }

  static Future<void> listAnimals(
    List<Map<String, dynamic>> animals,
    int? asking,
  ) async {
    if (animals.isEmpty || animals.length > 500) {
      throw StateError('Select between 1 and 500 animals.');
    }
    await client
        .from('animal_sales')
        .insert(
          animals
              .map(
                (a) => {
                  'animal_id': a['id'],
                  'ring_id': a['ring_id'],
                  'animal_name': '',
                  'asking_cents': asking,
                },
              )
              .toList(),
        );
  }

  static Future<void> update(
    SaleRecord sale,
    Map<String, dynamic> changes,
  ) async {
    final rows = await client
        .from('animal_sales')
        .update(changes)
        .eq('id', sale.id)
        .eq('version', sale.data['version'])
        .select('id');
    if (rows.isEmpty) {
      throw StateError('This sale changed. Close and refresh before editing.');
    }
  }

  static Future<void> payment(
    String id,
    String saleId,
    Map<String, dynamic> payment,
  ) async {
    // Reusing this ID after an uncertain response cannot create a second receipt.
    try {
      await client.from('animal_sale_payments').insert({
        'id': id,
        'sale_id': saleId,
        ...payment,
      });
    } on PostgrestException catch (e) {
      if (e.code != '23505') rethrow;
      final saved = await client
          .from('animal_sale_payments')
          .select()
          .eq('id', id)
          .single();
      if (saved['sale_id'] != saleId ||
          payment.entries.any((e) => saved[e.key] != e.value)) {
        rethrow;
      }
    }
  }

  static Future<List<Map<String, dynamic>>> history(String saleId) =>
      _all('animal_sale_history', 'sale_id', [saleId]);
}
