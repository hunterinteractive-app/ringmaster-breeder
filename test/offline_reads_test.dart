import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ringmaster_breeder/offline/offline_reads.dart';
import 'package:ringmaster_breeder/offline/offline_store.dart';
import 'package:ringmaster_breeder/offline/sync_engine.dart';

class _UnusedRemote implements SyncRemote {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FailingStore extends MemoryOfflineStore {
  @override
  Future<bool> commit({
    Map<String, int?> expected = const {},
    Map<String, JsonMap> puts = const {},
    List<String> deletes = const [],
  }) async => throw StateError('Storage full');
}

void main() {
  late SyncEngine engine;
  setUp(() {
    engine = SyncEngine(
      store: MemoryOfflineStore(),
      remote: _UnusedRemote(),
      accountId: 'user',
    );
  });

  test(
    'offline startup uses its saved account check without a request',
    () async {
      await engine.cache('deletion', {'pending': false});
      final result = await readOfflineCached(engine, 'deletion', () async {
        fail('An offline account check must use the downloaded result');
      }, offline: true);
      expect(result, {'pending': false});
    },
  );

  test(
    'a downloaded list animal can open before its detail view was cached',
    () async {
      await engine.cache('animal:a', {'id': 'a', 'name': 'Willow'});
      final result = await readOfflineCached(
        engine,
        'animal-view:a',
        () async => throw http.ClientException('No connection'),
        fallbackName: 'animal:a',
      );
      expect(result['name'], 'Willow');
    },
  );

  test(
    'missing offline history is distinguishable from empty history',
    () async {
      await expectLater(
        readOfflineCached(
          engine,
          'weights:a',
          () async => throw http.ClientException('No connection'),
          offline: true,
        ),
        throwsA(isA<OfflineDataUnavailable>()),
      );
      await engine.cache('weights:a', {'rows': []});
      expect(
        await readOfflineCached(
          engine,
          'weights:a',
          () async => {},
          offline: true,
        ),
        {'rows': []},
      );
    },
  );

  for (final error in <Object>[
    http.ClientException('No connection'),
    TimeoutException('No response'),
    AuthRetryableFetchException(message: 'No connection'),
    const PostgrestException(message: 'Gateway unavailable', code: '503'),
  ]) {
    test(
      'saved records survive ${error.runtimeType} transport failure',
      () async {
        await engine.cache('animal:a', {'id': 'a'});
        expect(
          await readOfflineCached(engine, 'animal:a', () async => throw error),
          {'id': 'a'},
        );
      },
    );
  }

  for (final code in ['42501', 'PGRST301', 'PGRST116', '23514']) {
    test(
      'a server response $code cannot be hidden by cached records',
      () async {
        await engine.cache('animal:a', {'id': 'a'});
        final error = PostgrestException(
          message: 'Server rejected request',
          code: code,
        );
        await expectLater(
          readOfflineCached(engine, 'animal:a', () async => throw error),
          throwsA(same(error)),
        );
      },
    );
  }

  test(
    'a response cannot be returned or cached after the account changes',
    () async {
      var current = true;
      await expectLater(
        readOfflineCached(engine, 'deletion', () async {
          current = false;
          return {'pending': false};
        }, stillCurrent: () => current),
        throwsA(isA<SyncFailure>()),
      );
      expect(await engine.cached('deletion'), isNull);
    },
  );

  test('failed device storage cannot report a successful download', () async {
    final failing = SyncEngine(
      store: _FailingStore(),
      remote: _UnusedRemote(),
      accountId: 'user',
    );
    await expectLater(
      readOfflineCached(failing, 'deletion', () async => {'pending': false}),
      throwsStateError,
    );
  });

  test(
    'a stale offline hint cannot prevent the first successful download',
    () async {
      expect(
        await readOfflineCached(
          engine,
          'deletion',
          () async => {'pending': false},
          offline: true,
        ),
        {'pending': false},
      );
      expect(await engine.cached('deletion'), {'pending': false});
    },
  );

  test(
    'one outage makes later screens and missing history immediate',
    () async {
      final connection = OfflineConnection();
      await engine.cache('animal:a', {'id': 'a'});
      await readOfflineCached(
        engine,
        'animal:a',
        () async => throw http.ClientException('No connection'),
        connection: connection,
      );
      expect(connection.unavailable, isTrue);
      for (var i = 0; i < 5; i++) {
        expect(
          await readOfflineCached(engine, 'animal:a', () async {
            fail('Known outages must not retry on every screen');
          }, connection: connection),
          {'id': 'a'},
        );
      }
      await expectLater(
        readOfflineCached(engine, 'weights:a', () async {
          fail('Missing offline history must not start another timeout');
        }, connection: connection),
        throwsA(isA<OfflineDataUnavailable>()),
      );
    },
  );

  testWidgets('first unresponsive request falls back after three seconds', (
    tester,
  ) async {
    final connection = OfflineConnection();
    await engine.cache('animal:a', {'id': 'a'});
    final network = Completer<JsonMap>();
    JsonMap? result;
    unawaited(
      readOfflineCached(
        engine,
        'animal:a',
        () => network.future,
        connection: connection,
      ).then((value) => result = value),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(result, isNull);
    await tester.pump(const Duration(seconds: 1));
    expect(result, {'id': 'a'});
    expect(connection.unavailable, isTrue);
    // A late response cannot silently overwrite the downloaded record.
    network.complete({'id': 'a', 'name': 'Late response'});
    await tester.pump();
    expect(await engine.cached('animal:a'), {'id': 'a'});
  });

  test('reconnection probes coalesce without delaying cached reads', () async {
    final connection = OfflineConnection()..markUnavailable();
    await engine.cache('animal:a', {'id': 'a'});
    final response = Completer<void>();
    var probes = 0;
    Future<void> probe() {
      probes++;
      return response.future;
    }

    final first = connection.probe(probe);
    final second = connection.probe(probe);
    expect(probes, 1);
    expect(
      await readOfflineCached(engine, 'animal:a', () async {
        fail('A probe in progress must not hold up the saved record');
      }, connection: connection),
      {'id': 'a'},
    );
    response.complete();
    await Future.wait([first, second]);
    expect(connection.unavailable, isFalse);
    expect(
      await readOfflineCached(
        engine,
        'animal:a',
        () async => {'id': 'a', 'name': 'Fresh record'},
        connection: connection,
      ),
      {'id': 'a', 'name': 'Fresh record'},
    );
  });

  test(
    'a reachable auth rejection resumes authoritative screen checks',
    () async {
      final connection = OfflineConnection()..markUnavailable();
      final error = AuthException('Session expired', statusCode: '401');
      await connection.probe(() async => throw error);
      expect(connection.unavailable, isFalse);
      await engine.cache('deletion', {'pending': false});
      await expectLater(
        readOfflineCached(
          engine,
          'deletion',
          () async => throw error,
          connection: connection,
        ),
        throwsA(same(error)),
      );
    },
  );

  test('failed probes retain the outage and schedule another check', () async {
    var retries = 0;
    final connection = OfflineConnection(onUnavailable: () => retries++);
    connection.markUnavailable();
    await connection.probe(() async => throw http.ClientException('Offline'));
    expect(connection.unavailable, isTrue);
    expect(retries, 2);
  });
}
