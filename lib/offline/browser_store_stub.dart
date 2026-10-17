import 'offline_store.dart';

OfflineStore createBrowserStore() =>
    throw UnsupportedError('Offline pilot requires a web browser.');

Future<Map<String, dynamic>> browserStorageStatus() async => {};
void watchBrowserConnectivity(void Function() callback) {}
bool browserIsOnline() => true;
Future<void> setupBrowserWorkspace(JsonMap? config) async {}
bool browserWorkspaceReady() => false;
bool browserHasOfflineWorker() => false;
Future<JsonMap> browserWorkspaceStatus() async => {};
Future<JsonMap> downloadBrowserWorkspace({bool fullFiles = false}) async => {};
Future<void> pushBrowserRequest(JsonMap operation) async =>
    throw UnsupportedError('Web only');
Future<void> resolveBrowserRequest(String id, bool keep) async {}
Future<String?> browserFileUrl(
  String bucket,
  String path, {
  bool full = false,
}) async => null;
void watchBrowserWorkspace(void Function() callback) {}
Future<bool> pauseBrowserWorkspace(bool paused) async => true;
Future<void> cancelBrowserJob(String id) async {}
Future<void> retryBrowserJob(String id) async {}
