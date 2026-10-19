import 'package:flutter/material.dart';
import '../offline/offline_runtime.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/ringmaster_page_shell.dart';

class KintraksHistoryScreen extends StatefulWidget {
  final String? ringId, animalId;
  const KintraksHistoryScreen({super.key, this.ringId, this.animalId});
  @override
  State<KintraksHistoryScreen> createState() => _KintraksHistoryScreenState();
}

class _KintraksHistoryScreenState extends State<KintraksHistoryScreen> {
  late Future<List<Map<String, dynamic>>> _rows;
  @override
  void initState() {
    super.initState();
    _rows = _load();
  }

  void _refresh() => setState(() => _rows = _load());
  Future<List<Map<String, dynamic>>> _load() async {
    final rows = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += 500) {
      var query = OfflineRuntime.client.from('kintraks_animals').select();
      if (widget.ringId != null) query = query.eq('ring_id', widget.ringId!);
      if (widget.animalId != null) {
        query = query.eq('animal_id', widget.animalId!);
      }
      final page = await query
          .order('ring_id')
          .order('source')
          .order('source_id')
          .range(offset, offset + 499);
      rows.addAll(page);
      if (page.length < 500) break;
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    title: 'Kintraks history',
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
        final rows = snapshot.data!;
        return ListView.builder(
          padding: BreederLayout.pagePadding(context, normal: 16),
          itemCount: rows.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  rows.isEmpty
                      ? 'No Kintraks records imported.'
                      : 'Original Kintraks CSV fields and import choices. Breeder [1] is the original status flag; Breeder [2] contains the breeder name. Undated weights remain snapshots. Custom vaccine fields remain as exported and do not create treatment records.',
                ),
              );
            }
            final row = rows[index - 1];
            final raw = row['raw'] as Map;
            final name = [
              raw['Prefix'],
              raw['Name'],
              raw['Suffix'],
            ].where((v) => v != null && v.toString().isNotEmpty).join(' ');
            return Card(
              child: ExpansionTile(
                title: Text(
                  name.isEmpty ? 'Kintraks #${row['source_id']}' : name,
                ),
                subtitle: Text(
                  '${row['source']} • Source #${row['source_id']}',
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (row['profile_weight'] != null)
                          Text(
                            'Profile weight: ${row['profile_weight']} lb (measurement date unknown)',
                          ),
                        if (row['decisions'] is Map)
                          for (final choice
                              in (row['decisions'] as Map).entries)
                            Text(
                              'Import review ${choice.key}: ${choice.value ?? 'Left empty'}',
                            ),
                        if ((row['decisions'] as Map?)?['corrections'] is Map)
                          for (final edit
                              in ((row['decisions'] as Map)['corrections']
                                      as Map)
                                  .entries)
                            SelectableText(
                              'Corrected ${edit.key}: ${edit.value.toString().isEmpty ? '(cleared)' : edit.value}',
                            ),
                        for (final field in raw.entries)
                          if (field.key != '_csv_headers' &&
                              field.value.toString().isNotEmpty)
                            SelectableText('${field.key}: ${field.value}'),
                        TextButton(
                          onPressed: () => Navigator.pushNamed(
                            context,
                            '/animal-detail',
                            arguments: row['animal_id'],
                          ),
                          child: const Text('Open rabbit'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ),
  );
}
