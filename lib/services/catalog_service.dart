import 'package:supabase_flutter/supabase_flutter.dart';

class CatalogService {
  static DateTime? _synced;
  static Future<void>? _pending;
  static List<Map<String, dynamic>>? _catalog;
  static DateTime? _loaded;
  static Future<List<Map<String, dynamic>>>? _loading;
  static Future<void> refresh() async {
    if (_synced != null &&
        DateTime.now().difference(_synced!) < const Duration(minutes: 5)) {
      return;
    }
    if (_pending != null) return _pending;
    _pending = () async {
      try {
        await Supabase.instance.client.functions.invoke('sync-breed-catalog');
        _synced = DateTime.now();
        _catalog = null;
      } catch (_) {
        /* Retain the saved catalog during outages. */
      }
    }();
    try {
      await _pending;
    } finally {
      _pending = null;
    }
  }

  static String normalize(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  static Future<List<Map<String, dynamic>>> options(
    String species,
    String? breed,
  ) async {
    await refresh();
    if (_catalog == null ||
        _loaded == null ||
        DateTime.now().difference(_loaded!) > const Duration(seconds: 5)) {
      _loading ??= () async {
        final rows = List<Map<String, dynamic>>.from(
          await Supabase.instance.client
              .from('breeds')
              .select(
                'name,species,is_recognized,varieties(name,is_recognized)',
              )
              .order('name'),
        );
        _catalog = rows;
        _loaded = DateTime.now();
        return rows;
      }();
      try {
        await _loading;
      } finally {
        _loading = null;
      }
    }
    final breeds = _catalog!.where(
      (b) => b['species'] == species.toLowerCase(),
    );
    if (breed == null) return breeds.toList();
    final matches = breeds.where(
      (b) => normalize(b['name']) == normalize(breed),
    );
    if (matches.isEmpty) return [];
    final varieties = List<Map<String, dynamic>>.from(
      matches.first['varieties'],
    );
    varieties.sort(
      (a, b) => a['name'].toString().compareTo(b['name'].toString()),
    );
    return varieties;
  }

  static int distance(String a, String b) {
    a = normalize(a);
    b = normalize(b);
    var row = List.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final next = [i];
      for (var j = 1; j <= b.length; j++) {
        final values = [
          next[j - 1] + 1,
          row[j] + 1,
          row[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
        ]..sort();
        next.add(values.first);
      }
      row = next;
    }
    return row.last;
  }
}
