import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../imports/kintraks_csv.dart';
import '../offline/offline_runtime.dart';
import '../services/kintraks_import_service.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/ringmaster_page_shell.dart';
import 'kintraks_history_screen.dart';

class KintraksImportScreen extends StatefulWidget {
  final KintraksImportGateway? gateway;
  final Future<({String name, Uint8List bytes})?> Function()? pickFile;
  const KintraksImportScreen({super.key, this.gateway, this.pickFile});
  @override
  State<KintraksImportScreen> createState() => _KintraksImportScreenState();
}

class _KintraksImportScreenState extends State<KintraksImportScreen> {
  late final _gateway =
      widget.gateway ?? KintraksImportService(OfflineRuntime.client);
  final _source = TextEditingController();
  List<Map<String, dynamic>> _herds = [];
  List<String> _sources = [];
  String? _herd, _filename, _error;
  KintraksExport? _export;
  Map<String, dynamic>? _review, _result;
  final Map<String, String> _sexes = {}, _matches = {};
  final Set<String> _omittedParents = {}, _activeIds = {};
  String _animalSearch = '', _editSearch = '';
  final Map<String, Map<String, String>> _edits = {};
  int _fileRevision = 0;
  bool _busy = true, _ack = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  Future<void> _load() => _run(() async {
    final herds = await _gateway.ownedHerds();
    if (!mounted) return;
    setState(() {
      _herds = herds;
      _herd = herds.isEmpty ? null : herds.first['id'] as String;
    });
    if (_herd != null) await _loadSources();
  });
  Future<void> _loadSources() async {
    final sources = await _gateway.sources(_herd!);
    if (mounted) setState(() => _sources = sources);
  }

  void _reportError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on FormatException catch (e) {
      _reportError(e.message);
    } on PostgrestException catch (e) {
      _reportError(
        ['PGRST202', '42P01'].contains(e.code)
            ? 'Kintraks import is not available on this server yet.'
            : 'The server could not complete the import. Check herd access and retry; the import saves atomically.',
      );
    } catch (_) {
      _reportError(
        'Unable to complete this step. Reconnect and retry with the same source name; retries preserve existing records.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _invalidate() => _review = null;
  Future<void> _pick() => _run(() async {
    setState(_invalidate);
    final file = await (widget.pickFile?.call() ?? _pickPlatformFile());
    if (file == null || !mounted) return;
    final parsed = KintraksExport.parse(file.bytes);
    setState(() {
      _filename = file.name;
      _export = parsed;
      _sexes.clear();
      _omittedParents.clear();
      _activeIds.clear();
      _animalSearch = '';
      _editSearch = '';
      _edits.clear();
      _fileRevision++;
      _matches.clear();
      _ack = false;
      _review = null;
      _result = null;
    });
  });
  Future<({String name, Uint8List bytes})?> _pickPlatformFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null) return null;
    final file = result.files.single;
    if (file.size > KintraksExport.maxBytes) {
      throw const FormatException('Select a CSV file smaller than 10 MB.');
    }
    if (file.bytes == null) {
      throw const FormatException('Unable to read this file. Choose it again.');
    }
    return (name: file.name, bytes: file.bytes!);
  }

  Map<String, dynamic> _payload() => _export!.payload(
    sexes: _sexes,
    matches: _matches,
    acknowledged: _ack,
    omittedParents: _omittedParents,
    activeIds: _activeIds,
  );
  Future<void> _preview() => _run(() async {
    final result = await _gateway.run(_herd!, _source.text.trim(), _payload());
    if (mounted) setState(() => _review = result);
  });
  Future<void> _save() => _run(() async {
    final result = await _gateway.run(
      _herd!,
      _source.text.trim(),
      _payload(),
      commit: true,
    );
    if (!mounted) return;
    setState(() {
      if (result['status'] == 'imported') {
        _result = result;
        _review = null;
      } else {
        _review = result;
      }
    });
  });
  Widget _panel(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 20),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final export = _export;
    final issues = _review?['issues'] as List? ?? [];
    final parentProblems = export?.parentProblems(_sexes) ?? [];
    return RingMasterPageShell(
      title: 'Import from Kintraks',
      body: ListView(
        padding: BreederLayout.pagePadding(context, normal: 24),
        children: [
          _panel('Export your records from Kintraks', [
            const Text('1. Open the database you want to export in Kintraks.'),
            const SizedBox(height: 12),
            const Text('2. Open Database → Export Records.'),
            const SizedBox(height: 12),
            const Text(
              '3. Select All records to include your rabbits and pedigree ancestors.',
            ),
            const SizedBox(height: 12),
            const Text(
              '4. Set CSV delimiter to Comma and CSV wrap text to Double Quotes.',
            ),
            const SizedBox(height: 12),
            const Text(
              '5. Click CSV file and save the .csv file somewhere you can find it.',
            ),
            const SizedBox(height: 12),
            const Text('6. Return here and choose that file in Step 1 below.'),
            const SizedBox(height: 20),
            const Text(
              'Use the CSV export, rather than the .cax backup file. You can review and correct the records before importing. Preview and saving require an internet connection.',
            ),
          ]),
          if (_error != null) ...[
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 20),
          ],
          if (_busy) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 20),
          ],
          if (_result != null)
            _panel('Import complete', [
              Text(
                '${_result!['animals_added']} new rabbits, ${_result!['animals_existing']} existing rabbits preserved, ${_result!['history_added']} new source history records.',
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => KintraksHistoryScreen(ringId: _herd),
                  ),
                ),
                child: const Text('View Kintraks history'),
              ),
            ])
          else ...[
            _panel('1. Choose your export', [
              if (_herds.isEmpty && !_busy) ...[
                const Text(
                  'Create a personally owned, non-demo herd before importing.',
                ),
                const SizedBox(height: 16),
              ],
              DropdownButtonFormField<String>(
                key: ValueKey(_herd),
                initialValue: _herd,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Destination herd',
                ),
                items: [
                  for (final h in _herds)
                    DropdownMenuItem(
                      value: h['id'] as String,
                      child: Text(h['name'] as String),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => _run(() async {
                        setState(() {
                          _herd = value;
                          _source.clear();
                          _sources = [];
                          _matches.clear();
                          _invalidate();
                        });
                        await _loadSources();
                      }),
              ),
              const SizedBox(height: 24),
              if (_sources.isNotEmpty) ...[
                const Text('Previously imported sources'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final source in _sources)
                      ActionChip(
                        label: Text(source),
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _source.text = source;
                                _matches.clear();
                                _invalidate();
                              }),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
              TextField(
                controller: _source,
                enabled: !_busy,
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Source database name',
                  hintText: 'Example: Hunter Kintraks',
                ),
                onChanged: (_) => setState(() {
                  _matches.clear();
                  _invalidate();
                }),
              ),
              const SizedBox(height: 8),
              const Text(
                'Reuse this name for later exports of this database. Give another breeder’s database a different name.',
              ),
              const SizedBox(height: 20),
              const Text(
                'Kintraks CSV weights use pounds and ounces: 3.13 means 3 lb 13 oz. Breeder converts these to pounds automatically and preserves the original text.',
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.upload_file),
                label: const Text('Choose Kintraks CSV'),
              ),
              if (_filename != null) ...[
                const SizedBox(height: 12),
                Text(_filename!),
              ],
            ]),
            if (export != null) ...[
              _panel('2. Review source data', [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    for (final entry in const {'Animals': 'Rabbits'}.entries)
                      Chip(
                        label: Text(
                          '${entry.value}: ${export.counts[entry.key] ?? 0}',
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '${_activeIds.length} selected for current herd • ${export.animals.length - _activeIds.length} historical rabbits',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Different Kintraks IDs remain separate unless you explicitly link them to an existing rabbit. Missing parents are not invented.',
                ),
                const SizedBox(height: 20),
                ExpansionTile(
                  title: Text('Source warnings (${export.warnings.length})'),
                  initiallyExpanded: true,
                  tilePadding: EdgeInsets.zero,
                  children: [
                    for (final warning in export.warnings)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(warning),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                ExpansionTile(
                  key: ValueKey('edit-rabbits-$_fileRevision'),
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    'Review and edit rabbits (${_edits.length} corrected)',
                  ),
                  subtitle: const Text(
                    'Correct dates, breeds, parent IDs, weights, and any other CSV fields before preview.',
                  ),
                  children: [
                    const Text(
                      'Original CSV values remain in history. Corrections apply to this import and do not overwrite existing animals.',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const ValueKey('edit-search'),
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText:
                            'Find a rabbit by name, ear number, or source ID',
                      ),
                      onChanged: (v) =>
                          setState(() => _editSearch = v.trim().toLowerCase()),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 300,
                      child: Builder(
                        builder: (context) {
                          final rows = export.animals
                              .where(
                                (a) =>
                                    '${a['name']} ${a['tattoo'] ?? ''} ${a['source_id']}'
                                        .toLowerCase()
                                        .contains(_editSearch),
                              )
                              .toList();
                          return ListView.builder(
                            itemCount: rows.length,
                            itemBuilder: (context, i) {
                              final a = rows[i];
                              final id = a['source_id'] as String;
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(a['name'] as String),
                                subtitle: Text(
                                  'Source #$id • Ear: ${a['tattoo'] ?? 'None'}${_edits.containsKey(id) ? ' • Corrected' : ''}',
                                ),
                                trailing: TextButton(
                                  key: ValueKey('edit-$id'),
                                  onPressed: _busy
                                      ? null
                                      : () => _editRabbit(a),
                                  child: const Text('Edit'),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _ack,
                  title: const Text('I reviewed the source warnings'),
                  onChanged: _busy
                      ? null
                      : (v) => setState(() {
                          _ack = v ?? false;
                          _invalidate();
                        }),
                ),
                const SizedBox(height: 20),
                ExpansionTile(
                  key: ValueKey('current-herd-$_fileRevision'),
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    'Choose current herd (${_activeIds.length} selected)',
                  ),
                  subtitle: const Text(
                    'Leave ancestors and other breeders’ rabbits unselected.',
                  ),
                  children: [
                    TextField(
                      key: const ValueKey('current-herd-search'),
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Search by name, ear number, or source ID',
                      ),
                      onChanged: (v) => setState(
                        () => _animalSearch = v.trim().toLowerCase(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 300,
                      child: Builder(
                        builder: (context) {
                          final rows = export.animals
                              .where(
                                (a) =>
                                    a['status'] == 'archived' &&
                                    '${a['name']} ${a['tattoo'] ?? ''} ${a['source_id']}'
                                        .toLowerCase()
                                        .contains(_animalSearch),
                              )
                              .toList();
                          return ListView.builder(
                            key: const ValueKey('current-herd-list'),
                            itemCount: rows.length,
                            itemBuilder: (context, i) {
                              final a = rows[i];
                              final id = a['source_id'] as String;
                              return CheckboxListTile(
                                key: ValueKey('active-$id'),
                                contentPadding: EdgeInsets.zero,
                                title: Text(a['name'] as String),
                                subtitle: Text(
                                  'Ear: ${a['tattoo'] ?? 'None'} • Source #$id',
                                ),
                                value: _activeIds.contains(id),
                                onChanged: _busy
                                    ? null
                                    : (v) => setState(() {
                                        if (v == true) {
                                          _activeIds.add(id);
                                        } else {
                                          _activeIds.remove(id);
                                        }
                                        _invalidate();
                                      }),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    const Text(
                      'Sold and deceased rabbits retain their source status. Reimporting preserves the status of existing animals.',
                    ),
                  ],
                ),
                if (export.animals.any((a) => a['sex'] == null)) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Choose missing sexes',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'The export does not specify these rabbits’ sexes. Choose only values you know to be correct.',
                  ),
                  const SizedBox(height: 20),
                  for (final a in export.animals.where(
                    (a) => a['sex'] == null,
                  )) ...[
                    Text('${a['name']} (source ${a['source_id']}): choose sex'),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: ValueKey('sex-${a['source_id']}-$_fileRevision'),
                      isExpanded: true,
                      initialValue: _sexes[a['source_id']],
                      decoration: const InputDecoration(labelText: 'Sex'),
                      items: const [
                        DropdownMenuItem(value: 'Buck', child: Text('Buck')),
                        DropdownMenuItem(value: 'Doe', child: Text('Doe')),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) => setState(() {
                              if (v != null) {
                                _sexes[a['source_id'] as String] = v;
                              }
                              _matches.clear();
                              _invalidate();
                            }),
                    ),
                    const SizedBox(height: 24),
                  ],
                ],
                if (parentProblems.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Review conflicting parent links',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'These links create a cycle or conflict with a parent’s sex. Correct them in Kintraks and export again, or explicitly choose which links to leave empty here.',
                  ),
                  const SizedBox(height: 12),
                  for (final problem in parentProblems) ...[
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _omittedParents.contains(problem['key']),
                      title: Text(
                        '${problem['name']} (#${problem['source_id']}) → ${problem['side'] == 'sire_id' ? 'sire' : 'dam'} ${problem['parent_name']} (#${problem['parent_id']})',
                      ),
                      subtitle: Text(
                        '${problem['reason']}. Select to leave this link empty; its original value stays in source history.',
                      ),
                      onChanged: _busy
                          ? null
                          : (value) => setState(() {
                              if (value == true) {
                                _omittedParents.add(problem['key']!);
                              } else {
                                _omittedParents.remove(problem['key']);
                              }
                              _invalidate();
                            }),
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed:
                      _busy || _herd == null || _source.text.trim().isEmpty
                      ? null
                      : _preview,
                  child: const Text('Preview import'),
                ),
              ]),
            ],
            if (_review != null)
              _panel('3. Review import', [
                Text(
                  '${_review!['animals_added']} new rabbits • ${_review!['animals_existing']} existing rabbits preserved • ${_review!['history_count']} source history records',
                ),
                const SizedBox(height: 20),
                for (final issue in issues)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      issue.toString(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                for (final warning in (_review!['warnings'] as List? ?? []))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(warning.toString()),
                  ),
                for (final row in (_review!['rows'] as List? ?? []))
                  if ((row['candidates'] as List? ?? []).isNotEmpty) ...[
                    _matchChoice(row),
                    const SizedBox(height: 24),
                  ],
                ExpansionTile(
                  title: const Text('Rabbit preview'),
                  tilePadding: EdgeInsets.zero,
                  children: [
                    for (final row in (_review!['rows'] as List? ?? []))
                      ExpansionTile(
                        title: Text('${row['name']} (#${row['source_id']})'),
                        subtitle: Text(row['action'] as String),
                        children: [
                          for (final a in export!.animals.where(
                            (a) => a['source_id'] == row['source_id'],
                          ))
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'Breed: ${a['breed'] ?? 'Unknown'} • Variety: ${a['variety'] ?? 'Unknown'}\n'
                                'Sex: ${_sexes[a['source_id']] ?? a['sex'] ?? 'Choose sex'} • DOB: ${a['dob'] ?? 'Unknown'} • Status: ${_activeIds.contains(a['source_id']) ? 'active' : a['status']}\n'
                                'Tattoo: ${a['tattoo'] ?? 'None'} • Sire source: ${_omittedParents.contains('${a['source_id']}:sire_id') ? 'Left empty by review' : a['sire_id'] ?? 'Unknown'} • Dam source: ${_omittedParents.contains('${a['source_id']}:dam_id') ? 'Left empty by review' : a['dam_id'] ?? 'Unknown'}\n'
                                'Profile weight: ${a['profile_weight'] ?? 'Unknown'} lb (date unknown)\n'
                                'Corrections: ${(a['corrections'] as Map? ?? {}).entries.map((e) => '${e.key}: ${e.value.toString().isEmpty ? '(cleared)' : e.value}').join('; ')}',
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'All original CSV fields, including both Breeder columns, vaccine details, ownership, awards, and undated weights, are retained in Kintraks history. Existing rabbits keep their details, parents, status, and weights. This export does not create dated measurements, litter tracking, or payments.',
                ),
                const SizedBox(height: 16),
                Text(
                  'Destination: ${_herds.firstWhere((h) => h['id'] == _herd)['name']} • Source: ${_source.text.trim()}',
                ),
                const SizedBox(height: 16),
                const Text(
                  'Nothing is saved until you choose Import into herd.',
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy || issues.isNotEmpty || !_ack ? null : _save,
                  child: const Text('Import into herd'),
                ),
              ]),
          ],
        ],
      ),
    );
  }

  Future<void> _editRabbit(Map<String, dynamic> animal) async {
    final id = animal['source_id'] as String;
    final changes = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _KintraksEditDialog(
        animal: animal,
        onValidate: (changes) =>
            _export!.withCorrections({..._edits, id: changes}),
      ),
    );
    if (changes == null || !mounted) return;
    final next = {..._edits, id: changes};
    final corrected = _export!.withCorrections(next);
    setState(() {
      if (changes.isEmpty) {
        _edits.remove(id);
      } else {
        _edits[id] = changes;
      }
      _export = corrected;
      _sexes.remove(id);
      _matches.clear();
      _omittedParents.clear();
      _activeIds.removeWhere(
        (id) => !corrected.animals.any(
          (a) => a['source_id'] == id && a['status'] == 'archived',
        ),
      );
      _ack = false;
      _error = null;
      _invalidate();
    });
  }

  Widget _matchChoice(dynamic row) {
    final sid = row['source_id'] as String;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${row['name']} (#$sid): existing match'),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('match-$sid-${_matches[sid]}'),
          initialValue: _matches[sid],
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Choose how to import this rabbit',
          ),
          items: [
            const DropdownMenuItem(
              value: 'new',
              child: Text('Keep as a separate new rabbit'),
            ),
            for (final c in row['candidates'] as List)
              DropdownMenuItem(
                value: c['id'] as String,
                child: Text(
                  'Link ${c['name']} • ${c['tattoo']} • ${c['status']} (${c['id']})',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _busy
              ? null
              : (v) => setState(() {
                  if (v != null) _matches[sid] = v;
                  _review = {
                    ..._review!,
                    'issues': ['Choices changed. Preview the import again.'],
                  };
                }),
        ),
      ],
    );
  }
}

class _KintraksEditDialog extends StatefulWidget {
  final Map<String, dynamic> animal;
  final void Function(Map<String, String>) onValidate;
  const _KintraksEditDialog({required this.animal, required this.onValidate});
  @override
  State<_KintraksEditDialog> createState() => _KintraksEditDialogState();
}

class _KintraksEditDialogState extends State<_KintraksEditDialog> {
  late final raw = widget.animal['raw'] as Map;
  late final controllers = <String, TextEditingController>{
    for (final key in raw.keys.where((k) => k != 'Id' && k != '_csv_headers'))
      key as String: TextEditingController(
        text:
            (widget.animal['corrections'] as Map?)?[key] as String? ??
            raw[key] as String? ??
            '',
      ),
  };
  String? error;
  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> changes() => {
    for (final e in controllers.entries)
      if (e.value.text != raw[e.key]) e.key: e.value.text,
  };
  bool get misplacedWeight {
    final legs = controllers['Legs']?.text.trim() ?? '';
    if (legs.isEmpty || int.tryParse(legs) != null) return false;
    try {
      return KintraksExport.poundsAndOunces(legs) != null &&
          controllers.containsKey('Weight');
    } on FormatException {
      return false;
    }
  }

  void apply() {
    final edits = changes();
    try {
      widget.onValidate(edits);
      Navigator.pop(context, edits);
    } on FormatException catch (e) {
      setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      'Edit ${widget.animal['name']} (#${widget.animal['source_id']})',
    ),
    content: SizedBox(
      width: 600,
      height: MediaQuery.sizeOf(context).height * .65,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Source ID is fixed. Weight uses pounds and ounces; dates use YYYY-MM-DD. Clear a value to leave it empty. Parent fields use source IDs. Breeder [1], Sold, and Deceased use True or False.',
            ),
            const SizedBox(height: 16),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (misplacedWeight) ...[
              OutlinedButton(
                key: const ValueKey('move-legs-weight'),
                onPressed: () => setState(() {
                  controllers['Weight']!.text = controllers['Legs']!.text;
                  controllers['Legs']!.clear();
                  error = null;
                }),
                child: Text(
                  'Move Legs value (${controllers['Legs']!.text}) to Weight',
                ),
              ),
              const Text(
                'This replaces the current Weight field. Apply corrections to keep this change.',
              ),
              const SizedBox(height: 20),
            ],
            for (final entry in controllers.entries) ...[
              TextFormField(
                key: ValueKey('field-${entry.key}'),
                controller: entry.value,
                decoration: InputDecoration(
                  labelText: entry.key,
                  helperText: raw[entry.key].toString().isEmpty
                      ? 'Originally empty'
                      : 'Original: ${raw[entry.key]}',
                  helperMaxLines: 3,
                ),
                minLines: 1,
                maxLines:
                    entry.key == 'Notes' ||
                        entry.key == 'Health' ||
                        entry.key == 'Journal'
                    ? 5
                    : 1,
              ),
              const SizedBox(height: 20),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () {
          for (final e in controllers.entries) {
            e.value.text = raw[e.key] as String? ?? '';
          }
          setState(() => error = null);
        },
        child: const Text('Reset to CSV'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('apply-corrections'),
        onPressed: apply,
        child: const Text('Apply corrections'),
      ),
    ],
  );
}
