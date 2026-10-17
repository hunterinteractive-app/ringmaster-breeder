import '../offline/offline_runtime.dart';
import '../offline/browser_store.dart';

class ShowReportService {
  static Future<Map<String, dynamic>> request(
    String action, {
    String? ownerId,
    String? reportId,
  }) async {
    if (action == 'download' && OfflineRuntime.workspaceReady) {
      final status = await browserWorkspaceStatus();
      for (final job in status['jobs'] as List? ?? []) {
        final file = job['result']?['file'] as Map?;
        if (job['target'] == 'show-reports' &&
            job['payload']?['report_id'] == reportId &&
            file != null) {
          final url = await browserFileUrl(
            file['bucket'],
            file['path'],
            full: true,
          );
          if (url != null) return {'url': url, 'offline': true};
        }
      }
    }
    final response = await OfflineRuntime.client.functions.invoke(
      'show-reports',
      body: {
        'action': action,
        if (ownerId != null) 'owner_id': ownerId,
        if (reportId != null) 'report_id': reportId,
      },
    );
    final result = Map<String, dynamic>.from(response.data as Map);
    if (result['queued'] == true) throw StateError(result['error']);
    if (result['error'] != null) throw Exception(result['error']);
    return result;
  }
}
