import '../offline/offline_runtime.dart';
import 'package:flutter/material.dart';
import '../services/show_report_service.dart';
import '../screens/show_reports_screen.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ShowConnectionPanel extends StatefulWidget {
  final Future<Map<String, dynamic>> Function(String, List<String>)? gateway;
  const ShowConnectionPanel({super.key, this.gateway});
  @override
  State<ShowConnectionPanel> createState() => _ShowConnectionPanelState();
}

class _ShowConnectionPanelState extends State<ShowConnectionPanel> {
  Map<String, dynamic>? connection;
  List<dynamic> herds = [];
  Set<String> selected = {};
  bool busy = true;
  String? error, notice;
  @override
  void initState() {
    super.initState();
    action('status');
  }

  Future<Map<String, dynamic>> request(String name) async {
    if (widget.gateway != null) return widget.gateway!(name, selected.toList());
    if (name.startsWith('reports-')) {
      return ShowReportService.request(name.substring(8));
    }
    final response = await OfflineRuntime.client.functions.invoke(
      'show-connection',
      body: {'action': name, 'herd_ids': selected.toList()},
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    if (data['error'] != null) throw Exception(data['error']);
    return data;
  }

  Future<void> action(String name) async {
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      var result = await request(name);
      if (name == 'reports-enable') {
        if (mounted) setState(() => connection?['reports_enabled'] = true);
        result = await request('reports-refresh');
      }
      final data = name == 'status' || name == 'connect'
          ? result
          : await request('status');
      if (!mounted) return;
      setState(() {
        connection = data['connection'] == null
            ? null
            : Map<String, dynamic>.from(data['connection']);
        herds = data['herds'] ?? [];
        if (!name.startsWith('reports-')) {
          selected = Set<String>.from(connection?['herd_ids'] ?? []);
        }
        if (name == 'save' || name == 'sync') {
          notice = 'Refreshed ${result['count']} animals in Show.';
        }
        if (name == 'reports-enable' || name == 'reports-refresh') {
          notice =
              'Received ${result['reports'] ?? 0} reports and ${result['results'] ?? 0} show results.';
        }
        if (name == 'reports-disable') {
          notice = 'Report receiving stopped. Your received reports are kept.';
        }
        if (name == 'disconnect') {
          notice = 'Herd sharing stopped. Existing Show entries are preserved.';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e is FunctionException
              ? ((e.details is Map ? e.details['error'] : null)?.toString() ??
                    'Unable to connect. Please retry.')
              : e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'RingMaster Show',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      const Text(
        'Connect using the same verified email in both apps. Only active animals from the herds you select are shared; pedigree-only ancestors are excluded.',
      ),
      if (busy) const LinearProgressIndicator(),
      if (connection == null) ...[
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: busy ? null : () => action('connect'),
          icon: const Icon(Icons.link),
          label: const Text('Connect RingMaster Show'),
        ),
      ] else ...[
        const SizedBox(height: 12),
        Text(
          connection!['enabled'] == true
              ? 'Connected • Herd sharing enabled'
              : 'Account linked • Choose herds to share',
        ),
        for (final herd in herds)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(herd['name']),
            value: selected.contains(herd['id']),
            onChanged: busy
                ? null
                : (value) => setState(() {
                    if (value == true) {
                      selected.add(herd['id']);
                    } else {
                      selected.remove(herd['id']);
                    }
                  }),
          ),
        if (herds.isEmpty) const Text('Create a herd before enabling sharing.'),
        const Text(
          'Animals refresh when Show’s entry picker opens. Saved show entries keep their historical details. Breeder remains the source for linked animal details.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: busy ? null : () => action('save'),
              child: const Text('Save herd selection'),
            ),
            OutlinedButton(
              onPressed: busy ? null : () => action('sync'),
              child: const Text('Sync now'),
            ),
            TextButton(
              onPressed: busy ? null : () => action('disconnect'),
              child: const Text('Stop sharing'),
            ),
          ],
        ),
        if (connection!['last_synced_at'] != null)
          Text(
            'Last refreshed: ${DateTime.parse(connection!['last_synced_at']).toLocal()}',
          ),
        if (connection!['last_error'] != null) Text(connection!['last_error']),
      ],
      if (notice != null) Text(notice!),
      if (error != null) ...[
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        TextButton(
          onPressed: busy ? null : () => action('status'),
          child: const Text('Retry'),
        ),
      ],
      const Divider(),
      if (connection != null) ...[
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.calendar_month_outlined),
          title: Text('Entered shows on your calendar'),
          subtitle: Text(
            'Active show entries refresh automatically when you open or refresh the herd calendar.',
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Receive show reports'),
          subtitle: const Text(
            'Receive available exhibitor reports, ARBA leg PDFs and show results from your linked Show account. Reports refresh when you open Show reports.',
          ),
          value: connection!['reports_enabled'] == true,
          onChanged: busy
              ? null
              : (value) => action(value ? 'reports-enable' : 'reports-disable'),
        ),
        if (connection!['last_reports_synced_at'] != null)
          Text(
            'Reports refreshed: ${DateFormat('MM-dd-yy HH:mm').format(DateTime.parse(connection!['last_reports_synced_at']).toLocal())}',
          ),
        if (connection!['last_reports_error'] != null)
          Text(
            connection!['last_reports_error'],
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        Wrap(
          spacing: 12,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.description_outlined),
              label: const Text('Show reports'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ShowReportsScreen(ownAccount: true),
                ),
              ),
            ),
            if (connection!['reports_enabled'] == true)
              TextButton(
                onPressed: busy ? null : () => action('reports-refresh'),
                child: const Text('Refresh reports'),
              ),
          ],
        ),
      ] else
        const Text('Link your Show account to receive show reports.'),
    ],
  );
}
