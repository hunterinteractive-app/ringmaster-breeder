import '../offline/offline_runtime.dart';
import 'package:flutter/material.dart';
import '../widgets/ringmaster_page_shell.dart';

class GlobalPedigreeHistoryScreen extends StatefulWidget {
  final String? ringId, animalId;
  const GlobalPedigreeHistoryScreen({super.key, this.ringId, this.animalId});
  @override
  State<GlobalPedigreeHistoryScreen> createState() =>
      _GlobalPedigreeHistoryScreenState();
}

class _GlobalPedigreeHistoryScreenState
    extends State<GlobalPedigreeHistoryScreen> {
  late Future<List<Map<String, dynamic>>> _records;
  String _filter = 'All';
  @override
  void initState() {
    super.initState();
    _records = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = <Map<String, dynamic>>[];
    // Paginate: history may exceed the API's default 1,000-row limit.
    for (var offset = 0; ; offset += 500) {
      var query = OfflineRuntime.client
          .from('global_pedigree_history')
          .select();
      if (widget.ringId != null) {
        query = query.eq('ring_id', widget.ringId!);
      }
      if (widget.animalId != null) {
        query = query.or(
          'animal_id.eq.${widget.animalId},sire_id.eq.${widget.animalId}',
        );
      }
      final page = await query.order('id').range(offset, offset + 499);
      rows.addAll(page);
      if (page.length < 500) break;
    }
    rows.sort((a, b) => _date(b).compareTo(_date(a)));
    return rows;
  }

  String _date(Map row) {
    final r = row['record'] as Map;
    final raw =
        (r['recorded_date'] ??
                r['fields']?['Date Bred'] ??
                r['date_bred'] ??
                '')
            .toString();
    final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(raw);
    return match == null ? raw : '${match[3]}-${match[1]}-${match[2]}';
  }

  void _refresh() => setState(() => _records = _load());
  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    title: 'Global Pedigree history',
    onRefresh: _refresh,
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _records,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: _refresh,
              child: const Text('Unable to load history. Try again.'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!
            .where((r) => _filter == 'All' || r['kind'] == _filter)
            .toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Imported source history. Dates and totals are preserved as recorded in Global Pedigree.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in {
                  'All': 'All',
                  'litter': 'Litters & breedings',
                  'weight': 'Weights',
                  'show': 'Show results',
                }.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _filter == entry.key,
                    onSelected: (_) => setState(() => _filter = entry.key),
                  ),
              ],
            ),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No imported records in this category.'),
              ),
            for (final row in rows) _card(row),
          ],
        );
      },
    ),
  );
  Widget _card(Map row) {
    final r = row['record'] as Map, fields = (r['fields'] as Map?) ?? {};
    final isLitter = row['kind'] == 'litter';
    final title = isLitter
        ? '${r['dam_name']} × ${r['sire_name']}'
        : row['kind'] == 'weight'
        ? '${r['weight']} lb • ${r['recorded_date']}'
        : 'Show result';
    return Card(
      child: ExpansionTile(
        title: Text(title),
        subtitle: Text(
          isLitter
              ? '${r['category']} • Bred ${r['date_bred']}'
              : 'Source record ${r['source_id']}',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isLitter)
                  Text(
                    'Kindled / due: ${r['kindled_or_due']}\nBorn: ${r['born']} • Died: ${r['died']}\nBucks: ${r['bucks']} • Does: ${r['does']}\nWeaned: ${r['weaned']} • Date: ${r['date_weaned']}',
                  ),
                for (final field in fields.entries)
                  if (field.value.toString().isNotEmpty)
                    Text('${field.key}: ${field.value}'),
                if (r['events'] != null)
                  for (final event in r['events'] as List)
                    Text('${event['event']}: ${event['date']}'),
                if ((r['offspring_source_ids'] as List? ?? []).isNotEmpty)
                  Text(
                    'Linked offspring source records: ${(r['offspring_source_ids'] as List).join(', ')}',
                  ),
                TextButton(
                  onPressed: () => Navigator.pushNamed(
                    context,
                    '/animal-detail',
                    arguments: row['animal_id'],
                  ),
                  child: Text(isLitter ? 'Open dam' : 'Open rabbit'),
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
