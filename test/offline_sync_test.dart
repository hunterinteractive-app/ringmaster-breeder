import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ringmaster_breeder/offline/offline_store.dart';
import 'package:ringmaster_breeder/offline/sync_engine.dart';

class FakeRemote implements SyncRemote {
  final animals = <String, JsonMap>{};
  final weights = <String, JsonMap>{};
  final order = <String>[];
  bool offline = false, loseWeightReply = false, loseAnimalReply = false;
  int inserts = 0;
  final rejected = <String>{};
  void available(String id) {
    if (offline) throw const SyncFailure('Offline', retryable: true);
    if (rejected.contains(id)) throw const SyncFailure('Access revoked');
  }

  @override
  Future<JsonMap> animal(String id) async {
    available(id);
    return copyJson(animals[id]!);
  }

  @override
  Future<JsonMap?> updateAnimal(
    String id,
    JsonMap changes,
    int revision,
  ) async {
    available(id);
    if (animals[id]!['revision'] != revision) return null;
    order.add('animal:$id');
    animals[id]!.addAll(changes);
    animals[id]!['revision'] = revision + 1;
    if (loseAnimalReply) {
      loseAnimalReply = false;
      throw const SyncFailure('Reply lost', retryable: true);
    }
    return copyJson(animals[id]!);
  }

  @override
  Future<void> insertWeight(JsonMap row) async {
    available(row['animal_id']);
    order.add('weight:${row['id']}');
    if (!weights.containsKey(row['id'])) {
      weights[row['id']] = copyJson(row);
      inserts++;
    }
    if (loseWeightReply) {
      loseWeightReply = false;
      throw const SyncFailure('Reply lost', retryable: true);
    }
  }
}

class FailingStore extends MemoryOfflineStore {
  bool fail = false;
  @override
  Future<bool> commit({
    Map<String, int?> expected = const {},
    Map<String, JsonMap> puts = const {},
    List<String> deletes = const [],
  }) async {
    if (fail) throw StateError('Quota exceeded');
    return super.commit(expected: expected, puts: puts, deletes: deletes);
  }
}

void main() {
  late MemoryOfflineStore store;
  late FakeRemote remote;
  late SyncEngine engine;
  var clock = DateTime.utc(2026, 10, 17);
  JsonMap animal(String id) => {
    'id': id,
    'name': 'Original',
    'revision': 1,
    'status': 'active',
    'sex': 'Doe',
    'species': 'rabbit',
    'registration_number': '',
  };
  JsonMap weight(String id, {String animalId = 'a'}) => {
    'id': 'weight:$id',
    'kind': 'weight',
    'animal_id': animalId,
    'row': {
      'id': id,
      'animal_id': animalId,
      'weight': 4.5,
      'recorded_at': clock.toIso8601String(),
    },
  };
  JsonMap edit(
    String id,
    JsonMap changes, {
    String animalId = 'a',
    JsonMap? base,
  }) => {
    'id': id,
    'kind': 'animal',
    'animal_id': animalId,
    'base': base ?? animal(animalId),
    'changes': changes,
  };
  SyncEngine reopen({String account = 'user'}) => SyncEngine(
    store: store,
    remote: remote,
    accountId: account,
    clock: () => clock,
  );

  setUp(() async {
    clock = DateTime.utc(2026, 10, 17);
    store = MemoryOfflineStore();
    remote = FakeRemote()
      ..animals['a'] = animal('a')
      ..animals['b'] = animal('b');
    engine = reopen();
    await engine.verifyAccess();
    await engine.cache('animal:a', animal('a'));
    await engine.cache('animal:b', animal('b'));
  });

  test(
    'draft and immutable operation survive reopening; sync acknowledges them',
    () async {
      final changes = {'name': 'Willow'};
      await engine.enqueue(edit('edit', changes));
      changes['name'] = 'Mutated after save';
      final restarted = reopen();
      await restarted.refresh();
      expect((await restarted.animal('a'))!['name'], 'Willow');
      await restarted.sync();
      expect(remote.animals['a']!['name'], 'Willow');
      expect(restarted.pending, 0);
      expect(restarted.lastSynced, clock);
    },
  );

  test('quota failure cannot report that a draft was saved', () async {
    final failing = FailingStore();
    final e = SyncEngine(
      store: failing,
      remote: remote,
      accountId: 'user',
      clock: () => clock,
    );
    await e.verifyAccess();
    failing.fail = true;
    await expectLater(e.enqueue(weight('w')), throwsStateError);
    expect(e.pending, 0);
    expect(await failing.scan(e.key('op:')), isEmpty);
  });

  test(
    'weight lost acknowledgement remains queued and retries without duplication',
    () async {
      await engine.enqueue(weight('w'));
      remote.loseWeightReply = true;
      await engine.sync();
      expect(engine.pending, 1);
      expect(remote.weights.length, 1);
      final restarted = reopen();
      await restarted.sync();
      expect(restarted.pending, 0);
      expect(remote.inserts, 1);
    },
  );

  test(
    'animal lost acknowledgement is confirmed without another update',
    () async {
      await engine.enqueue(edit('edit', {'name': 'Willow'}));
      remote.loseAnimalReply = true;
      await engine.sync();
      expect(engine.pending, 1);
      await engine.sync();
      expect(engine.pending, 0);
      expect(remote.order, ['animal:a']);
    },
  );

  test('independent changes merge without replacing the family edit', () async {
    await engine.enqueue(edit('edit', {'name': 'Willow'}));
    remote.animals['a']!.addAll({'registration_number': 'R123', 'revision': 2});
    await engine.sync();
    expect(remote.animals['a']!['name'], 'Willow');
    expect(remote.animals['a']!['registration_number'], 'R123');
    expect(engine.pending, 0);
  });

  test(
    'same-field conflict retains both versions until explicitly resolved',
    () async {
      await engine.enqueue(edit('edit', {'name': 'Willow'}));
      remote.animals['a']!.addAll({'name': 'Willow Jane', 'revision': 2});
      await engine.sync();
      expect(engine.attention, 1);
      expect((await engine.animal('a'))!['name'], 'Willow');
      expect(engine.operations.single['server']['name'], 'Willow Jane');
      await engine.resolve('edit', keepMine: true);
      await engine.sync();
      expect(remote.animals['a']!['name'], 'Willow');
      expect(engine.pending, 0);
    },
  );

  test(
    'choosing server version removes only the reviewed conflicting draft',
    () async {
      await engine.enqueue(edit('edit', {'name': 'Willow'}));
      remote.animals['a']!.addAll({'name': 'Family version', 'revision': 2});
      await engine.sync();
      await engine.resolve('edit', keepMine: false);
      expect((await engine.animal('a'))!['name'], 'Family version');
      expect(engine.pending, 0);
      expect(remote.order, isEmpty);
    },
  );

  test('related identity and status edits do not silently merge', () async {
    await engine.enqueue(edit('edit', {'sex': 'Buck'}));
    remote.animals['a']!.addAll({'status': 'sold', 'revision': 2});
    await engine.sync();
    expect(engine.attention, 1);
    expect(remote.animals['a']!['sex'], 'Doe');
  });

  test(
    'Genotype drafts survive offline storage and conflict with changed color facts',
    () async {
      final genotype = {'notation': 'aa bb C- D-', 'basis': 'inferred'};
      await engine.enqueue(edit('genotype', {'genotype': genotype}));
      expect((await engine.animal('a'))!['genotype'], genotype);
      final restored = reopen();
      await restored.refresh();
      remote.animals['a']!.addAll({'variety': 'Blue', 'revision': 2});
      await restored.sync();
      expect(restored.attention, 1);
      expect(remote.animals['a']!.containsKey('genotype'), isFalse);
      expect((await restored.animal('a'))!['genotype'], genotype);
    },
  );

  test(
    'blocked animal dependencies wait while unrelated animals sync',
    () async {
      await engine.enqueue(edit('edit', {'name': 'Willow'}));
      await engine.enqueue(weight('w'));
      await engine.enqueue(weight('other', animalId: 'b'));
      remote.animals['a']!.addAll({'name': 'Family version', 'revision': 2});
      await engine.sync();
      expect(engine.pending, 2);
      expect(remote.weights.keys, ['other']);
    },
  );

  test(
    'dependencies retain order even with identical timestamps and reversed IDs',
    () async {
      await engine.enqueue(edit('z', {'name': 'First'}));
      await engine.enqueue(
        edit('a', {'name': 'Second'}, base: {...animal('a'), 'name': 'First'}),
      );
      final restarted = reopen();
      await restarted.sync();
      expect(remote.animals['a']!['name'], 'Second');
      expect(restarted.pending, 0);
    },
  );

  test(
    'rejected operation is retained; unrelated operations continue',
    () async {
      await engine.enqueue(weight('w'));
      await engine.enqueue(weight('other', animalId: 'b'));
      remote.rejected.add('a');
      await engine.sync();
      expect(engine.pending, 1);
      expect(engine.operations.single['state'], 'rejected');
      expect(remote.weights.containsKey('other'), isTrue);
    },
  );

  test(
    'connection failure retains all pending work across a restart',
    () async {
      await engine.enqueue(weight('w'));
      remote.offline = true;
      await engine.sync();
      expect(engine.error, 'Offline');
      final restarted = reopen();
      await restarted.refresh();
      expect(restarted.pending, 1);
      remote.offline = false;
      await restarted.sync();
      expect(restarted.pending, 0);
    },
  );

  test(
    'access expires at seven days; expiry does not erase drafts or cached records',
    () async {
      await engine.enqueue(weight('w'));
      clock = clock.add(const Duration(days: 7));
      await expectLater(
        engine.enqueue(weight('later')),
        throwsA(isA<SyncFailure>()),
      );
      expect(engine.pending, 1);
      expect(await engine.animal('a'), isNotNull);
      clock = clock.subtract(const Duration(days: 8));
      await expectLater(engine.requireAccess(), throwsA(isA<SyncFailure>()));
    },
  );

  test(
    'duplicate operation ID confirms identical payload and refuses changed data',
    () async {
      final operation = weight('w');
      await engine.enqueue(operation);
      await reopen().enqueue(operation);
      final altered = copyJson(operation);
      altered['row']['weight'] = 5;
      await expectLater(engine.enqueue(altered), throwsA(isA<SyncFailure>()));
      await engine.refresh();
      expect(engine.pending, 1);
    },
  );

  test('accounts cannot see or restore each other\'s data', () async {
    await engine.enqueue(weight('w'));
    final other = reopen(account: 'other');
    await other.refresh();
    expect(other.pending, 0);
    expect(await other.animal('a'), isNull);
    await expectLater(
      other.restoreRecovery(await engine.exportRecovery()),
      throwsA(isA<SyncFailure>()),
    );
  });

  test(
    'recovery round trip retains operation IDs without renewing access',
    () async {
      await engine.enqueue(weight('w'));
      final recovery = await engine.exportRecovery();
      final restored = SyncEngine(
        store: MemoryOfflineStore(),
        remote: remote,
        accountId: 'user',
        clock: () => clock,
      );
      await restored.restoreRecovery(recovery);
      expect(restored.operations.single['id'], 'weight:w');
      await expectLater(restored.requireAccess(), throwsA(isA<SyncFailure>()));
      await restored.restoreRecovery(recovery);
      expect(restored.pending, 1);
      await restored.sync();
      expect(restored.pending, 0);
      expect(remote.inserts, 1);
    },
  );

  test('changed recovery payload never overwrites an existing draft', () async {
    await engine.enqueue(weight('w'));
    final data = jsonDecode(await engine.exportRecovery());
    data['documents']['op:weight:w']['row']['weight'] = 9;
    await expectLater(
      engine.restoreRecovery(jsonEncode(data)),
      throwsA(isA<SyncFailure>()),
    );
    expect(engine.operations.single['row']['weight'], 4.5);
  });

  test(
    'export does not release work; logout confirmation refuses an outdated export',
    () async {
      await engine.enqueue(weight('w'));
      final exported = await engine.exportRecovery();
      expect(engine.pending, 1);
      await engine.enqueue(weight('new'));
      expect(await engine.releaseExportedOperations(exported), isFalse);
      expect(engine.pending, 2);
      expect(
        await engine.releaseExportedOperations(await engine.exportRecovery()),
        isTrue,
      );
      expect(engine.pending, 0);
    },
  );

  test('atomic version checks prevent one tab overwriting another', () async {
    await store.commit(
      puts: {
        'row': {'name': 'Original'},
      },
    );
    final stale = await store.read('row');
    await store.commit(
      puts: {
        'row': {'name': 'Family edit'},
      },
    );
    expect(
      await store.commit(
        expected: {'row': stale!.version},
        puts: {
          'row': {'name': 'Stale'},
        },
      ),
      isFalse,
    );
    expect((await store.read('row'))!.value['name'], 'Family edit');
  });

  test(
    'new edits depend on restored work even when their clock is earlier',
    () async {
      await engine.enqueue(edit('old', {'name': 'First'}));
      final recovered = SyncEngine(
        store: MemoryOfflineStore(),
        remote: remote,
        accountId: 'user',
        clock: () => clock.subtract(const Duration(minutes: 1)),
      );
      await recovered.restoreRecovery(await engine.exportRecovery());
      await recovered.verifyAccess();
      await recovered.enqueue(
        edit(
          'new',
          {'name': 'Second'},
          base: {...animal('a'), 'name': 'First'},
        ),
      );
      await recovered.sync();
      expect(remote.animals['a']!['name'], 'Second');
      expect(recovered.pending, 0);
    },
  );

  test(
    'malformed recovery operations are rejected before any cache is restored',
    () async {
      await engine.enqueue(weight('w'));
      final data = jsonDecode(await engine.exportRecovery());
      data['documents']['op:weight:w']['row']['weight'] = -1;
      final recovered = SyncEngine(
        store: MemoryOfflineStore(),
        remote: remote,
        accountId: 'user',
      );
      await expectLater(
        recovered.restoreRecovery(jsonEncode(data)),
        throwsA(isA<SyncFailure>()),
      );
      expect(await recovered.store.scan(recovered.prefix), isEmpty);
    },
  );
  test(
    'request recovery includes its pending binary and excludes downloaded files and credentials',
    () async {
      const id = 'aaaaaaaa-1111-4111-8111-111111111111';
      const ref = 'cache:pending-file:$id';
      await store.commit(
        puts: {
          engine.key('op:$id'): {
            'id': id,
            'kind': 'request',
            'animal_id': 'a',
            'request': {
              'type': 'file',
              'bucket': 'animal_photos',
              'path': 'a/new.jpg',
              'asset_ref': ref,
              'asset_hash': 'fixture',
            },
            'mutations': [],
            'expects': [],
            'requires': [],
            'state': 'pending',
            'created_at': clock.toIso8601String(),
          },
          engine.key(ref): {
            'base64': 'YWJj',
            'sha256': 'fixture',
            'type': 'image/jpeg',
          },
          engine.key('cache:file:other:full'): {'base64': 'unneeded'},
          'workspace:active': {'token': 'not-in-export'},
        },
      );
      final encoded = await engine.exportRecovery();
      expect(encoded, contains('YWJj'));
      expect(encoded, isNot(contains('unneeded')));
      expect(encoded, isNot(contains('not-in-export')));
      final restoredStore = MemoryOfflineStore();
      final restored = SyncEngine(
        store: restoredStore,
        remote: remote,
        accountId: 'user',
        clock: () => clock,
      );
      await restored.restoreRecovery(encoded);
      expect(restored.pending, 1);
      expect(
        (await restoredStore.read(restored.key(ref)))!.value['base64'],
        'YWJj',
      );
      await expectLater(restored.requireAccess(), throwsA(isA<SyncFailure>()));
      final damaged = jsonDecode(encoded);
      (damaged['documents'] as Map).remove(ref);
      final fresh = SyncEngine(
        store: MemoryOfflineStore(),
        remote: remote,
        accountId: 'user',
      );
      await expectLater(
        fresh.restoreRecovery(jsonEncode(damaged)),
        throwsA(isA<SyncFailure>()),
      );
      expect(fresh.pending, 0);
      await store.commit(deletes: [engine.key(ref)]);
      await expectLater(engine.exportRecovery(), throwsA(isA<SyncFailure>()));
    },
  );
}
