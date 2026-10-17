import 'dart:convert';

typedef JsonMap = Map<String, dynamic>;

class LocalDocument {
  final int version;
  final JsonMap value;
  const LocalDocument(this.version, this.value);
}

/// Every batch is atomic, including its version checks. Implementations must
/// report completion only after the transaction commits to persistent storage.
abstract interface class OfflineStore {
  Future<LocalDocument?> read(String key);
  Future<Map<String, LocalDocument>> scan(String prefix);
  Future<bool> commit({
    Map<String, int?> expected = const {},
    Map<String, JsonMap> puts = const {},
    List<String> deletes = const [],
  });
}

JsonMap copyJson(JsonMap value) =>
    Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

/// Test adapter only. Production must never silently fall back to volatile data.
class MemoryOfflineStore implements OfflineStore {
  final _rows = <String, LocalDocument>{};
  @override
  Future<LocalDocument?> read(String key) async {
    final row = _rows[key];
    return row == null ? null : LocalDocument(row.version, copyJson(row.value));
  }

  @override
  Future<Map<String, LocalDocument>> scan(String prefix) async => {
    for (final entry in _rows.entries)
      if (entry.key.startsWith(prefix))
        entry.key: LocalDocument(
          entry.value.version,
          copyJson(entry.value.value),
        ),
  };

  @override
  Future<bool> commit({
    Map<String, int?> expected = const {},
    Map<String, JsonMap> puts = const {},
    List<String> deletes = const [],
  }) async {
    if (expected.entries.any((e) => _rows[e.key]?.version != e.value)) {
      return false;
    }
    final copies = {for (final e in puts.entries) e.key: copyJson(e.value)};
    for (final e in copies.entries) {
      _rows[e.key] = LocalDocument((_rows[e.key]?.version ?? 0) + 1, e.value);
    }
    for (final key in deletes) {
      _rows.remove(key);
    }
    return true;
  }
}
