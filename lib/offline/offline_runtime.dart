import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/record_write_attempt.dart';
import '../services/sales_service.dart';
import '../utils/animal_labels.dart';
import '../config/app_config.dart';
import 'browser_store.dart';
import 'offline_data_client.dart';
import 'offline_store.dart';
import 'offline_reads.dart';
import 'sync_engine.dart';

export 'offline_reads.dart'
    show OfflineDataUnavailable, isOfflineTransportError;

/// Existing pilot operations must reach the actual server while a full local
/// repository is active. Their own projections are not acknowledgements.
class _NetworkOnlyClient extends http.BaseClient {
  final _inner = http.Client();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!browserHasOfflineWorker()) return _inner.send(request);
    final target = request.url.replace(
      queryParameters: {
        ...request.url.queryParameters,
        '__breeder_network': '1',
      },
    );
    final copy = http.Request(request.method, target)
      ..headers.addAll(request.headers)
      ..bodyBytes = await request.finalize().toBytes();
    return _inner.send(copy);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

class SupabaseSyncRemote implements SyncRemote, RequestSyncRemote {
  final SupabaseClient client;
  final String accountId;
  final OfflineConnection connection;
  final SupabaseClient network;
  SupabaseSyncRemote(this.client, this.accountId, this.connection)
    : network = SupabaseClient(
        AppConfig.supabaseUrl,
        AppConfig.supabaseKey,
        httpClient: _NetworkOnlyClient(),
        accessToken: () async {
          if (client.auth.currentUser?.id != accountId) {
            throw const SyncFailure(
              'Sign in to the original account to sync this work.',
              retryable: true,
            );
          }
          return client.auth.currentSession?.accessToken;
        },
      );

  @override
  Future<void> applyRequest(JsonMap operation) async {
    if(connection.unavailable)throw const SyncFailure('Connection unavailable. Changes remain saved on this device.',retryable:true);
    try {
      await pushBrowserRequest(operation);
    } on SyncFailure catch (error) {
      if (error.retryable) connection.markUnavailable();
      rethrow;
    }
  }

  Future<T> _call<T>(Future<T> Function() action) async {
    if (client.auth.currentUser?.id != accountId) {
      throw const SyncFailure(
        'Sign in to the original account to sync this work.',
        retryable: true,
      );
    }
    try {
      if (connection.unavailable) {
        throw TimeoutException('Connection unavailable');
      }
      return await connection.request(
        action,
        timeout: const Duration(seconds: 20),
      );
    } catch (error) {
      if (isOfflineTransportError(error)) {
        throw const SyncFailure(
          'Connection unavailable. Changes remain saved on this device.',
          retryable: true,
        );
      }
      if (error is PostgrestException) {
        if (['PGRST301', 'PGRST303'].contains(error.code)) {
          throw const SyncFailure(
            'Sign in again to finish syncing. Your work is retained.',
            retryable: true,
          );
        }
        throw SyncFailure(
          error.code == '23505'
              ? 'A record with this identity already exists. Review your saved change.'
              : error.code == 'P0001' && error.message.contains('animal')
              ? error.message
              : 'The server could not accept this change. Check current access and record rules.',
        );
      }
      if (error is StateError) throw SyncFailure(error.message.toString());
      rethrow;
    }
  }

  @override
  Future<JsonMap> animal(String id) => _call(() async {
    final row = await network
        .from('animals')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (row == null) {
      throw const SyncFailure(
        'This animal was deleted or family access has ended. Your draft is retained.',
      );
    }
    return row;
  });
  @override
  Future<JsonMap?> updateAnimal(String id, JsonMap changes, int revision) =>
      _call(() async {
        final rows = await network
            .from('animals')
            .update(changes)
            .eq('id', id)
            .eq('revision', revision)
            .select();
        return rows.isEmpty ? null : rows.single;
      });
  @override
  Future<void> insertWeight(JsonMap row) => _call(
    () => RecordWriteAttempt('animal_weights', [row]).save(client: network),
  );
}

/// Shared offline runtime, including compatibility with saved pilot operations.
/// Never use an in-memory adapter if browser storage cannot open.
class OfflineRuntime {
  static const enabled = kIsWeb && bool.fromEnvironment('OFFLINE_PILOT');
  static OfflineDataClient? _dataClient;
  static SupabaseClient get client => !enabled
      ? Supabase.instance.client
      : _dataClient ??= OfflineDataClient(
          url: AppConfig.supabaseUrl,
          key: AppConfig.supabaseKey,
          sessionClient: Supabase.instance.client,
          localReady: () => workspaceReady,
        );
  static final current = ValueNotifier<SyncEngine?>(null);
  static final problem = ValueNotifier<String?>(null);
  static final workspaceStatus = ValueNotifier<JsonMap>({});
  static Timer? _retry;
  static Timer? _connectionRetry;
  static OfflineConnection? _connection;
  static int _failures = 0;
  static String? _actor;
  static OfflineStore? _store;
  static int _generation = 0;
  static Future<void>? _attachment;
  static bool _preparingLogout = false;
  static const fullEnabled = enabled && bool.fromEnvironment('OFFLINE_FULL');
  static bool get workspaceReady =>
      enabled && engine != null && browserWorkspaceReady();
  static JsonMap serviceResult(dynamic data) {
    final value = Map<String, dynamic>.from(data as Map);
    if (value['queued'] == true) {
      throw StateError(
        value['error'] ??
            'Request saved. Open Sync to track it after reconnection.',
      );
    }
    return value;
  }

  static SyncEngine? get engine =>
      enabled &&
          current.value?.accountId ==
              Supabase.instance.client.auth.currentUser?.id
      ? current.value
      : null;

  static Future<void> initialize() async {
    if (!enabled) return;
    _store = createBrowserStore();
    watchBrowserConnectivity(() {
      if (!browserIsOnline()) _connection?.markUnavailable();
      unawaited(sync(refreshDownload: true));
    });
    watchBrowserWorkspace(() async {
      final active = engine;
      if (active == null) return;
      try {
        final status = await browserWorkspaceStatus();
        if (!identical(active, engine)) return;
        workspaceStatus.value = status;
        await active.refresh();
        if (identical(active, engine) && active.pending > 0) unawaited(sync());
      } catch (_) {
        if (identical(active, engine)) {
          problem.value =
              'Unable to read device storage. Keep this app open and export your work before clearing browser data.';
        }
      }
    });
    Supabase.instance.client.auth.onAuthStateChange.listen(
      (_) {
        unawaited(() async {
          try {
            await attach();
            await _configureWorkspace();
          } catch (_) {
            problem.value =
                'Unable to prepare device storage. Your saved work is retained.';
          }
        }());
      },
      onError: (Object error, StackTrace stack) {
        if (isOfflineTransportError(error)) {
          _connection?.markUnavailable();
        } else {
          problem.value =
              'Sign in again to finish syncing. Your saved work is retained.';
        }
      },
    );
    await attach();
    Timer.periodic(const Duration(seconds: 30), (_) {
      if ((workspaceReady || fullEnabled) &&
          browserIsOnline() &&
          _connection?.unavailable == false) {
        unawaited(sync(refreshDownload: true));
      }
    });
  }

  static Future<void> attach() {
    final actor = Supabase.instance.client.auth.currentUser?.id;
    if (actor == _actor) {
      if (_attachment != null) return _attachment!;
      if (current.value != null || actor == null) return Future.value();
    }
    final pending = _attach(actor);
    _attachment = pending;
    return pending.whenComplete(() {
      if (identical(_attachment, pending)) _attachment = null;
    });
  }

  static Future<void> _attach(String? actor) async {
    final generation = ++_generation;
    _retry?.cancel();
    _connectionRetry?.cancel();
    _connection = null;
    _actor = actor;
    current.value = null;
    workspaceStatus.value = {};
    if (actor == null) {
      await setupBrowserWorkspace(null);
      return;
    }
    final connection = OfflineConnection(
      onUnavailable: () {
        if (generation == _generation) _scheduleConnectionCheck();
      },
    );
    _connection = connection;
    final next = SyncEngine(
      store: _store!,
      remote: SupabaseSyncRemote(Supabase.instance.client, actor, connection),
      accountId: actor,
    );
    try {
      await next.refresh();
      if (generation != _generation) return;
      current.value = next;
      await _configureWorkspace();
      problem.value = null;
      if (!browserIsOnline()) connection.markUnavailable();
      unawaited(sync(refreshDownload: true));
      if (fullEnabled && !browserWorkspaceReady() && browserIsOnline()) {
        unawaited(
          download().catchError((Object error) => {'error': error.toString()}),
        );
      }
    } catch (_) {
      problem.value =
          'Device storage is unavailable. Offline saving is disabled; reconnect before making changes.';
    }
  }

  static Future<void> _configureWorkspace() async {
    if (!enabled) return;
    final session = Supabase.instance.client.auth.currentSession;
    await setupBrowserWorkspace(
      session == null
          ? null
          : {
              'account': session.user.id,
              'token': session.accessToken,
              'expires': session.expiresAt,
              'url': AppConfig.supabaseUrl,
              'apiKey': AppConfig.supabaseKey,
            },
    );
  }

  static Future<JsonMap> download({bool fullFiles = false}) async {
    await attach();
    JsonMap value;
    try {
      value = await downloadBrowserWorkspace(fullFiles: fullFiles);
    } on SyncFailure catch (error) {
      if (error.retryable) _connection?.markUnavailable();
      rethrow;
    }
    await engine?.refresh();
    return value;
  }

  static Future<void> resolveOperation(
    String id, {
    required bool keepMine,
  }) async {
    final active = engine!;
    final op = active.operations.firstWhere((o) => o['id'] == id);
    if (op['kind'] == 'request') {
      await resolveBrowserRequest(id, keepMine);
      await active.refresh();
    } else {
      await active.resolve(id, keepMine: keepMine);
    }
  }

  static void _scheduleConnectionCheck() {
    // Keep checking even with an empty outbox. Some phones never emit an
    // accurate reconnect event. Probes run independently of screen loading.
    _connectionRetry?.cancel();
    _connectionRetry = Timer(const Duration(seconds: 15), () {
      unawaited(sync());
    });
  }

  static Future<void> sync({bool refreshDownload = false}) async {
    if (_preparingLogout) return;
    final active = engine;
    if (active == null) return;
    _retry?.cancel();
    final connection = _connection!;
    if (browserIsOnline() &&
        Supabase.instance.client.auth.currentSession?.isExpired == true) {
      try {
        await connection.request(
          () => Supabase.instance.client.auth.refreshSession(),
          timeout: const Duration(seconds: 3),
        );
        await _configureWorkspace();
      } catch (_) {
        /* Saved views remain local; uploads retry after sign-in recovers. */
      }
      if (!identical(active, engine)) return;
    }
    if (connection.unavailable) {
      await connection.probe(() async {
        // Reachability only: the normal startup flow still verifies family
        // access and renews the seven-day lease after all its checks succeed.
        await Supabase.instance.client.auth.getUser();
      });
      if (!identical(active, engine)) return;
      if (connection.unavailable) {
        _scheduleConnectionCheck();
      } else {
        _connectionRetry?.cancel();
      }
    }
    final hadPending = active.pending > 0;
    await active.sync();
    if (!identical(active, engine)) return;
    if ((workspaceReady || fullEnabled) &&
        !connection.unavailable &&
        (refreshDownload ||
            hadPending && active.pending == 0 && active.error == null)) {
      try {
        await download();
      } catch (_) {
        /* Keep the last complete download and its freshness. */
      }
    }
    _failures = active.error == null ? 0 : (_failures + 1).clamp(0, 5);
    if (active.pending == 0 || (active.error == null && active.attention > 0)) {
      return;
    }
    // Connectivity events are hints. Periodic retries also recover from weak
    // service that never produces a reliable online/offline event.
    _retry = Timer(Duration(seconds: 5 * (1 << _failures)), () {
      unawaited(sync());
    });
  }

  static Future<bool> pauseForLogout() async {
    final result = await pauseBrowserWorkspace(true);
    if (result) _preparingLogout = true;
    return result;
  }

  static Future<void> resumeAfterLogoutDialog() async {
    _preparingLogout = false;
    await pauseBrowserWorkspace(false);
  }

  static Future<JsonMap> readThrough(
    String name,
    Future<JsonMap> Function() fetch, {
    String? fallbackName,
  }) async {
    if (!enabled) return fetch();
    // A fresh sign-in emits before IndexedDB attachment finishes. Every startup
    // read must wait, or its successful result can miss the offline cache.
    await attach();
    final active = engine;
    if (active == null) return fetch();
    if (workspaceReady) {
      // Full preparation verified current identity/family access atomically.
      // Ordinary reads now use the worker's local relational repository.
      if (name.startsWith('farms:')) {
        final rows = await client
            .from('farms')
            .select()
            .eq('owner_id', name.substring(6))
            .order('created_at');
        return {'rows': rows};
      }
      return fetch();
    }
    return readOfflineCached(
      active,
      name,
      fetch,
      fallbackName: fallbackName,
      offline: !browserIsOnline(),
      stillCurrent: () => identical(active, engine),
      connection: _connection,
    );
  }

  static Future<void> queueAnimal(
    String id,
    JsonMap changes,
    int revision, {
    JsonMap? expectedBase,
  }) async {
    final active = engine!;
    await active.refresh();
    final base = await active.animal(id);
    if (base == null || base['revision'] != revision) {
      throw const SyncFailure(
        'Reload this animal before saving an offline change.',
      );
    }
    if (expectedBase != null) {
      final checked = {
        ...changes.keys,
        if (changes.keys.any(SyncEngine.related.contains))
          ...SyncEngine.related,
      };
      if (checked.any(
        (field) =>
            !const DeepCollectionEquality().equals(
              base[field],
              expectedBase[field],
            ) &&
            !(changes.containsKey(field) &&
                const DeepCollectionEquality().equals(
                  base[field],
                  changes[field],
                )),
      )) {
        throw const SyncFailure(
          'This animal has another local edit. Your form is still shown; copy your changes and reload before saving.',
        );
      }
    }
    final different = {
      for (final e in changes.entries)
        if (!const DeepCollectionEquality().equals(base[e.key], e.value))
          e.key: e.value,
    };
    if (different.isEmpty) return;
    if (workspaceReady) {
      await client
          .from('animals')
          .update(different)
          .eq('id', id)
          .eq('revision', revision)
          .select();
      await active.refresh();
      unawaited(sync());
      return;
    }
    await active.enqueue({
      'id': SalesService.newId(),
      'kind': 'animal',
      'animal_id': id,
      'label': animalTitle(base['name'], base['tattoo']),
      'base': base,
      'changes': different,
    });
    unawaited(sync());
  }

  static Future<void> queueWeight(JsonMap row) async {
    final animal = await engine!.animal(row['animal_id']);
    if (animal == null || ['sold', 'deceased'].contains(animal['status'])) {
      throw const SyncFailure(
        'Load an eligible animal before recording an offline weight.',
      );
    }
    if (workspaceReady) {
      await client.from('animal_weights').insert(row);
      await engine!.refresh();
      unawaited(sync());
      return;
    }
    await engine!.enqueue({
      'id': 'weight:${row['id']}',
      'kind': 'weight',
      'animal_id': row['animal_id'],
      'label': animalTitle(animal['name'], animal['tattoo']),
      'row': row,
    });
    unawaited(sync());
  }

  static Future<String?> exportRecovery() async {
    final active = engine;
    if (active == null) return null;
    final encoded = await active.exportRecovery();
    await FilePicker.platform.saveFile(
      dialogTitle: 'Save pending work for recovery',
      fileName:
          'breeder-recovery-${DateTime.now().millisecondsSinceEpoch}.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: Uint8List.fromList(utf8.encode(encoded)),
    );
    // Web browsers cannot confirm that the user actually saved the download.
    // Callers must explicitly confirm possession before clearing any drafts.
    return encoded;
  }

  static Future<void> importRecovery() async {
    final active = engine;
    if (active == null) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      withData: true,
    );
    if (picked == null) return;
    final bytes = picked.files.single.bytes;
    if (bytes == null || bytes.length > 200 * 1024 * 1024) {
      throw const SyncFailure('Choose a recovery file smaller than 200 MB.');
    }
    await active.restoreRecovery(utf8.decode(bytes));
  }
}
