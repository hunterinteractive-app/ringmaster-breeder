import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'offline_store.dart';

class SyncFailure implements Exception {
  final String message;
  final bool retryable;
  final JsonMap? server;
  const SyncFailure(this.message, {this.retryable = false, this.server});
  @override
  String toString() => message;
}

abstract interface class SyncRemote {
  Future<JsonMap> animal(String id);
  Future<JsonMap?> updateAnimal(String id, JsonMap changes, int revision);
  Future<void> insertWeight(JsonMap row);
}

abstract interface class RequestSyncRemote {
  Future<void> applyRequest(JsonMap operation);
}

class SyncEngine extends ChangeNotifier {
  final OfflineStore store;
  final SyncRemote remote;
  final String accountId;
  final DateTime Function() now;
  SyncEngine({
    required this.store,
    required this.remote,
    required this.accountId,
    DateTime Function()? clock,
  }) : now = clock ?? DateTime.now;

  String get prefix => 'v1:${Uri.encodeComponent(accountId)}:';
  String key(String suffix) => '$prefix$suffix';
  List<JsonMap> operations = [];
  bool syncing = false;
  int completed = 0;
  String? error;
  DateTime? lastSynced;
  Future<void>? _syncing;
  int get pending => operations.length;
  int get attention => operations.where((o) => o['state'] != 'pending').length;
  String get status => syncing
      ? 'Syncing'
      : attention > 0
      ? 'Needs your attention'
      : error != null
      ? 'Waiting to sync'
      : pending > 0
      ? 'Saved on this device'
      : 'No pending changes';

  Future<void> refresh() async {
    operations =
        (await store.scan(
          key('op:'),
        )).values.map((d) => d.value).toList()..sort(
          (a, b) =>
              (a['created_at'] as String).compareTo(b['created_at'] as String),
        );
    final byId = {for (final op in operations) op['id']: op};
    final ordered = <JsonMap>[];
    final visited = <String>{}, visiting = <String>{};
    void visit(JsonMap op) {
      final id = op['id'] as String;
      if (visited.contains(id)) return;
      if (!visiting.add(id)) {
        throw const SyncFailure(
          'The recovery queue contains a dependency cycle.',
        );
      }
      for (final id in [op['depends_on'], ...?(op['requires'] as List?)]) {
        final parent = byId[id];
        if (parent != null) visit(parent);
      }
      visiting.remove(id);
      visited.add(id);
      ordered.add(op);
    }

    for (final op in operations) {
      visit(op);
    }
    operations = ordered;
    final meta = await store.read(key('sync'));
    lastSynced = DateTime.tryParse(meta?.value['at'] ?? '');
    notifyListeners();
  }

  Future<void> verifyAccess() async {
    await store.commit(
      puts: {
        key('access'): {'verified_at': now().toUtc().toIso8601String()},
      },
    );
  }

  Future<void> requireAccess() async {
    final access = await store.read(key('access'));
    final verified = DateTime.tryParse(access?.value['verified_at'] ?? '');
    final age = verified == null ? null : now().toUtc().difference(verified);
    if (age == null || age.isNegative || age >= const Duration(days: 7)) {
      throw const SyncFailure(
        'Reconnect to verify access before making more offline changes. Your saved work is retained.',
      );
    }
  }

  Future<void> cache(String name, JsonMap value) =>
      store.commit(puts: {key('cache:$name'): value}).then((_) {});
  Future<JsonMap?> cached(String name) async =>
      (await store.read(key('cache:$name')))?.value;

  Future<JsonMap?> animal(String id) async {
    final base = await cached('animal:$id');
    if (base == null) return null;
    final projected = copyJson(base);
    for (final op in operations) {
      if (op['kind'] == 'animal' && op['animal_id'] == id) {
        projected.addAll(Map<String, dynamic>.from(op['changes'] as Map));
      }
    }
    return projected;
  }

  /// Save the draft and outbox entry in one committed transaction. Immutable
  /// operation IDs also make retries after a lost acknowledgement safe.
  Future<void> enqueue(JsonMap operation) async {
    await requireAccess();
    final op = copyJson(operation);
    validateOperation(op);
    final opKey = key('op:${op['id']}');
    final existing = await store.read(opKey);
    if (existing != null) {
      for (final field in [
        'kind',
        'animal_id',
        'changes',
        'base',
        'row',
        'request',
        'mutations',
        'expects',
        'requires',
        'result',
        'seed',
      ]) {
        if (!_same(existing.value[field], op[field])) {
          throw const SyncFailure(
            'This saved operation has different data. Keep the original draft and review Sync activity.',
          );
        }
      }
      await refresh();
      return;
    }
    op['state'] = 'pending';
    op['created_at'] = now().toUtc().toIso8601String();
    final headKey = key('head:${op['animal_id']}');
    final head = await store.read(headKey);
    if (head != null) op['depends_on'] = head.value['id'];
    if (!await _commitQueue(
      expected: {opKey: null, headKey: head?.version},
      puts: {
        opKey: op,
        headKey: {'id': op['id']},
      },
    )) {
      return enqueue(operation);
    }
    await refresh();
  }

  static bool _same(dynamic a, dynamic b) =>
      const DeepCollectionEquality().equals(a, b);

  static Iterable<String> _assetRefs(JsonMap operation) sync* {
    final request = operation['request'];
    if (request is! Map) return;
    final body = request['body'];
    for (final value in [
      request['asset_ref'],
      if (body is Map) body['pdf_asset_ref'],
    ]) {
      if (value == null) continue;
      if (value is! String ||
          !RegExp(r'^cache:pending-file:[a-fA-F0-9-]{36}$').hasMatch(value)) {
        throw const SyncFailure('Invalid recovery attachment reference.');
      }
      yield value;
    }
  }

  // Related identity/status fields are reviewed together. An unrelated name
  // change can still merge with a registration-number change.
  static const related = {
    'species',
    'breed',
    'variety',
    'color_details',
    'sex',
    'dob',
    'status',
    'sire_id',
    'dam_id',
  };

  static void validateOperation(JsonMap op) {
    bool identifier(dynamic value) =>
        value is String && value.isNotEmpty && value.length <= 200;
    const animalFields = {
      ...related,
      'name',
      'tattoo',
      'registration_number',
      'grand_champion_number',
      'leg_details',
    };
    if (!identifier(op['id']) ||
        !identifier(op['animal_id']) ||
        !['animal', 'weight', 'request'].contains(op['kind'])) {
      throw const SyncFailure(
        'Invalid recovery operation. No saved work was changed.',
      );
    }
    if (op['kind'] == 'request') {
      final request = op['request'];
      if (request is! Map ||
          ![
            'table',
            'rpc',
            'file',
            'file_delete',
            'external',
          ].contains(request['type']) ||
          op['mutations'] is! List ||
          (op['mutations'] as List).any(
            (m) =>
                m is! Map ||
                m['table'] is! String ||
                !['insert', 'update', 'delete'].contains(m['action']) ||
                m['row'] is! Map,
          ) ||
          op['expects'] is! List ||
          (op['expects'] as List).any(
            (e) =>
                e is! Map ||
                e['table'] is! String ||
                e['key'] is! Map ||
                e['before'] is! Map,
          ) ||
          op['requires'] is! List ||
          (op['requires'] as List).any((id) => !identifier(id))) {
        throw const SyncFailure('Invalid saved record operation.');
      }
      // The shared browser implementation additionally validates each table,
      // RPC, field, file and service before either enqueueing or transmitting.
    } else if (op['kind'] == 'animal') {
      if (op['base'] is! Map ||
          op['changes'] is! Map ||
          (op['changes'] as Map).isEmpty ||
          !(op['changes'] as Map).keys.every(animalFields.contains)) {
        throw const SyncFailure('Invalid animal changes in the recovery file.');
      }
    } else {
      final row = op['row'];
      if (row is! Map ||
          !identifier(row['id']) ||
          row['animal_id'] != op['animal_id'] ||
          row['weight'] is! num ||
          !(row['weight'] as num).isFinite ||
          row['weight'] <= 0 ||
          row['recorded_at'] is! String ||
          DateTime.tryParse(row['recorded_at']) == null ||
          !row.keys.every(
            {'id', 'animal_id', 'weight', 'recorded_at'}.contains,
          )) {
        throw const SyncFailure('Invalid weight in the recovery file.');
      }
    }
  }

  Future<bool> _commitQueue({
    Map<String, int?> expected = const {},
    Map<String, JsonMap> puts = const {},
    List<String> deletes = const [],
  }) async {
    final epochKey = key('queue-version');
    final epoch = await store.read(epochKey);
    return store.commit(
      expected: {epochKey: epoch?.version, ...expected},
      puts: {...puts, epochKey: {}},
      deletes: deletes,
    );
  }

  Future<JsonMap> _applyAnimal(JsonMap op) async {
    final changes = Map<String, dynamic>.from(op['changes'] as Map);
    final base = Map<String, dynamic>.from(op['base'] as Map);
    for (var retry = 0; retry < 3; retry++) {
      final latest = await remote.animal(op['animal_id']);
      if (changes.entries.every((e) => _same(latest[e.key], e.value))) {
        return latest;
      }
      final checked = {
        ...changes.keys,
        if (changes.keys.any(related.contains)) ...related,
      };
      final conflicts = checked
          .where(
            (field) =>
                !_same(latest[field], base[field]) &&
                !(changes.containsKey(field) &&
                    _same(latest[field], changes[field])),
          )
          .toList();
      if (conflicts.isNotEmpty) {
        throw SyncFailure(
          'This animal changed on another device. Review the conflicting fields.',
          server: latest,
        );
      }
      final updated = await remote.updateAnimal(
        op['animal_id'],
        changes,
        (latest['revision'] as num).toInt(),
      );
      if (updated != null) return updated;
    }
    throw const SyncFailure(
      'This animal is changing on another device. Will retry.',
      retryable: true,
    );
  }

  Future<void> sync() =>
      _syncing ??= _run().whenComplete(() => _syncing = null);
  Future<void> _run() async {
    syncing = true;
    completed = 0;
    error = null;
    notifyListeners();
    try {
      await refresh();
      final blocked = <String>{};
      for (final queued in List<JsonMap>.from(operations)) {
        final animalId = queued['animal_id'] as String;
        if (queued['state'] != 'pending' || blocked.contains(animalId)) {
          blocked.add(animalId);
          continue;
        }
        final opKey = key('op:${queued['id']}');
        final document = await store.read(opKey);
        if (document == null || document.value['state'] != 'pending') continue;
        final op = document.value;
        var waiting = false;
        for (final id in [op['depends_on'], ...?(op['requires'] as List?)]) {
          if (id != null && await store.read(key('op:$id')) != null) {
            waiting = true;
          }
        }
        if (waiting) {
          blocked.add(animalId);
          continue;
        }
        try {
          JsonMap? updated;
          if (op['kind'] == 'request') {
            if (remote is! RequestSyncRemote) {
              throw const SyncFailure(
                'This app version cannot sync this saved action. Export it before updating.',
              );
            }
            await (remote as RequestSyncRemote).applyRequest(op);
            if (await store.read(opKey) == null) completed++;
            continue;
          } else if (op['kind'] == 'animal') {
            updated = await _applyAnimal(op);
          } else if (op['kind'] == 'weight') {
            await remote.insertWeight(
              Map<String, dynamic>.from(op['row'] as Map),
            );
          } else {
            throw const SyncFailure(
              'Unsupported queued operation. Export it for recovery.',
            );
          }
          final saved = await _commitQueue(
            expected: {opKey: document.version},
            puts: {
              if (updated != null) key('cache:animal:$animalId'): updated,
              if (op['kind'] == 'weight')
                key('cache:weight:${op['row']['id']}'):
                    Map<String, dynamic>.from(op['row'] as Map),
            },
            deletes: [opKey],
          );
          if (saved) completed++;
        } on SyncFailure catch (failure) {
          if (failure.retryable) {
            error = failure.message;
            break;
          }
          await _commitQueue(
            expected: {opKey: document.version},
            puts: {
              opKey: {
                ...op,
                'state': failure.server == null ? 'rejected' : 'conflict',
                'message': failure.message,
                if (failure.server != null) 'server': failure.server,
              },
            },
          );
          blocked.add(animalId);
        }
      }
      await refresh();
      if (pending == 0 && error == null) {
        await store.commit(
          puts: {
            key('sync'): {'at': now().toUtc().toIso8601String()},
          },
        );
      }
    } catch (_) {
      error =
          'Unable to finish syncing. Your saved changes remain on this device.';
    } finally {
      syncing = false;
      try {
        await refresh();
      } catch (_) {
        error =
            'Unable to read device storage. Reconnect and keep this browser data for recovery.';
        notifyListeners();
      }
    }
  }

  /// Resolve against the server version the user actually reviewed. Another
  /// server edit is detected normally on the next synchronization attempt.
  Future<void> resolve(String id, {required bool keepMine}) async {
    final opKey = key('op:$id');
    final doc = await store.read(opKey);
    if (doc == null || doc.value['state'] != 'conflict') return;
    final op = doc.value;
    final server = Map<String, dynamic>.from(op['server'] as Map);
    if (!await _commitQueue(
      expected: {opKey: doc.version},
      puts: {
        key('cache:animal:${op['animal_id']}'): server,
        if (keepMine)
          opKey: {
            ...op,
            'base': server,
            'state': 'pending',
            'message': null,
            'server': null,
          },
      },
      deletes: keepMine ? [] : [opKey],
    )) {
      throw const SyncFailure(
        'This conflict changed in another tab. Review it again.',
      );
    }
    await refresh();
  }

  Future<String> exportRecovery() async {
    final version = await store.read(key('queue-version'));
    // Recovery carries unsynced work, its own immutable binaries, and the
    // baselines used by older pilot operations. Avoid exporting every optional
    // downloaded file in a large herd or copying background execution leases.
    final documents = {
      ...await store.scan(key('op:')),
      ...await store.scan(key('head:')),
    };
    for (final operation in documents.values.toList()) {
      final animalId = operation.value['animal_id'];
      if (animalId is String) {
        final cached = await store.read(key('cache:animal:$animalId'));
        if (cached != null) documents[key('cache:animal:$animalId')] = cached;
      }
      for (final reference in _assetRefs(operation.value)) {
        final file = await store.read(key(reference));
        if (file == null) {
          throw const SyncFailure(
            'A pending attachment is missing. Keep this browser data and reconnect before signing out.',
          );
        }
        documents[key(reference)] = file;
      }
    }
    final after = await store.read(key('queue-version'));
    if (version?.version != after?.version) {
      throw const SyncFailure(
        'Saved work changed while preparing the export. Try again.',
      );
    }
    return jsonEncode({
      'format': 'ringmaster-breeder-offline',
      'version': 1,
      'account_id': accountId,
      'exported_at': now().toUtc().toIso8601String(),
      'queue_version': version?.version,
      'documents': {
        for (final e in documents.entries)
          e.key.substring(prefix.length): e.value.value,
      },
    });
  }

  Future<bool> releaseExportedOperations(String encoded) async {
    if (syncing) return false;
    final export = jsonDecode(encoded) as Map;
    if (export['account_id'] != accountId) return false;
    final exported = Map<String, dynamic>.from(export['documents'] as Map);
    final documents = await store.scan(key('op:'));
    final expected = <String, int?>{};
    for (final e in documents.entries) {
      if (!_same(e.value.value, exported[e.key.substring(prefix.length)])) {
        return false;
      }
      expected[e.key] = e.value.version;
    }
    final assets = documents.values
        .expand((d) => _assetRefs(d.value))
        .map(key)
        .toSet();
    final result = await _commitQueue(
      expected: {
        ...expected,
        key('queue-version'): export['queue_version'] as int?,
      },
      deletes: [...documents.keys, ...assets],
    );
    await refresh();
    return result;
  }

  Future<void> restoreRecovery(String encoded) async {
    final data = jsonDecode(encoded) as Map;
    if (data['format'] != 'ringmaster-breeder-offline' ||
        data['version'] != 1 ||
        data['account_id'] != accountId) {
      throw const SyncFailure(
        'Choose a Breeder recovery file for this signed-in account.',
      );
    }
    final docs = Map<String, dynamic>.from(data['documents'] as Map);
    final expected = <String, int?>{};
    final puts = <String, JsonMap>{};
    for (final e in docs.entries) {
      // Restoring a file must never renew account access or overwrite current drafts.
      if (!e.key.startsWith('op:') &&
          !e.key.startsWith('cache:animal:') &&
          !e.key.startsWith('cache:pending-file:') &&
          !e.key.startsWith('head:')) {
        continue;
      }
      if (e.key.startsWith('head:') &&
          (e.value is! Map || e.value['id'] is! String)) {
        throw const SyncFailure('Invalid recovery dependency marker.');
      }
      if (e.key.startsWith('op:')) {
        final op = Map<String, dynamic>.from(e.value as Map);
        validateOperation(op);
        if (e.key != 'op:${op['id']}' ||
            !['pending', 'conflict', 'rejected'].contains(op['state']) ||
            DateTime.tryParse(op['created_at'] ?? '') == null ||
            (op['state'] == 'conflict' && op['server'] is! Map)) {
          throw const SyncFailure(
            'Invalid recovery queue. No saved work was changed.',
          );
        }
      }
      final documentKey = key(e.key);
      final existing = await store.read(documentKey);
      if (existing != null) {
        if (e.key.startsWith('op:') && !_same(existing.value, e.value)) {
          throw const SyncFailure(
            'A pending operation differs from the recovery file. No records were restored.',
          );
        }
        if (e.key.startsWith('cache:pending-file:') &&
            !_same(existing.value, e.value)) {
          throw const SyncFailure(
            'A saved attachment differs from the recovery file. No pending work was overwritten.',
          );
        }
        continue;
      }
      expected[documentKey] = null;
      puts[documentKey] = Map<String, dynamic>.from(e.value as Map);
    }
    // Reject cyclic dependencies before committing anything.
    final incoming = {
      for (final e in puts.entries)
        if (e.key.startsWith(key('op:'))) e.value['id']: e.value,
    };
    final existingOperations = (await store.scan(
      key('op:'),
    )).values.map((d) => d.value);
    final graph = {
      for (final op in existingOperations) op['id']: op,
      ...incoming,
    };
    for (final op in incoming.values) {
      for (final reference in _assetRefs(op)) {
        final value =
            puts[key(reference)] ?? (await store.read(key(reference)))?.value;
        if (value == null ||
            value['base64'] is! String ||
            value['sha256'] is! String) {
          throw const SyncFailure(
            'This recovery file is missing an attachment. No pending work was restored.',
          );
        }
      }
    }
    final visited = <dynamic>{}, visiting = <dynamic>{};
    void visit(JsonMap op) {
      if (visited.contains(op['id'])) return;
      if (!visiting.add(op['id'])) {
        throw const SyncFailure('Invalid recovery dependency cycle.');
      }
      for (final id in [op['depends_on'], ...?(op['requires'] as List?)]) {
        final parent = graph[id];
        if (parent != null) visit(parent);
      }
      visiting.remove(op['id']);
      visited.add(op['id']);
    }

    for (final op in incoming.values) {
      visit(op);
    }
    if (!await _commitQueue(expected: expected, puts: puts)) {
      throw const SyncFailure(
        'Another tab changed the saved work. Retry the recovery import.',
      );
    }
    await refresh();
  }
}

// Kept local to avoid comparing map insertion order in conflict checks.
class DeepCollectionEquality {
  const DeepCollectionEquality();
  bool equals(dynamic a, dynamic b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && equals(a[k], b[k]));
    }
    if (a is List && b is List) {
      return a.length == b.length &&
          List.generate(a.length, (i) => i).every((i) => equals(a[i], b[i]));
    }
    return a == b;
  }
}
