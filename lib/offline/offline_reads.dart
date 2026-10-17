import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'offline_store.dart';
import 'sync_engine.dart';

bool isOfflineTransportError(Object error) =>
    error is http.ClientException ||
    error is TimeoutException ||
    error is AuthRetryableFetchException ||
    (error is PostgrestException && ['502', '503', '504'].contains(error.code));

class OfflineDataUnavailable implements Exception {
  const OfflineDataUnavailable();
  @override
  String toString() =>
      'These records have not been downloaded. Connect and open them before using them offline.';
}

/// Share transport knowledge across screens. A stale navigator.onLine value
/// must not make every downloaded record wait for the same network timeout.
class OfflineConnection {
  final void Function()? onUnavailable;
  OfflineConnection({this.onUnavailable});

  bool unavailable = false;
  Future<void>? _probing;

  void markUnavailable() {
    unavailable = true;
    onUnavailable?.call();
  }

  Future<T> request<T>(
    Future<T> Function() action, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final value = await action().timeout(timeout);
      unavailable = false;
      return value;
    } catch (error) {
      if (isOfflineTransportError(error)) {
        markUnavailable();
      }
      // A rejection proves reachability, but remains an error for the caller.
      // Do not reset an outage for an unrelated local/storage exception.
      else if (error is PostgrestException || error is AuthException) {
        unavailable = false;
      }
      rethrow;
    }
  }

  /// At most one background probe; it never blocks cached navigation. Probing
  /// grants no offline lease and never treats an auth rejection as acceptance.
  Future<void> probe(Future<void> Function() action) => _probing ??= () async {
    try {
      await request(action, timeout: const Duration(seconds: 3));
    } catch (_) {
      // Screens still perform their authoritative checks once reachable.
    }
  }().whenComplete(() => _probing = null);
}

/// Only transport failures may fall back to previously downloaded records.
/// A permission, validation, or missing-record response remains authoritative.
Future<JsonMap> readOfflineCached(
  SyncEngine engine,
  String name,
  Future<JsonMap> Function() fetch, {
  String? fallbackName,
  bool offline = false,
  bool Function()? stillCurrent,
  OfflineConnection? connection,
}) async {
  void checkAccount() {
    if (stillCurrent != null && !stillCurrent()) {
      throw const SyncFailure(
        'The signed-in account changed. Reopen this page.',
      );
    }
  }

  Future<JsonMap?> downloaded() async {
    checkAccount();
    final cached =
        await engine.cached(name) ??
        (fallbackName == null ? null : await engine.cached(fallbackName));
    checkAccount();
    return cached;
  }

  final cached = await downloaded();
  if (offline || connection?.unavailable == true) {
    if (cached != null) return cached;
    if (connection?.unavailable == true) {
      throw const OfflineDataUnavailable();
    }
    // navigator.onLine is a hint. A stale offline flag must not prevent an
    // available server from downloading a record for the first time.
  }
  JsonMap value;
  try {
    value = await (connection ?? OfflineConnection()).request(
      fetch,
      // Only the first failure needs discovery. Later cached reads are local.
      timeout: Duration(seconds: cached == null ? 10 : 3),
    );
  } catch (error) {
    if (!isOfflineTransportError(error)) rethrow;
    checkAccount();
    if (cached == null) throw const OfflineDataUnavailable();
    return cached;
  }
  checkAccount();
  // Storage failures must never look like successful offline preparation.
  await engine.cache(name, value);
  return value;
}
