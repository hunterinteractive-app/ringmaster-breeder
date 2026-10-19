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
        var query = OfflineRuntime.client.from(table).select();
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
    return rows;
  }

  static const _labels = {
    'all': 'All',
    'animal': 'Rabbit snapshots',
    'contact': 'Contacts',
    'litter': 'Litters & breedings',
    'show': 'Show results',
    'weight': 'Weights',
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
              'Original Rabbit Register records, retained as exported. Empty-date values such as 0100-01-01 mean no date. Profile weights have no measurement date. Litters and sale fields are source history, separate from active tracking and payments.',
            ),
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

  Widget _card(Map<String, dynamic> row) {
    final record = row['record'] as Map?;
    final raw = (row['raw'] ?? record?['raw']) as Map;
    final title = switch (row['kind']) {
      'animal' => raw['Name'] ?? raw['Ear_Num'] ?? 'Unnamed rabbit',
      'contact' => '${raw['FirstName'] ?? ''} ${raw['LastName'] ?? ''}'.trim(),
      'show' =>
        '${raw['ShowName'] ?? 'Show result'} • ${raw['ShowDate'] ?? 'Date unknown'}',
      'litter' =>
        'Litter • ${raw['DATEBRED'] ?? raw['DATEBORN'] ?? 'Date unknown'}',
      'weight' => '${record?['weight']} lb • ${record?['recorded_date']}',
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
}
