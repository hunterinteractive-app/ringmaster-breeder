import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../offline/browser_store.dart';
import '../offline/offline_runtime.dart';
import '../offline/sync_engine.dart';
import '../screens/record_import_screen.dart';
import '../screens/global_pedigree_import_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class SyncHeaderButton extends StatelessWidget {
  final bool compact;
  const SyncHeaderButton({super.key, this.compact = false});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: OfflineRuntime.current,
    builder: (context, engine, _) => ListenableBuilder(
      listenable: Listenable.merge([
        engine ?? OfflineRuntime.problem,
        OfflineRuntime.problem,
        OfflineRuntime.workspaceStatus,
      ]),
      builder: (context, _) {
        final jobs =
            OfflineRuntime.workspaceStatus.value['jobs'] as List? ?? [];
        final pending =
            (engine?.pending ?? 0) +
            jobs
                .where((j) => !['complete', 'cancelled'].contains(j['state']))
                .length;
        final attention =
            (engine?.attention ?? 0) > 0 ||
            jobs.any(
              (j) => ['needs_input', 'review', 'failed'].contains(j['state']),
            );
        final label = pending > 0 ? 'Sync ($pending)' : 'Sync';
        final icon = Icon(attention ? Icons.sync_problem : Icons.sync);
        void openStatus() => showDialog<void>(
          context: context,
          builder: (_) => SyncStatusDialog(engine: engine),
        );
        if (compact) {
          return IconButton(
            tooltip: label,
            color: Colors.white,
            icon: Badge(
              isLabelVisible: pending > 0,
              label: Text(pending > 99 ? '99+' : '$pending'),
              child: icon,
            ),
            onPressed: openStatus,
          );
        }
        return OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white54),
          ),
          icon: icon,
          label: Text(label),
          onPressed: openStatus,
        );
      },
    ),
  );
}

class SyncStatusDialog extends StatefulWidget {
  final SyncEngine? engine;
  const SyncStatusDialog({super.key, this.engine});
  @override
  State<SyncStatusDialog> createState() => _SyncStatusDialogState();
}

class _SyncStatusDialogState extends State<SyncStatusDialog> {
  Map<String, dynamic> storage = {};
  Map<String, dynamic> workspace = {};
  bool downloading = false, statusLoaded = false;
  Timer? statusTimer;
  String? message;
  @override
  void initState() {
    super.initState();
    workspace = Map<String, dynamic>.from(OfflineRuntime.workspaceStatus.value);
    statusLoaded = workspace.isNotEmpty;
    browserStorageStatus()
        .then((value) {
          if (mounted) setState(() => storage = value);
        })
        .catchError((Object _) {});
    unawaited(widget.engine?.refresh());
    widget.engine?.addListener(scheduleStatus);
    scheduleStatus(immediate: true);
  }

  void scheduleStatus({bool immediate = false}) {
    statusTimer?.cancel();
    statusTimer = Timer(Duration(milliseconds: immediate ? 0 : 150), () async {
      if (widget.engine == null) return;
      try {
        final value = await browserWorkspaceStatus();
        if (mounted) {
          setState(() {
            workspace = value;
            statusLoaded = true;
          });
        }
      } catch (_) {
        /* Storage/startup errors are displayed separately. */
      }
    });
  }

  @override
  void dispose() {
    statusTimer?.cancel();
    widget.engine?.removeListener(scheduleStatus);
    super.dispose();
  }

  Future<void> prepare({bool fullFiles = false}) async {
    setState(() => downloading = true);
    await perform(() async {
      await OfflineRuntime.download(fullFiles: fullFiles);
    });
    if (mounted) setState(() => downloading = false);
    scheduleStatus();
  }

  String operationLabel(Map<String, dynamic> op) {
    if (op['kind'] == 'weight') return 'Weight';
    if (op['kind'] == 'animal') return 'Animal edit';
    final request = op['request'] as Map?;
    return const {
          'farms': 'Herd',
          'users': 'Profile',
          'animals': 'Animal',
          'animal_weights': 'Weight',
          'animal_health_records': 'Health record',
          'breeding_settings': 'Breeding settings',
          'record_breeding_with_parents': 'Breeding record',
          'save_breeding_tracking': 'Litter tracking',
          'create_litter_animals': 'Offspring',
          'save_pedigree_draft': 'Pedigree',
          'pedigree_drafts': 'Pedigree draft',
          'create_animal_with_color_details': 'New animal',
          'create_breeder_ring': 'New herd',
          'delete_empty_breeder_ring': 'Empty herd deletion',
          'animal_sales': 'Sale',
          'animal_sale_payments': 'Payment record',
          'email-buyer-pedigree': 'Pedigree email',
          'show-reports': 'Show report',
          'global-pedigree': 'Outside pedigree lookup',
          'import-ringmaster-records': 'Record import',
        }[request?['target']] ??
        (request?['type'] == 'file' ? 'Attachment' : 'Saved action');
  }

  Iterable<Widget> requestConflictDetails(Map<String, dynamic> op) sync* {
    final current = (op['server']?['current'] as List? ?? []);
    for (final value in op['mutations'] as List? ?? []) {
      final m = Map<String, dynamic>.from(value as Map);
      if (m['before'] is! Map) continue;
      final latest = current
          .where(
            (row) =>
                row['table'] == m['table'] &&
                (row['key'] as Map).entries.every(
                  (e) => m['row'][e.key] == e.value,
                ),
          )
          .firstOrNull;
      if (latest == null || latest['row'] == null) {
        yield const Text(
          'This record was deleted or is no longer accessible. Your saved version is retained.',
        );
        continue;
      }
      for (final field in (m['before'] as Map).keys) {
        if (!(m['row'] as Map).containsKey(field)) continue;
        String show(dynamic v) {
          final text = v?.toString() ?? 'Empty';
          return text.length > 180 ? '${text.substring(0, 180)}…' : text;
        }

        yield Text(
          '${field.toString().replaceAll('_', ' ')} — Yours: ${show(m['row'][field])} · Server: ${show(latest['row'][field])}',
        );
      }
    }
  }

  Future<void> openJobFile(Map job) async {
    final file = job['result']?['file'] as Map?;
    if (file == null) return;
    final url = await browserFileUrl(file['bucket'], file['path'], full: true);
    if (url == null) {
      throw const SyncFailure(
        'This file has not finished downloading. Reconnect and choose Sync now.',
      );
    }
    if (!await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    )) {
      throw const SyncFailure('Unable to open the downloaded file.');
    }
  }

  String size(dynamic bytes) => bytes is num
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
      : 'Unavailable on this browser';

  Future<void> perform(Future<void> Function() action) async {
    try {
      await action();
      if (mounted) setState(() => message = null);
    } catch (error) {
      if (mounted) setState(() => message = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final engine = widget.engine;
    return ListenableBuilder(
      listenable: engine ?? OfflineRuntime.problem,
      builder: (context, _) => AlertDialog(
        title: const Text('Sync status'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  OfflineRuntime.workspaceReady
                      ? 'Offline access: downloaded herd records, ordinary edits, and queued outside-service requests.'
                      : 'Offline pilot: downloaded animals, animal edits, and new weights. Other workflows still require a connection.',
                ),
                const SizedBox(height: 16),
                if (!statusLoaded)
                  const Text('Checking downloaded records…')
                else if (workspace['ready'] == true) ...[
                  const Text('All authorized record tables downloaded.'),
                  Text(
                    'Last record download: ${workspace['downloaded_at'] ?? 'Not completed'}',
                  ),
                  if (workspace['files'] is Map)
                    Text(
                      'Files downloaded: ${workspace['files']['completed']} of ${workspace['files']['total']}',
                    ),
                  if (workspace['files'] is Map &&
                      (workspace['files']['failed'] as List? ?? []).isNotEmpty)
                    const Text(
                      'Some photos or files need another download attempt.',
                    ),
                ] else
                  const Text(
                    'Prepare your records while connected before going into the barn.',
                  ),
                if (workspace['download'] is Map &&
                    workspace['download']['state'] == 'failed')
                  Text(
                    workspace['download']['message'] ??
                        'Download did not finish. The previous complete download is retained.',
                  ),
                if (downloading) const LinearProgressIndicator(),
                if (workspace['update_waiting'] == true)
                  const Text(
                    'An app update is ready. Finish saving your forms, then close all Breeder tabs and reopen the app to install it.',
                  ),
                if (workspace['paused'] == true) ...[
                  const Text('Uploads are paused for a recovery export.'),
                  TextButton(
                    onPressed: () =>
                        perform(OfflineRuntime.resumeAfterLogoutDialog),
                    child: const Text('Resume uploads'),
                  ),
                ],
                Text(
                  workspace['background_sync'] == true
                      ? 'Background sync is available on this browser.'
                      : 'Reopen the app after reconnecting to finish device synchronization.',
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: downloading || engine == null
                          ? null
                          : () => prepare(),
                      child: const Text('Download records and thumbnails'),
                    ),
                    TextButton(
                      onPressed: downloading || engine == null
                          ? null
                          : () => prepare(fullFiles: true),
                      child: Text(
                        'Include full photos and documents (${size(workspace['optional_bytes'])})',
                      ),
                    ),
                  ],
                ),
                Text(
                  engine?.status ??
                      OfflineRuntime.problem.value ??
                      'Sign in to view device sync activity.',
                ),
                if (engine != null) ...[
                  Text(
                    'Last queue sync: ${engine.lastSynced == null ? 'Not yet completed' : DateFormat.yMd().add_jm().format(engine.lastSynced!.toLocal())}',
                  ),
                  Text('Pending changes: ${engine.pending}'),
                  Text('Needs attention: ${engine.attention}'),
                  Text('Completed this attempt: ${engine.completed}'),
                  if (engine.syncing) const LinearProgressIndicator(),
                  if (engine.error != null) Text(engine.error!),
                ],
                const SizedBox(height: 12),
                Text('Device storage used: ${size(storage['usage'])}'),
                Text('Storage quota: ${size(storage['quota'])}'),
                Text(
                  'Persistent storage: ${switch (storage['persistent']) {
                    true => 'Granted',
                    false => 'Not granted',
                    _ => 'Unavailable on this browser',
                  }}',
                ),
                if (statusLoaded && workspace['ready'] != true)
                  const Text(
                    'Full herd offline readiness: download not completed.',
                  ),
                if (message != null) Text(message!),
                for (final op
                    in engine?.operations ?? <Map<String, dynamic>>[]) ...[
                  const Divider(),
                  Text(
                    '${operationLabel(op)} · ${op['label'] ?? 'Saved record'}',
                  ),
                  Text(
                    op['message'] ?? 'Saved on this device. Waiting to sync.',
                  ),
                  if (op['state'] == 'conflict') ...[
                    for (final field in (op['changes'] as Map? ?? {}).keys)
                      Text(
                        '$field — Yours: ${op['changes'][field]} · Server: ${op['server'][field]}',
                      ),
                    if (op['kind'] == 'request') ...requestConflictDetails(op),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: engine!.syncing
                              ? null
                              : () => perform(
                                  () => OfflineRuntime.resolveOperation(
                                    op['id'],
                                    keepMine: false,
                                  ),
                                ),
                          child: const Text('Use server version'),
                        ),
                        TextButton(
                          onPressed: engine.syncing
                              ? null
                              : () => perform(
                                  () => OfflineRuntime.resolveOperation(
                                    op['id'],
                                    keepMine: true,
                                  ),
                                ),
                          child: const Text('Keep my changes'),
                        ),
                      ],
                    ),
                  ],
                  if (op['kind'] == 'request' &&
                      ['pending', 'rejected'].contains(op['state']))
                    TextButton(
                      onPressed: engine?.syncing == true
                          ? null
                          : () async {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text(
                                    'Discard this saved action?',
                                  ),
                                  content: const Text(
                                    'This removes the unsynced action from this device. Export a recovery file first if you may need it.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Keep action'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('Discard'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                await perform(
                                  () => OfflineRuntime.resolveOperation(
                                    op['id'],
                                    keepMine: false,
                                  ),
                                );
                              }
                            },
                      child: const Text('Discard saved action'),
                    ),
                ],
                if ((workspace['jobs'] as List? ?? []).isNotEmpty)
                  const Divider(),
                for (final job in workspace['jobs'] as List? ?? []) ...[
                  Text(
                    '${operationLabel({
                      'kind': 'request',
                      'request': {'target': job['target']},
                    })} · ${const {'queued': 'Waiting on server', 'running': 'Processing', 'needs_input': 'Needs your sign-in', 'review': 'Ready for review', 'complete': 'Completed', 'failed': 'Needs attention', 'cancelled': 'Cancelled'}[job['state']] ?? job['state']}',
                  ),
                  if (job['error'] != null) Text(job['error']),
                  if (job['state'] == 'review' &&
                      job['target'] == 'import-ringmaster-records')
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RecordImportScreen(
                            initialLookup: Map<String, dynamic>.from(
                              job['result'] as Map,
                            ),
                          ),
                        ),
                      ),
                      child: const Text('Review retrieved records'),
                    ),
                  if (job['state'] == 'needs_input')
                    TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const GlobalPedigreeImportScreen(),
                        ),
                      ),
                      child: const Text('Open Global Pedigree sign-in'),
                    ),
                  if (job['result']?['file'] != null)
                    TextButton(
                      onPressed: () => perform(() => openJobFile(job as Map)),
                      child: const Text('Open downloaded file'),
                    ),
                  if (job['state'] == 'failed' ||
                      job['state'] == 'running' &&
                          DateTime.tryParse(job['started_at'] ?? '')?.isBefore(
                                DateTime.now().subtract(
                                  const Duration(minutes: 5),
                                ),
                              ) ==
                              true)
                    TextButton(
                      onPressed: () =>
                          perform(() => retryBrowserJob(job['id'])),
                      child: const Text('Retry same request'),
                    ),
                  if ([
                    'queued',
                    'needs_input',
                    'review',
                    'failed',
                  ].contains(job['state']))
                    TextButton(
                      onPressed: () =>
                          perform(() => cancelBrowserJob(job['id'])),
                      child: const Text('Cancel request'),
                    ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (engine != null)
            TextButton(
              onPressed: () => perform(() async {
                await OfflineRuntime.exportRecovery();
              }),
              child: const Text('Export recovery file'),
            ),
          if (engine != null)
            TextButton(
              onPressed: engine.syncing
                  ? null
                  : () => perform(OfflineRuntime.importRecovery),
              child: const Text('Restore recovery file'),
            ),
          if (engine != null)
            FilledButton.icon(
              onPressed: engine.syncing
                  ? null
                  : () => perform(
                      () => OfflineRuntime.sync(refreshDownload: true),
                    ),
              icon: const Icon(Icons.sync),
              label: const Text('Sync now'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/// Exporting is not delivery. Once the user confirms possession of the exact
/// export, remove those queued operations so a closed tab cannot send them later.
Future<bool> confirmOfflineLogout(BuildContext context) async {
  final engine = OfflineRuntime.engine;
  if (engine == null) return true;
  await engine.refresh();
  if (engine.pending == 0) return true;
  if (!context.mounted) return false;
  final action = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Save pending work before signing out'),
      content: Text(
        '${engine.pending} changes are still on this device. Sync them or save a recovery file before signing out.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Stay signed in'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, 'export'),
          child: const Text('Export pending work'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, 'sync'),
          child: const Text('Sync now'),
        ),
      ],
    ),
  );
  if (action == 'sync') {
    await OfflineRuntime.sync();
    return engine.pending == 0;
  }
  if (action != 'export') return false;
  if (!await OfflineRuntime.pauseForLogout()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A background upload is being confirmed. Wait for its result before signing out.',
          ),
        ),
      );
    }
    return false;
  }
  try {
    final exported = await OfflineRuntime.exportRecovery();
    if (exported == null || !context.mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm your recovery file is saved'),
        content: const Text(
          'Confirm that you saved the recovery file somewhere you can find it. Device-only changes will be removed from this device. Requests already accepted by the server may still finish; restore the file with this account to reconcile them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('File saved — sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;
    return engine.releaseExportedOperations(exported);
  } finally {
    await OfflineRuntime.resumeAfterLogoutDialog();
  }
}
