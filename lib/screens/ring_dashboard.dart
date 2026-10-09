import '../widgets/ringmaster_page_shell.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/family_service.dart';
import '../services/license_service.dart';
import 'family_access_screen.dart';
import 'record_import_screen.dart';
import '../widgets/name_dialog.dart';

class RingDashboard extends StatefulWidget {
  final String userId;
  const RingDashboard({super.key, required this.userId});
  @override
  State<RingDashboard> createState() => _RingDashboardState();
}

class _RingDashboardState extends State<RingDashboard> {
  final _client = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _rings;
  LicenseStatus? _license;
  bool _checkedImport = false;
  @override
  void initState() {
    super.initState();
    _rings = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    await FamilyService.refresh();
    final owner = FamilyService.ownerId!;
    if (!_checkedImport) {
      _checkedImport = true;
      final own = FamilyService.households.firstWhere(
        (h) => h['is_owner'] == true,
      )['owner_user_id'];
      final profiles = await _client
          .from('breeder_exhibitor_profiles')
          .select('id')
          .eq('owner_id', own)
          .limit(1);
      if (profiles.isEmpty) {
        try {
          final lookup = Map<String, dynamic>.from(
            (await _client.functions.invoke(
                  'import-ringmaster-records',
                  body: {'action': 'lookup'},
                )).data
                as Map,
          );
          if (mounted && (lookup['matches'] as List? ?? []).isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => RecordImportScreen(initialLookup: lookup),
                  ),
                );
              }
            });
          }
        } catch (_) {
          /* Optional import remains available from the dashboard. */
        }
      }
    }
    _license = await fetchLicenseStatus(owner);
    final rings = await _client
        .from('farms')
        .select()
        .eq('owner_id', owner)
        .order('created_at');
    return List<Map<String, dynamic>>.from(rings);
  }

  void _refresh() {
    setState(() => _rings = _load());
  }

  Future<void> _createRing() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) =>
          const NameDialog(title: 'Create Ring', label: 'Ring name'),
    );
    if (name == null || !mounted) return;
    try {
      await _client.rpc(
        'create_breeder_ring',
        params: {'p_name': name, 'p_owner_id': FamilyService.ownerId},
      );
      if (mounted) _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to create Ring. Check your license and try again.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    title: 'My Rings',
    actions: [
      IconButton(
        tooltip: 'Import RingMaster records',
        icon: const Icon(Icons.download),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const RecordImportScreen()),
          );
          if (mounted) _refresh();
        },
      ),
      IconButton(
        tooltip: 'Imported profiles and show history',
        icon: const Icon(Icons.emoji_events_outlined),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => const ImportedRecordsScreen(),
          ),
        ),
      ),
      IconButton(
        tooltip: 'Family access',
        icon: const Icon(Icons.group),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const FamilyAccessScreen()),
          );
          if (mounted) _refresh();
        },
      ),
      IconButton(
        tooltip: 'Refresh Rings',
        icon: const Icon(Icons.refresh),
        onPressed: _refresh,
      ),
      IconButton(
        tooltip: 'Sign out',
        icon: const Icon(Icons.logout),
        onPressed: () async {
          try {
            await _client.auth.signOut();
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Unable to sign out. Please try again.'),
                ),
              );
            }
          }
        },
      ),
    ],
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _rings,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Unable to load your Rings.'),
                TextButton(onPressed: _refresh, child: const Text('Try again')),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rings = snapshot.data!;
        final canCreate =
            _license!.hasActiveLicense &&
            _license!.currentRings < _license!.maxRings;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Your rabbitry, together',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: FamilyService.ownerId,
              decoration: const InputDecoration(labelText: 'Family'),
              items: FamilyService.households
                  .map(
                    (h) => DropdownMenuItem<String>(
                      value: h['owner_user_id'],
                      child: Text(h['label']),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  FamilyService.select(value);
                  _refresh();
                }
              },
            ),
            const SizedBox(height: 16),
            if (!_license!.hasActiveLicense)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'This family has no active Breeder license. Existing records remain available.',
                  ),
                ),
              ),
            if (rings.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No Rings yet.'),
              ),
            ...rings.map(
              (ring) => Card(
                child: ListTile(
                  leading: const Icon(Icons.pets),
                  title: Text(ring['name']),
                  subtitle: Text(
                    FamilyService.households.any(
                          (h) =>
                              h['owner_user_id'] == FamilyService.ownerId &&
                              h['is_owner'] == true,
                        )
                        ? 'Your Ring'
                        : 'Shared family Ring',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pushNamed(
                    context,
                    '/animals',
                    arguments: {'ringId': ring['id'], 'ringName': ring['name']},
                  ),
                ),
              ),
            ),
            if (canCreate)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: ElevatedButton.icon(
                  onPressed: _createRing,
                  icon: const Icon(Icons.add),
                  label: const Text('Create Ring'),
                ),
              ),
          ],
        );
      },
    ),
  );
}
