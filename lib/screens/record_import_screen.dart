import '../widgets/ringmaster_page_shell.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/family_service.dart';
import '../services/record_import_service.dart';

class RecordImportScreen extends StatefulWidget {
  final Map<String, dynamic>? initialLookup;
  final RecordImportGateway? gateway;
  const RecordImportScreen({super.key, this.initialLookup, this.gateway});
  @override
  State<RecordImportScreen> createState() => _RecordImportScreenState();
}

class _RecordImportScreenState extends State<RecordImportScreen> {
  late final RecordImportGateway _gateway =
      widget.gateway ?? RecordImportService(Supabase.instance.client);
  List<Map<String, dynamic>> _matches = [];
  List<Map<String, dynamic>> _rings = [];
  final _selected = <String>{};
  String _source = 'show';
  String? _ring;
  String? _message;
  bool _loading = true, _busy = false, _animals = false, _entries = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rings = await _gateway.ownedRings();
      final data = widget.initialLookup ?? await _gateway.lookup();
      if (!mounted) return;
      setState(() {
        _matches = List<Map<String, dynamic>>.from(
          data['matches'] as List? ?? [],
        );
        _rings = List<Map<String, dynamic>>.from(rings);
        _ring = _rings.isEmpty ? null : _rings.first['id'];
        if (!_matches.any((p) => p['source'] == 'show')) _source = 'club';
        if (_matches.isEmpty) {
          _message =
              'No matching Show or Club profiles were found for your verified email.';
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _message =
              'Unable to check your other RingMaster accounts. Please try again later.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final data = await _gateway.importRecords({
        'source': _source,
        'profile_ids': _selected.toList(),
        'include_animals': _source == 'show' && _animals && _ring != null,
        'include_entries': _source == 'show' && _entries,
        'ring_id': _ring,
      });
      if (data['status'] != 'imported') {
        throw StateError('Import not completed');
      }
      if (!mounted) return;
      setState(() => _selected.clear());
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Import successful'),
          content: SingleChildScrollView(
            child: Text(
              '${data['profiles_selected'] ?? 0} profiles selected\n'
              '${data['animals_added'] ?? 0} new animals imported\n'
              '${data['entries_added'] ?? 0} show-entry records imported\n\n'
              'Existing records were preserved.'
              '${(data['results_unmatched'] as num? ?? 0) > 0 ? '\n\n${data['results_unmatched']} results could not be linked to an animal and were kept for review.' : ''}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Import could not be completed. Check your Ring and selected records, then try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    title: 'Import RingMaster records',
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Bring your existing records into Breeder',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'Choose the profiles that belong to you. Matching uses your verified login email. Imports copy records and leave Show and Club unchanged.',
              ),
              const SizedBox(height: 20),
              if (_matches.isNotEmpty) ...[
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'show', label: Text('Show')),
                    ButtonSegment(value: 'club', label: Text('Club')),
                  ],
                  selected: {_source},
                  onSelectionChanged: _busy
                      ? null
                      : (v) => setState(() {
                          _source = v.single;
                          _selected.clear();
                        }),
                ),
                ..._matches
                    .where((p) => p['source'] == _source)
                    .map(
                      (p) => CheckboxListTile(
                        value: _selected.contains(p['id']),
                        title: Text(
                          (p['display_name'] ??
                                  p['showing_name'] ??
                                  'Exhibitor')
                              .toString(),
                        ),
                        subtitle: Text(
                          [
                            p['city'],
                            p['state'],
                          ].whereType<String>().join(', '),
                        ),
                        onChanged: _busy
                            ? null
                            : (v) => setState(() {
                                if (v == true) {
                                  _selected.add(p['id']);
                                } else {
                                  _selected.remove(p['id']);
                                }
                              }),
                      ),
                    ),
                if (_source == 'show') ...[
                  const Divider(),
                  if (!_animals && _entries)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Results only — no animal records will be created or changed.',
                      ),
                    ),
                  CheckboxListTile(
                    title: const Text('Also import animals'),
                    subtitle: const Text(
                      'Leave this off if your animals are already in Breeder or will come from another breeder program.',
                    ),
                    value: _animals && _ring != null,
                    onChanged: _busy || _ring == null
                        ? null
                        : (v) => setState(() => _animals = v!),
                  ),
                  if (_rings.isEmpty)
                    const Text(
                      'Create a Ring first to import animals. You can import profiles and show history now, then return for animals.',
                    ),
                  if (_rings.isNotEmpty && _animals)
                    DropdownButtonFormField<String>(
                      initialValue: _ring,
                      decoration: const InputDecoration(
                        labelText: 'Import animals into your Ring',
                      ),
                      items: _rings
                          .map(
                            (r) => DropdownMenuItem<String>(
                              value: r['id'],
                              child: Text(r['name']),
                            ),
                          )
                          .toList(),
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _ring = v),
                    ),
                  CheckboxListTile(
                    title: const Text('Import show entries and results'),
                    subtitle: const Text(
                      'History remains linked to its original show and exhibitor. Payments and show administration remain in Show.',
                    ),
                    value: _entries,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _entries = v!),
                  ),
                ] else
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Club supplies exhibitor profiles. Animal and individual show-entry records come from Show.',
                    ),
                  ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _busy || _selected.isEmpty ? null : _import,
                  icon: const Icon(Icons.download),
                  label: Text(_busy ? 'Importing…' : 'Import selected records'),
                ),
              ],
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Semantics(liveRegion: true, child: Text(_message!)),
                ),
            ],
          ),
  );
}

class ImportedRecordsScreen extends StatelessWidget {
  const ImportedRecordsScreen({super.key});
  Future<List<Map<String, dynamic>>> _records() async {
    final client = Supabase.instance.client;
    final profiles = await client
        .from('breeder_exhibitor_profiles')
        .select()
        .eq('owner_id', FamilyService.ownerId!)
        .order('imported_at');
    final entries = await client
        .from('breeder_show_history')
        .select()
        .eq('owner_id', FamilyService.ownerId!)
        .order('imported_at');
    return [
      ...profiles.map((r) => {...r, 'kind': 'profile'}),
      ...entries.map((r) => {...r, 'kind': 'entry'}),
    ];
  }

  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    title: 'Imported profiles and show history',
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _records(),
      builder: (context, s) {
        if (s.hasError) {
          return const Center(child: Text('Unable to load imported records.'));
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        if (s.data!.isEmpty) {
          return const Center(child: Text('No imported records yet.'));
        }
        return ListView(
          padding: const EdgeInsets.all(24),
          children: s.data!.map((r) {
            final profile = r['kind'] == 'profile';
            final data = Map<String, dynamic>.from(
              (profile ? r['profile'] : r['record']) as Map,
            );
            final show = data['shows'] is Map
                ? Map<String, dynamic>.from(data['shows'] as Map)
                : <String, dynamic>{};
            return Card(
              child: ListTile(
                leading: Icon(profile ? Icons.person : Icons.emoji_events),
                title: Text(
                  (profile
                          ? data['display_name'] ??
                                data['showing_name'] ??
                                'Exhibitor'
                          : show['name'] ?? 'Show entry')
                      .toString(),
                ),
                subtitle: Text(
                  profile
                      ? [
                          data['email'],
                          data['phone'],
                          data['city'],
                          data['state'],
                        ].whereType<String>().join(' • ')
                      : [
                              show['start_date'],
                              data['tattoo'],
                              data['breed'],
                              data['class_name'],
                              data['placement'],
                              data['special_awards'],
                            ]
                            .whereType<String>()
                            .where((v) => v.isNotEmpty)
                            .join(' • '),
                ),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text(
                      profile ? 'Profile details' : 'Show-entry details',
                    ),
                    content: SingleChildScrollView(
                      child: Text(
                        data.entries
                            .where((e) => e.value != null)
                            .map(
                              (e) =>
                                  '${e.key.replaceAll('_', ' ')}: ${e.value}',
                            )
                            .join('\n'),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    ),
  );
}
