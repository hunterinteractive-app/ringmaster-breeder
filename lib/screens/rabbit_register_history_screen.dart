import 'herd_contacts_screen.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../offline/offline_runtime.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/ringmaster_page_shell.dart';

class RabbitRegisterHistoryScreen extends StatefulWidget {
  final String? ringId, animalId;
  const RabbitRegisterHistoryScreen({super.key, this.ringId, this.animalId});
  @override
  State<RabbitRegisterHistoryScreen> createState() =>
      _RabbitRegisterHistoryScreenState();
}

class _RabbitRegisterHistoryScreenState
    extends State<RabbitRegisterHistoryScreen> {
  late Future<List<Map<String, dynamic>>> _rows;
  String _filter = 'all';
  @override
  void initState() {
    super.initState();
    _rows = _load();
  }

  void _refresh() => setState(() => _rows = _load());

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = <Map<String, dynamic>>[];
    for (final table in [
      'rabbit_register_animals',
      'rabbit_register_records',
    ]) {
      for (var offset = 0; ; offset += 500) {
        var query = OfflineRuntime.client
            .from(table)
            .select(
              table == 'rabbit_register_records'
                  ? '*,native_wool:animal_wool_records(animal_id)'
                  : '*',
            );
        if (widget.ringId != null) query = query.eq('ring_id', widget.ringId!);
        if (widget.animalId != null) {
          query = table == 'rabbit_register_animals'
              ? query.eq('animal_id', widget.animalId!)
              : query.or(
                  'animal_id.eq.${widget.animalId},sire_id.eq.${widget.animalId}',
                );
        }
        final page = await query
            .order('ring_id')
            .order('source')
            .order('source_id')
            .order(table == 'rabbit_register_records' ? 'kind' : 'animal_id')
            .range(offset, offset + 499);
        rows.addAll(
          page.map(
            (r) => <String, dynamic>{
              ...r,
              if (table == 'rabbit_register_animals') 'kind': 'animal',
            },
          ),
        );
        if (page.length < 500) break;
      }
    }
    if (widget.animalId == null) {
      for (var offset = 0; ; offset += 500) {
        var query = OfflineRuntime.client
            .from('rabbit_register_files')
            .select('id,ring_id,source,filename,header,recovered,imported_at');
        if (widget.ringId != null) query = query.eq('ring_id', widget.ringId!);
        final page = await query
            .order('imported_at', ascending: false)
            .order('id')
            .range(offset, offset + 499);
        rows.addAll(
          page.map(
            (r) => <String, dynamic>{
              ...r,
              'kind': 'file',
              'source_id': r['id'],
              'raw': r['header'],
            },
          ),
        );
        if (page.length < 500) break;
      }
    }
    return rows;
  }

  static const _labels = {
    'all': 'All',
    'animal': 'Rabbit snapshots',
    'contact': 'Contacts',
    'litter': 'Litters & breedings',
    'show': 'Show results',
    'weight': 'Weights',
    'litter_weight': 'Litter weights',
    'wool': 'Wool harvests',
    'picture': 'Picture references',
    'mileage': 'Mileage',
    'growth': 'Growth',
    'finance': 'Finances',
    'journal': 'Journal',
    'sweep': 'Sweepstakes',
    'file': 'Original XML files',
  };
  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    title: 'Rabbit Register history',
    onRefresh: _refresh,
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _rows,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: _refresh,
              child: const Text(
                'Unable to load source history. Reconnect and try again.',
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!
            .where((r) => _filter == 'all' || r['kind'] == _filter)
            .toList();
        return ListView(
          padding: BreederLayout.pagePadding(context, normal: 16),
          children: [
            const Text(
              'Original Rabbit Register records, retained as exported. Blank-date or zero-weight rows remain here without creating chart measurements. Linked litters, show results, contacts, sales and wool records also appear in their normal screens. Payment receipts are not supplied by the export.',
            ),
            if (widget.animalId == null) ...[
              TextButton.icon(
                onPressed: () => _downloadHistory(snapshot.data!),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Download all retained source records'),
              ),
              TextButton.icon(
                onPressed: () => _link(snapshot.data!),
                icon: const Icon(Icons.link),
                label: const Text('Add retained records to normal tracking'),
              ),
              TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HerdContactsScreen(ringId: widget.ringId),
                  ),
                ),
                child: const Text('Contacts & account setup'),
              ),
            ],
            Wrap(
              spacing: 8,
              children: [
                for (final label in _labels.entries)
                  ChoiceChip(
                    label: Text(label.value),
                    selected: _filter == label.key,
                    onSelected: (_) => setState(() => _filter = label.key),
                  ),
              ],
            ),
            if (rows.isEmpty)
              const Text('No imported records in this category.'),
            for (final row in rows) _card(row),
          ],
        );
      },
    ),
  );

  Future<void> _link(List<Map<String, dynamic>> rows) async {
    final sources = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      sources['${r['ring_id']}:${r['source']}'] = r;
    }
    if (sources.isEmpty) return;
    try {
      final previews = <Map<String, dynamic>>[];
      for (final r in sources.values) {
        previews.add(
          Map<String, dynamic>.from(
            await OfflineRuntime.client.rpc(
              'link_rabbit_register_history',
              params: {'p_ring': r['ring_id'], 'p_source': r['source']},
            ),
          ),
        );
      }
      if (!mounted) return;
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Link previously imported history?'),
          content: SingleChildScrollView(
            child: Text(
              '${previews.fold<int>(0, (n, r) => n + (r['contacts'] as num).toInt())} contacts, ${previews.fold<int>(0, (n, r) => n + (r['litters'] as num).toInt())} litters and ${previews.fold<int>(0, (n, r) => n + (r['shows'] as num).toInt())} show records will be checked for links. Existing source links are reused. Missing management details are filled, and current values are preserved. Account details change only when you separately choose a contact.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Link records'),
            ),
          ],
        ),
      );
      if (yes != true) return;
      final warnings = <String>[];
      for (final r in sources.values) {
        final result = await OfflineRuntime.client.rpc(
          'link_rabbit_register_history',
          params: {
            'p_ring': r['ring_id'],
            'p_source': r['source'],
            'p_commit': true,
          },
        );
        warnings.addAll((result['warnings'] as List? ?? []).cast<String>());
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('History linked'),
          content: SingleChildScrollView(
            child: Text(
              warnings.isEmpty
                  ? 'Records are available in their normal screens.'
                  : 'Some rows remain in source history:\n${warnings.join('\n')}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to link history. Reconnect and retry. Already linked source records will be reused.',
            ),
          ),
        );
      }
    }
  }

  Widget _card(Map<String, dynamic> row) {
    final record = row['record'] as Map?;
    final raw = (row['raw'] ?? record?['raw']) as Map;
    final title = switch (row['kind']) {
      'file' => row['filename'] ?? 'Original XML',
      'animal' => raw['Name'] ?? raw['Ear_Num'] ?? 'Unnamed rabbit',
      'contact' => '${raw['FirstName'] ?? ''} ${raw['LastName'] ?? ''}'.trim(),
      'show' =>
        '${raw['ShowName'] ?? 'Show result'} • ${raw['ShowDate'] ?? 'Date unknown'}',
      'litter' =>
        'Litter • ${raw['DATEBRED'] ?? raw['DATEBORN'] ?? 'Date unknown'}',
      'weight' =>
        '${record?['weight'] == null ? 'No body weight' : '${record?['weight']} lb'} • ${record?['recorded_date'] ?? 'Date unknown'}',
      _ => 'Source record',
    };
    return Card(
      child: ExpansionTile(
        title: Text(title.toString()),
        subtitle: Text(
          '${row['source']} • ${_labels[row['kind']]} #${row['source_id']}',
        ),
        children: [
          AdaptivePadding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (row['kind'] == 'file') ...[
                  Text('Saved ${row['imported_at']}'),
                  if (row['recovered'] == true)
                    const Text(
                      'The source export was incomplete. Its original XML is preserved unchanged.',
                    ),
                  TextButton.icon(
                    onPressed: () => _downloadOriginal(row),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Download original XML'),
                  ),
                ],
                if (row['profile_weight'] != null)
                  Text(
                    'Profile weight: ${row['profile_weight']} lb (measurement date unknown)',
                  ),
                if (row['decisions'] is Map)
                  for (final choice in (row['decisions'] as Map).entries)
                    Text(
                      'Import review ${choice.key}: ${choice.value ?? 'Left empty'}',
                    ),
                for (final field in raw.entries)
                  if (field.value.toString().isNotEmpty)
                    SelectableText('${field.key}: ${field.value}'),
                if (row['kind'] == 'wool' &&
                    row['animal_id'] == null &&
                    row['native_wool_id'] == null)
                  TextButton.icon(
                    onPressed: () => _linkWool(row),
                    icon: const Icon(Icons.link),
                    label: const Text('Link wool record to rabbit'),
                  ),
                if (row['native_wool'] is Map && row['animal_id'] == null)
                  TextButton(
                    onPressed: () => Navigator.pushNamed(
                      context,
                      '/animal-detail',
                      arguments: row['native_wool']['animal_id'],
                    ),
                    child: const Text('Open linked rabbit'),
                  ),
                if (row['animal_id'] != null)
                  TextButton(
                    onPressed: () => Navigator.pushNamed(
                      context,
                      '/animal-detail',
                      arguments: row['animal_id'],
                    ),
                    child: Text(
                      row['kind'] == 'litter' ? 'Open dam' : 'Open rabbit',
                    ),
                  ),
                if (row['sire_id'] != null)
                  TextButton(
                    onPressed: () => Navigator.pushNamed(
                      context,
                      '/animal-detail',
                      arguments: row['sire_id'],
                    ),
                    child: const Text('Open sire'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _linkWool(Map<String, dynamic> row) async {
    try {
      final animals = <Map<String, dynamic>>[];
      for (var start = 0; ; start += 500) {
        final page = await OfflineRuntime.client
            .from('animals')
            .select('id,name,tattoo,breed,status')
            .eq('ring_id', row['ring_id'])
            .eq('species', 'rabbit')
            .order('id')
            .range(start, start + 499);
        animals.addAll(page);
        if (page.length < 500) break;
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => LinkWoolRabbitDialog(
          animals: animals,
          writer: (id) async {
            await OfflineRuntime.client.rpc(
              'link_rabbit_register_wool',
              params: {
                'p_ring': row['ring_id'],
                'p_source': row['source'],
                'p_source_id': row['source_id'],
                'p_animal': id,
              },
            );
          },
        ),
      );
      _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to link wool. Reconnect and retry.'),
          ),
        );
      }
    }
  }

  Future<void> _downloadOriginal(Map<String, dynamic> row) async {
    try {
      final saved = await OfflineRuntime.client
          .from('rabbit_register_files')
          .select('original_file_base64')
          .eq('id', row['id'])
          .single();
      await FilePicker.platform.saveFile(
        dialogTitle: 'Save original Rabbit Register export',
        fileName: row['filename'],
        type: FileType.custom,
        allowedExtensions: ['xml'],
        bytes: base64Decode(saved['original_file_base64'] as String),
      );
    } catch (_) {
      _downloadError();
    }
  }

  Future<void> _downloadHistory(List<Map<String, dynamic>> rows) async {
    try {
      await FilePicker.platform.saveFile(
        dialogTitle: 'Save retained Rabbit Register records',
        fileName: 'rabbit-register-source-history.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(
          utf8.encode(const JsonEncoder.withIndent('  ').convert(rows)),
        ),
      );
    } catch (_) {
      _downloadError();
    }
  }

  void _downloadError() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to download the source records. Reconnect and retry.',
          ),
        ),
      );
    }
  }
}

class LinkWoolRabbitDialog extends StatefulWidget {
  final List<Map<String, dynamic>> animals;
  final Future<void> Function(String) writer;
  const LinkWoolRabbitDialog({
    super.key,
    required this.animals,
    required this.writer,
  });
  @override
  State<LinkWoolRabbitDialog> createState() => _LinkWoolRabbitDialogState();
}

class _LinkWoolRabbitDialogState extends State<LinkWoolRabbitDialog> {
  String search = '';
  String? selected, error;
  bool saving = false;
  @override
  Widget build(BuildContext context) => AdaptiveFormDialog(
    title: const Text('Link wool record to rabbit'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'The export did not provide a usable rabbit reference for this record. Choose its rabbit to add the harvest or evaluation to normal wool tracking. The original XML stays unchanged.',
        ),
        const SizedBox(height: 16),
        TextField(
          enabled: !saving,
          decoration: const InputDecoration(
            labelText: 'Search name or ear number',
          ),
          onChanged: (v) => setState(() => search = v.toLowerCase()),
        ),
        const SizedBox(height: 12),
        if (error != null) Text(error!),
        for (final a in widget.animals.where(
          (a) => '${a['name']} ${a['tattoo']}'.toLowerCase().contains(search),
        ))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${a['name'] ?? 'Unnamed'} · ${a['tattoo'] ?? ''}'),
            subtitle: Text('${a['breed'] ?? ''} · ${a['status'] ?? ''}'),
            leading: Icon(
              selected == a['id']
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
            ),
            onTap: saving ? null : () => setState(() => selected = a['id']),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: saving || selected == null
            ? null
            : () async {
                setState(() => saving = true);
                try {
                  await widget.writer(selected!);
                  if (context.mounted) Navigator.pop(context);
                } catch (_) {
                  if (mounted) {
                    setState(() {
                      saving = false;
                      error = 'Unable to confirm the link. Refresh and retry.';
                    });
                  }
                }
              },
        child: Text(saving ? 'Linking…' : 'Link selected rabbit'),
      ),
    ],
  );
}
