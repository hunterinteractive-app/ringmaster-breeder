import 'herd_contacts_screen.dart';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../imports/rabbit_register_xml.dart';
import '../offline/offline_runtime.dart';
import '../services/rabbit_register_import_service.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/ringmaster_page_shell.dart';
import 'rabbit_register_history_screen.dart';

class RabbitRegisterImportScreen extends StatefulWidget {
  final RabbitRegisterImportGateway? gateway;
  final Future<({String name, Uint8List bytes})?> Function()? pickFile;
  const RabbitRegisterImportScreen({super.key, this.gateway, this.pickFile});
  @override
  State<RabbitRegisterImportScreen> createState() =>
      _RabbitRegisterImportScreenState();
}

class _RabbitRegisterImportScreenState
    extends State<RabbitRegisterImportScreen> {
  late final _gateway =
      widget.gateway ?? RabbitRegisterImportService(OfflineRuntime.client);
  final _source = TextEditingController();
  List<Map<String, dynamic>> _herds = [];
  List<String> _sources = [];
  String? _herd, _filename, _error;
  RabbitRegisterExport? _export;
  Map<String, dynamic>? _review, _result;
  final Map<String, String> _sexes = {}, _matches = {};
  final Set<String> _omittedParents = {};
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

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on FormatException catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(
          () => _error = ['PGRST202', '42P01'].contains(e.code)
              ? 'Rabbit Register import is not available on this server yet.'
              : 'The server could not complete the import. Check herd access and retry; the import saves atomically.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Unable to complete this step. Reconnect and retry with the same source name; retries preserve existing records.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _invalidate() => _review = null;
  Future<void> _pick() => _run(() async {
    setState(_invalidate);
    final file = await (widget.pickFile?.call() ?? _pickPlatformFile());
    if (file == null || !mounted) return;
    final parsed = RabbitRegisterExport.parse(file.bytes);
    setState(() {
      _filename = file.name;
      _export = parsed;
      _sexes.clear();
      _omittedParents.clear();
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
      allowedExtensions: ['xml'],
      withData: true,
    );
    if (result == null) return null;
    final file = result.files.single;
    if (file.size > RabbitRegisterExport.maxBytes) {
      throw const FormatException('Select an XML file smaller than 10 MB.');
    }
    if (file.bytes == null) {
      throw const FormatException('Unable to read this file. Choose it again.');
    }
    return (name: file.name, bytes: file.bytes!);
  }

  Map<String, dynamic> _payload() => _export!.payload(
    filename: _filename,
    sexes: _sexes,
    matches: _matches,
    acknowledged: _ack,
    omittedParents: _omittedParents,
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
      title: 'Import from Rabbit Register',
      body: ListView(
        padding: BreederLayout.pagePadding(context, normal: 24),
        children: [
          const Text(
            'In Rabbit Register, choose Data Management → Export Data as XML File → Other. Upload that XML here, review the records, then choose whether to import. Preview and saving require an internet connection.',
          ),
          const SizedBox(height: 20),
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
              for (final warning in _result!['warnings'] as List? ?? [])
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(warning.toString()),
                ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RabbitRegisterHistoryScreen(ringId: _herd),
                  ),
                ),
                child: const Text('View Rabbit Register history'),
              ),
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HerdContactsScreen(ringId: _herd),
                  ),
                ),
                icon: const Icon(Icons.contacts_outlined),
                label: const Text('Review contacts & account setup'),
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
                  hintText: 'Example: Hunter Rabbit Register',
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
                'Rabbit Register stores XML weights in grams. Breeder converts them to pounds automatically.',
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pick,
                icon: const Icon(Icons.upload_file),
                label: const Text('Choose Rabbit Register XML'),
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
                    for (final entry in const {
                      'Animals': 'Rabbits',
                      'Contacts': 'Contacts',
                      'Winnings': 'Show results',
                      'Litters': 'Litters',
                      'CritterWeights': 'Animal weights',
                      'LitterWeights': 'Litter weights',
                      'Wool': 'Wool harvests',
                      'PictureMap': 'Picture references',
                      'Mileage': 'Mileage',
                    }.entries)
                      Chip(
                        label: Text(
                          '${entry.value}: ${export.counts[entry.key] ?? 0}',
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '${export.animals.where((a) => a['status'] == 'active').length} active rabbits • ${export.animals.where((a) => a['status'] != 'active').length} historical rabbits',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Rabbits, contacts, litters, show results, sales and valid measurements are linked to their normal screens. Missing dates and zero-weight rows remain in source history. Account details change only after you choose a contact. Different source IDs remain separate unless you explicitly link them to an existing rabbit.',
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
                const SizedBox(height: 16),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _ack,
                  title: const Text(
                    'I reviewed the source warnings. Preserve missing references in source history and leave their pedigree links empty.',
                  ),
                  onChanged: _busy
                      ? null
                      : (v) => setState(() {
                          _ack = v ?? false;
                          _invalidate();
                        }),
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
                    'These links create a cycle or conflict with a parent’s sex. Correct them in Rabbit Register and export again, or explicitly choose which links to leave empty here.',
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
                                'Sex: ${_sexes[a['source_id']] ?? a['sex'] ?? 'Choose sex'} • DOB: ${a['dob'] ?? 'Unknown'} • Status: ${a['status']}\n'
                                'Tattoo: ${a['tattoo'] ?? 'None'} • Sire source: ${_omittedParents.contains('${a['source_id']}:sire_id') ? 'Left empty by review' : a['sire_id'] ?? 'Unknown'} • Dam source: ${_omittedParents.contains('${a['source_id']}:dam_id') ? 'Left empty by review' : a['dam_id'] ?? 'Unknown'}\n'
                                'Profile weight: ${a['profile_weight'] ?? 'Unknown'} lb (date unknown)',
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'Contacts, litters, show results, sale fields, and original rabbit fields are retained in Rabbit Register history. Imported litters and sales do not create active tracking or payment records. Existing rabbits keep their details, parents, and weights.',
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
