import '../widgets/adaptive_layout.dart';
import '../offline/offline_runtime.dart';
import 'package:flutter/material.dart';
import '../widgets/ringmaster_page_shell.dart';
import '../utils/weight_date.dart';

Future<dynamic> supportView(
  String action, {
  String? owner,
  String? id,
  String query = '',
  int offset = 0,
}) async => OfflineRuntime.client.rpc(
  'breeder_support_view',
  params: {
    'p_action': action,
    'p_owner': owner,
    'p_id': id,
    'p_query': query,
    'p_offset': offset,
  },
);
String supportLabel(Map data) => [
  data['name'],
  data['tattoo'],
].where((v) => v != null && v.toString().trim().isNotEmpty).join(' • ');

class SuperAdminScreen extends StatefulWidget {
  const SuperAdminScreen({super.key});
  @override
  State<SuperAdminScreen> createState() => _SuperAdminScreenState();
}

class _SuperAdminScreenState extends State<SuperAdminScreen> {
  final query = TextEditingController();
  List<dynamic> users = [];
  bool busy = true, more = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> load({bool append = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final rows =
          await supportView(
                'search',
                query: query.text.trim(),
                offset: append ? users.length : 0,
              )
              as List;
      if (mounted) {
        setState(() {
          users = append ? [...users, ...rows] : rows;
          more = rows.length == 50;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          users = [];
          error = 'Unable to view accounts. Super-admin access is required.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    title: 'Super Admin',
    onRefresh: busy ? null : () => load(),
    body: ListView(
      padding: BreederLayout.pagePadding(context, normal: 24),
      children: [
        Text('View As User', style: Theme.of(context).textTheme.headlineSmall),
        const Text(
          'Find an account to inspect its herds and records. Support access is read-only and logged.',
        ),
        const AdaptiveGap(height: 20),
        TextField(
          controller: query,
          enabled: !busy,
          decoration: InputDecoration(
            labelText: 'Search name or email',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              onPressed: busy ? null : () => load(),
              icon: const Icon(Icons.arrow_forward),
            ),
          ),
          onSubmitted: (_) => load(),
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        if (!busy && error == null && users.isEmpty)
          const AdaptivePadding(
            padding: EdgeInsets.all(24),
            child: Text('No matching accounts.'),
          ),
        for (final u in users)
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(
                (u['display_name'] ?? '').toString().isEmpty
                    ? u['email']
                    : u['display_name'],
              ),
              subtitle: Text(
                '${u['email']} • ${u['herd_count']} herds${u['is_active'] == true ? '' : ' • Inactive'}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      SupportAccountScreen(owner: u['id'], label: u['email']),
                ),
              ),
            ),
          ),
        if (more)
          TextButton(
            onPressed: busy ? null : () => load(append: true),
            child: const Text('Load more accounts'),
          ),
      ],
    ),
  );
}

class SupportAccountScreen extends StatefulWidget {
  final String owner, label;
  final String? herd, animal;
  const SupportAccountScreen({
    super.key,
    required this.owner,
    required this.label,
    this.herd,
    this.animal,
  });
  @override
  State<SupportAccountScreen> createState() => _SupportAccountScreenState();
}

class _SupportAccountScreenState extends State<SupportAccountScreen> {
  dynamic data;
  bool busy = true, more = false;
  String? error;
  final query = TextEditingController();
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> load({bool append = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await supportView(
        widget.animal != null
            ? 'animal'
            : widget.herd != null
            ? 'animals'
            : 'account',
        owner: widget.owner,
        id: widget.animal ?? widget.herd,
        query: query.text.trim(),
        offset: append ? (data as List).length : 0,
      );
      if (mounted) {
        setState(() {
          data = append ? [...data, ...result] : result;
          more = result is List && result.length == 50;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          data = null;
          error = 'Unable to load this account. Access may have changed.';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String fieldLabel(String key) {
    final label = key.replaceAll('_', ' ');
    if (label == 'dob') return 'DOB';
    return label.isEmpty
        ? label
        : '${label[0].toUpperCase()}${label.substring(1)}';
  }

  Widget details(Map values) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final entry in values.entries)
        if (entry.value != null && entry.value.toString().isNotEmpty)
          AdaptivePadding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Text(
              '${fieldLabel(entry.key.toString())}: ${entry.value is bool ? (entry.value ? 'Yes' : 'No') : entry.value}',
            ),
          ),
    ],
  );
  Widget section(String title, Widget child) => Card(
    child: AdaptivePadding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const AdaptiveGap(height: 12),
          child,
        ],
      ),
    ),
  );
  void open({String? herd, String? animal}) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => SupportAccountScreen(
        owner: widget.owner,
        label: widget.label,
        herd: herd,
        animal: animal,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    title: 'View As User',
    onRefresh: busy ? null : () => load(),
    body: ListView(
      padding: BreederLayout.pagePadding(context, normal: 24),
      children: [
        Card(
          color: const Color(0xFFFFF1D6),
          child: ListTile(
            leading: const Icon(Icons.visibility_outlined),
            title: Text(widget.label),
            subtitle: const Text('Support view • Read-only'),
            trailing: TextButton(
              onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
              child: const Text('Exit'),
            ),
          ),
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        if (data != null && widget.herd == null && widget.animal == null) ...[
          section('Contact & address', details(data['profile'])),
          section(
            'Subscription',
            Column(
              children: [
                for (final p in data['subscriptions']) details(p),
                if ((data['subscriptions'] as List).isEmpty)
                  const Text('No subscription recorded.'),
              ],
            ),
          ),
          section(
            'Connected Show program',
            data['connection'] == null
                ? const Text('Not connected')
                : details(data['connection']),
          ),
          section(
            'Herds',
            Column(
              children: [
                for (final h in data['herds'])
                  ListTile(
                    title: Text(h['name']),
                    subtitle: Text('${h['animals']} animals'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => open(herd: h['id']),
                  ),
              ],
            ),
          ),
        ],
        if (widget.herd != null) ...[
          TextField(
            controller: query,
            enabled: !busy,
            decoration: InputDecoration(
              labelText: 'Search name, tattoo, or breed',
              suffixIcon: IconButton(
                onPressed: busy ? null : () => load(),
                icon: const Icon(Icons.search),
              ),
            ),
            onSubmitted: (_) => load(),
          ),
          if (data is List) ...[
            for (final a in data)
              Card(
                child: ListTile(
                  title: Text(supportLabel(a)),
                  subtitle: Text(
                    '${a['breed'] ?? ''} • ${a['variety'] ?? ''} • ${a['sex'] ?? ''}\n${a['status']}${a['pedigree_only'] == true ? ' • Pedigree only' : ''}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => open(animal: a['id']),
                ),
              ),
            if (more)
              TextButton(
                onPressed: busy ? null : () => load(append: true),
                child: const Text('Load more animals'),
              ),
          ],
        ],
        if (data != null && widget.animal != null) ...[
          section(
            supportLabel(data['animal']),
            details({
              for (final k in [
                'species',
                'breed',
                'variety',
                'sex',
                'dob',
                'status',
                'registration_number',
                'grand_champion_number',
                'legs',
                'leg_details',
                'notes',
              ])
                k.replaceAll('_', ' '): data['animal'][k],
              'Sire': data['sire'] == null ? null : supportLabel(data['sire']),
              'Dam': data['dam'] == null ? null : supportLabel(data['dam']),
            }),
          ),
          section(
            'Latest 100 weight records',
            Column(
              children: [
                for (final w in data['weights'])
                  ListTile(
                    title: Text('${w['weight']} lb'),
                    subtitle: Text(weightDate(w['recorded_at'])),
                  ),
              ],
            ),
          ),
          section(
            'Latest 100 health records',
            Column(children: [for (final h in data['health']) details(h)]),
          ),
        ],
      ],
    ),
  );
}
