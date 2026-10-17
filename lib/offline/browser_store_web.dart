import 'dart:convert';
import 'dart:js_interop';
import 'offline_store.dart';
import 'sync_engine.dart';

@JS('breederOffline.read')
external JSPromise<JSString> _read(JSString key);
@JS('breederOffline.scan')
external JSPromise<JSString> _scan(JSString prefix);
@JS('breederOffline.commit')
external JSPromise<JSBoolean> _commit(JSString batch);
@JS('breederOffline.storageStatus')
external JSPromise<JSString> _status();
@JS('breederOffline.watch')
external void _watch(JSFunction callback);
@JS('breederOffline.isOnline')
external JSBoolean _isOnline();
@JS('breederWorkspace.setup')
external JSPromise<JSString> _setupWorkspace(JSString config);
@JS('breederWorkspace.isReady')
external JSBoolean _workspaceReady();
@JS('breederWorkspace.isControlled')
external JSBoolean _workspaceControlled();
@JS('breederWorkspace.status')
external JSPromise<JSString> _workspaceStatus();
@JS('breederWorkspace.download')
external JSPromise<JSString> _downloadWorkspace(JSBoolean full);
@JS('breederWorkspace.push')
external JSPromise<JSString> _pushWorkspace(JSString operation);
@JS('breederWorkspace.resolve')
external JSPromise<JSString> _resolveWorkspace(JSString operation);
@JS('breederWorkspace.fileUrl')
external JSPromise<JSString> _workspaceFile(JSString value);
@JS('breederOffline.watchWorkspace')
external void _watchWorkspace(JSFunction callback);
@JS('breederWorkspace.pause')
external JSPromise<JSBoolean> _pauseWorkspace(JSBoolean paused);
@JS('breederWorkspace.cancelJob')
external JSPromise<JSString> _cancelJob(JSString id);
@JS('breederWorkspace.retryJob')
external JSPromise<JSString> _retryJob(JSString id);

LocalDocument _document(dynamic row) => LocalDocument(
  (row['version'] as num).toInt(),
  Map<String, dynamic>.from(row['value'] as Map),
);

class BrowserOfflineStore implements OfflineStore {
  @override
  Future<LocalDocument?> read(String key) async {
    final row = jsonDecode((await _read(key.toJS).toDart).toDart);
    return row == null ? null : _document(row);
  }

  @override
  Future<Map<String, LocalDocument>> scan(String prefix) async {
    final rows = jsonDecode((await _scan(prefix.toJS).toDart).toDart) as List;
    return {for (final row in rows) row['key'] as String: _document(row)};
  }

  @override
  Future<bool> commit({
    Map<String, int?> expected = const {},
    Map<String, JsonMap> puts = const {},
    List<String> deletes = const [],
  }) async => (await _commit(
    jsonEncode({'expected': expected, 'puts': puts, 'deletes': deletes}).toJS,
  ).toDart).toDart;
}

OfflineStore createBrowserStore() => BrowserOfflineStore();
Future<JsonMap> browserStorageStatus() async => Map<String, dynamic>.from(
  jsonDecode((await _status().toDart).toDart) as Map,
);
void watchBrowserConnectivity(void Function() callback) =>
    _watch(callback.toJS);
bool browserIsOnline() => _isOnline().toDart;
Future<JsonMap> _map(JSPromise<JSString> value) async {
  final result = Map<String, dynamic>.from(
    jsonDecode((await value.toDart).toDart) as Map,
  );
  if (result['error'] != null) {
    throw SyncFailure(
      result['error'],
      retryable: result['retryable'] == true,
      server: result['server'] == null
          ? null
          : Map<String, dynamic>.from(result['server'] as Map),
    );
  }
  return result;
}

Future<void> setupBrowserWorkspace(JsonMap? config) async {
  await _map(_setupWorkspace(jsonEncode(config).toJS));
}

bool browserWorkspaceReady() => _workspaceReady().toDart;
bool browserHasOfflineWorker() => _workspaceControlled().toDart;
Future<JsonMap> browserWorkspaceStatus() => _map(_workspaceStatus());
Future<JsonMap> downloadBrowserWorkspace({bool fullFiles = false}) =>
    _map(_downloadWorkspace(fullFiles.toJS));
Future<void> pushBrowserRequest(JsonMap operation) async {
  final value = await _map(_pushWorkspace(jsonEncode(operation).toJS));
  if (value['error'] != null) {
    throw SyncFailure(
      value['error'],
      retryable: value['retryable'] == true,
      server: value['server'] == null
          ? null
          : Map<String, dynamic>.from(value['server'] as Map),
    );
  }
}

Future<void> resolveBrowserRequest(String id, bool keep) async {
  await _map(_resolveWorkspace(jsonEncode({'id': id, 'keep': keep}).toJS));
}

Future<String?> browserFileUrl(
  String bucket,
  String path, {
  bool full = false,
}) async {
  final value = (await _workspaceFile(
    jsonEncode({'bucket': bucket, 'path': path, 'full': full}).toJS,
  ).toDart).toDart;
  return value.isEmpty ? null : value;
}

void watchBrowserWorkspace(void Function() callback) =>
    _watchWorkspace(callback.toJS);
Future<bool> pauseBrowserWorkspace(bool paused) async =>
    (await _pauseWorkspace(paused.toJS).toDart).toDart;
Future<void> cancelBrowserJob(String id) async {
  await _map(_cancelJob(id.toJS));
}

Future<void> retryBrowserJob(String id) async {
  await _map(_retryJob(id.toJS));
}
