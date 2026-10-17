import '../widgets/adaptive_layout.dart';
import '../offline/offline_runtime.dart';
import 'package:flutter/material.dart';
import '../services/global_pedigree_import_service.dart';
import '../widgets/ringmaster_page_shell.dart';

class GlobalPedigreeImportScreen extends StatefulWidget {
  final GlobalPedigreeImportGateway? gateway;
  const GlobalPedigreeImportScreen({super.key, this.gateway});

  @override
  State<GlobalPedigreeImportScreen> createState() =>
      _GlobalPedigreeImportScreenState();
}

class _GlobalPedigreeImportScreenState
    extends State<GlobalPedigreeImportScreen> {
  late final _gateway =
      widget.gateway ?? GlobalPedigreeImportService(OfflineRuntime.client);
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  List<Map<String, dynamic>> _herds = [];
  String? _herd, _error;
  Map<String, dynamic>? _data, _review, _result;
  bool _loading = true, _busy = false;
  final Set<String> _unknownSex = {};
  List<List<Map<String, dynamic>>> _duplicates = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final herds = await _gateway.ownedHerds();
      if (!mounted) return;
      setState(() {
        _herds = herds;
        _herd = herds.isEmpty ? null : herds.first['id'] as String;
      });
      final draft = await _gateway.pendingDraft();
      if (!mounted) return;
      if (draft != null && herds.any((h) => h['id'] == draft['ring_id'])) {
        _herd = draft['ring_id'] as String;
        _data = {
          'account': draft['account'],
          'history': draft['history'] ?? [],
          'history_complete': draft['history_complete'] == true,
          'sales_complete': draft['sales_complete'] == true,
          'animals': (draft['animals'] as List)
              .map((a) => Map<String, dynamic>.from(a as Map))
              .toList(),
        };
        _unknownSex.clear();
        for (final animal in _data!['animals'] as List) {
          if (animal['sex'] != 'Buck' && animal['sex'] != 'Doe') {
            _unknownSex.add(animal['source_id'].toString());
          }
        }
        final review = await _gateway.review(_herd!, _data!);
        if (mounted) setState(() => _applyReview(review));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Unable to load your herds. Try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on StateError catch (e) {
      if (mounted) setState(() => _error = e.message.toString());
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Unable to complete this step. Your import can be retried safely.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _collect() async {
    if (!_form.currentState!.validate() || _herd == null) return;
    await _run(() async {
      Map<String, dynamic> data;
      try {
        data = await _gateway.collect(_username.text.trim(), _password.text);
        data = {
          ...data,
          'animals': (data['animals'] as List)
              .map((a) => Map<String, dynamic>.from(a as Map))
              .toList(),
        };
      } finally {
        if (mounted) _password.clear();
      }
      if (!mounted) return;
      setState(() {
        _data = data;
        _unknownSex.clear();
        for (final animal in data['animals'] as List) {
          if (animal['sex'] != 'Buck' && animal['sex'] != 'Doe') {
            _unknownSex.add(animal['source_id'].toString());
          }
        }
        _review = null;
        _duplicates = [];
      });
      final review = await _gateway.review(_herd!, data);
      if (mounted) setState(() => _applyReview(review));
    });
  }

  Future<void> _preview() => _run(() async {
    final review = await _gateway.review(_herd!, _data!);
    if (mounted) setState(() => _applyReview(review));
  });

  void _applyReview(Map<String, dynamic> review) {
    _review = review;
    _duplicates = (review['duplicate_groups'] as List? ?? [])
        .map(
          (g) => (g as List)
              .map((a) => Map<String, dynamic>.from(a as Map))
              .toList(),
        )
        .toList();
  }

  void _chooseDuplicate(List<Map<String, dynamic>> group, String? choice) {
    if (choice == null) return;
    final ids = group.map((a) => a['source_id'].toString()).toSet();
    final animals = (_data!['animals'] as List).cast<Map>();
    for (final animal in animals.where(
      (a) => ids.contains(a['source_id'].toString()),
    )) {
      animal.remove('same_as');
      animal['keep_separate'] = true;
      if (choice != 'separate' && animal['source_id'].toString() != choice) {
        animal['same_as'] = choice;
      }
    }
    _review = null;
  }

  String? _duplicateChoice(List<Map<String, dynamic>> group) {
    final ids = group.map((a) => a['source_id'].toString()).toSet();
    final animals = (_data!['animals'] as List)
        .cast<Map>()
        .where((a) => ids.contains(a['source_id'].toString()))
        .toList();
    for (final animal in animals) {
      if (animal['same_as'] != null) return animal['same_as'].toString();
    }
    return animals.every((a) => a['keep_separate'] == true) ? 'separate' : null;
  }

  String _dobLabel(Map record) {
    final date = record['dob']?.toString() ?? '';
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(date);
    return match == null
        ? 'DOB unknown'
        : 'DOB ${match[2]}/${match[3]}/${match[1]}';
  }

  String _parentLabel(Map record, String side) {
    final id = record[side]?.toString();
    if (id == null || id.isEmpty) return 'Unknown';
    for (final parent in (_data!['animals'] as List).cast<Map>()) {
      if (parent['source_id'].toString() == id) {
        final ear = parent['tattoo']?.toString().trim() ?? '';
        final name = parent['name']?.toString().trim() ?? '';
        return [
          ear.isEmpty ? 'Ear number unknown' : ear,
          if (name.isNotEmpty) name,
        ].join(' • ');
      }
    }
    return 'Parent record unavailable';
  }

  String _sexEvidence(Map record) {
    final id = record['source_id'].toString();
    final animals = (_data!['animals'] as List).cast<Map>();
    final sires = animals.where((a) => a['sire_id']?.toString() == id).length;
    final dams = animals.where((a) => a['dam_id']?.toString() == id).length;
    if (sires > 0 && dams > 0) {
      return 'Listed as both sire and dam. Check the source before choosing.';
    }
    if (sires > 0) {
      return 'Listed as sire of $sires records — suggests Buck. Please confirm.';
    }
    if (dams > 0) {
      return 'Listed as dam of $dams records — suggests Doe. Please confirm.';
    }
    return 'No sex or parent-role evidence was collected.';
  }

  Future<void> _save() => _run(() async {
    final result = await _gateway.save(_herd!, _data!);
    if (result['status'] != 'imported') {
      if (mounted) setState(() => _review = result);
      throw const FormatException(
        'Resolve the listed conflicts before importing.',
      );
    }
    if (mounted) {
      setState(() {
        _result = result;
        _data = null;
        _review = null;
      });
    }
  });

  @override
  Widget build(BuildContext context) {
    final issues = (_review?['issues'] as List? ?? []).cast<String>();
    final rows = (_review?['rows'] as List? ?? []).cast<Map>();
    return PopScope(
      canPop: !_busy,
      child: RingMasterPageShell(
        title: 'Global Pedigree import',
        showAccountButton: false,
        showHomeButton: !_busy,
        showBackButton: !_busy,
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: BreederLayout.pagePadding(context, normal: 24),
                children: [
                  const Text(
                    'Bring your rabbits and pedigrees into Breeder',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const AdaptiveGap(height: 12),
                  const Text(
                    'Sign in to Global Pedigree, choose a destination herd, '
                    'and review your rabbits and ancestors before importing. '
                    'Your Global Pedigree records will remain unchanged.',
                  ),
                  const AdaptiveGap(height: 12),
                  const Text(
                    'Your login is used only to read your records during '
                    'this import. Your password is not saved. Your collected '
                    'preview is saved privately for 24 hours so you can resume.',
                  ),
                  const AdaptiveGap(height: 24),
                  if (_herds.isEmpty) ...[
                    const Text('Create a herd in Breeder before importing.'),
                    TextButton(
                      onPressed: _busy ? null : _load,
                      child: const Text('Reload herds'),
                    ),
                  ] else if (_result == null) ...[
                    DropdownButtonFormField<String>(
                      initialValue: _herd,
                      decoration: const InputDecoration(
                        labelText: 'Destination herd',
                      ),
                      items: [
                        for (final herd in _herds)
                          DropdownMenuItem(
                            value: herd['id'] as String,
                            child: Text(herd['name'] as String),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) => setState(() {
                              _herd = value;
                              _review = null;
                            }),
                    ),
                    const AdaptiveGap(height: 24),
                    if (_data == null)
                      Form(
                        key: _form,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _username,
                              enabled: !_busy,
                              autocorrect: false,
                              decoration: const InputDecoration(
                                labelText: 'Global Pedigree username or email',
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Enter your username or email.'
                                  : null,
                            ),
                            const AdaptiveGap(height: 16),
                            TextFormField(
                              controller: _password,
                              enabled: !_busy,
                              obscureText: true,
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: const InputDecoration(
                                labelText: 'Global Pedigree password',
                              ),
                              validator: (v) => v == null || v.isEmpty
                                  ? 'Enter your password.'
                                  : null,
                            ),
                            const AdaptiveGap(height: 20),
                            FilledButton.icon(
                              onPressed: _busy ? null : _collect,
                              icon: const Icon(Icons.travel_explore),
                              label: Text(
                                _busy
                                    ? 'Reading records…'
                                    : 'Connect and preview',
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      Text(
                        '${(_data!['animals'] as List).length} rabbits and ancestors collected.',
                      ),
                      Text(
                        '${(_data!['history'] as List? ?? []).where((r) => r['kind'] == 'litter').length} litter and breeding records; ${(_data!['history'] as List? ?? []).where((r) => r['kind'] == 'weight').length} dated weights; ${(_data!['history'] as List? ?? []).where((r) => r['kind'] == 'sale').length} historical sales collected.',
                      ),
                      if ((_data!['history'] as List? ?? []).any(
                        (r) => r['kind'] == 'sale',
                      ))
                        const Text(
                          'Historical sales preserve recorded prices and blank buyers. Payment history is not recorded.',
                        ),
                      const Text(
                        'Individual show results are not available on the inspected Global Pedigree pages. Show-leg totals are included with rabbit details.',
                      ),
                      for (final warning
                          in (_review?['history_warnings'] as List? ?? []))
                        Text(
                          warning.toString(),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      if (_unknownSex.isNotEmpty) ...[
                        const AdaptiveGap(height: 16),
                        const Text(
                          'Choose the sex for records marked unknown in Global Pedigree, then review again.',
                        ),
                        for (final animal
                            in (_data!['animals'] as List).cast<Map>().where(
                              (a) => _unknownSex.contains(
                                a['source_id'].toString(),
                              ),
                            ))
                          AdaptivePadding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: DropdownButtonFormField<String>(
                              key: ValueKey('sex-${animal['source_id']}'),
                              initialValue:
                                  animal['sex'] == 'Buck' ||
                                      animal['sex'] == 'Doe'
                                  ? animal['sex'] as String
                                  : null,
                              decoration: InputDecoration(
                                labelText:
                                    '${animal['name']} • ${_dobLabel(animal)} — sex',
                                helperText: _sexEvidence(animal),
                                helperMaxLines: 3,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'Buck',
                                  child: Text('Buck'),
                                ),
                                DropdownMenuItem(
                                  value: 'Doe',
                                  child: Text('Doe'),
                                ),
                              ],
                              onChanged: _busy
                                  ? null
                                  : (value) => setState(() {
                                      animal['sex'] = value;
                                      _review = null;
                                    }),
                            ),
                          ),
                      ],
                      for (final group in _duplicates)
                        Card(
                          child: AdaptivePadding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Possible duplicate: ${group.first['name']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Text(
                                  'A shared name and ear number is a suggestion. Choose whether these are separate rabbits or the same animal.',
                                ),
                                for (final record in group)
                                  ExpansionTile(
                                    title: Text(
                                      '${_dobLabel(record)} • ${record['status'] ?? 'active'} • Record ${record['source_id']}',
                                    ),
                                    children: [
                                      AdaptivePadding(
                                        padding: const EdgeInsets.all(8),
                                        child: Text(
                                          [
                                            'Ear number: ${record['tattoo'] ?? 'Unknown'}',
                                            'Breed: ${record['breed'] ?? 'Unknown'}',
                                            'Sex: ${record['sex'] ?? 'Unknown'}',
                                            'Sire ear number: ${_parentLabel(record, 'sire_id')}',
                                            'Dam ear number: ${_parentLabel(record, 'dam_id')}',
                                            'Weight: ${record['weight'] ?? 'Unknown'}',
                                            'Notes: ${record['notes'] ?? 'None'}',
                                          ].join('\n'),
                                        ),
                                      ),
                                    ],
                                  ),
                                DropdownButtonFormField<String>(
                                  key: ValueKey(
                                    'duplicates-${group.first['source_id']}',
                                  ),
                                  initialValue: _duplicateChoice(group),
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Duplicate decision',
                                  ),
                                  items: [
                                    const DropdownMenuItem(
                                      value: 'separate',
                                      child: Text('Keep as separate rabbits'),
                                    ),
                                    for (final record in group)
                                      DropdownMenuItem(
                                        value: record['source_id'].toString(),
                                        child: Text(
                                          'Keep record ${record['source_id']} and merge ${group.length == 2 ? 'the other record' : 'the other records'} • ${_dobLabel(record)}',
                                          maxLines: 2,
                                        ),
                                      ),
                                  ],
                                  onChanged: _busy
                                      ? null
                                      : (choice) => setState(
                                          () => _chooseDuplicate(group, choice),
                                        ),
                                ),
                                const Text(
                                  'For the same animal, the selected record supplies its dates, parents, notes, and weight. A rabbit is active if any merged source record is in the live herd. The other records are merged into it, and all pedigree links and source IDs are retained.',
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_review == null)
                        FilledButton(
                          onPressed: _busy ? null : _preview,
                          child: const Text('Review import'),
                        ),
                      if (_review != null) ...[
                        const AdaptiveGap(height: 16),
                        Text(
                          '${_review!['animals_added'] ?? 0} new records • '
                          '${_review!['animals_existing'] ?? 0} existing records',
                        ),
                        if ((_review!['aliases'] as Map? ?? {}).isNotEmpty)
                          Text(
                            '${(_review!["aliases"] as Map).length} duplicate source records linked to the selected animals.',
                          ),
                        const Text(
                          'Existing animals are preserved. Ancestors that are '
                          'not in your herd are added as pedigree-only records.',
                        ),
                        for (final issue in issues)
                          AdaptivePadding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              issue,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        for (final row in rows)
                          Card(
                            child: ListTile(
                              title: Text(
                                (row['name'] ?? row['source_id']).toString(),
                              ),
                              subtitle: Text(
                                [
                                      row['tattoo'],
                                      row['sex'],
                                      row['breed'],
                                      row['pedigree_only'] == true
                                          ? 'Ancestor'
                                          : 'Herd rabbit',
                                      row['action'],
                                    ]
                                    .where((v) => v != null && v != '')
                                    .join(' • '),
                              ),
                            ),
                          ),
                        const AdaptiveGap(height: 16),
                        FilledButton.icon(
                          onPressed: _busy || issues.isNotEmpty || rows.isEmpty
                              ? null
                              : _save,
                          icon: const Icon(Icons.download_outlined),
                          label: Text(
                            _busy ? 'Importing…' : 'Import into herd',
                          ),
                        ),
                      ],
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _run(() async {
                                await _gateway.discardDraft();
                                if (!mounted) return;
                                setState(() {
                                  _data = null;
                                  _review = null;
                                  _duplicates = [];
                                });
                              }),
                        child: const Text(
                          'Use another Global Pedigree account',
                        ),
                      ),
                    ],
                  ],
                  if (_busy)
                    const AdaptivePadding(
                      padding: EdgeInsets.all(16),
                      child: LinearProgressIndicator(),
                    ),
                  if (_error != null)
                    Semantics(
                      liveRegion: true,
                      child: AdaptivePadding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(_error!),
                      ),
                    ),
                  if (_result != null) ...[
                    const Text(
                      'Import complete',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${_result!['animals_added']} new records imported. '
                      '${_result!['animals_existing']} existing records preserved.',
                    ),
                    if ((_result!['sales_added'] ?? 0) > 0 ||
                        (_result!['sales_existing'] ?? 0) > 0)
                      Text(
                        '${_result!['sales_added']} historical sales imported; ${_result!['sales_existing']} existing sales preserved.',
                      ),
                    const AdaptiveGap(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Done'),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
