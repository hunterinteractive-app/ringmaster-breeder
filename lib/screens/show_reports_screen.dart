import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/family_service.dart';
import '../services/show_report_service.dart';
import '../widgets/ringmaster_page_shell.dart';
import 'animal_detail_screen.dart';

String reportDate(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date == null
      ? 'Date not recorded'
      : DateFormat('MM-dd-yy').format(date);
}

class ShowReportsScreen extends StatefulWidget {
  final String? animalId;
  final bool ownAccount;
  const ShowReportsScreen({super.key, this.animalId, this.ownAccount = false});
  @override
  State<ShowReportsScreen> createState() => _ShowReportsScreenState();
}

class _ShowReportsScreenState extends State<ShowReportsScreen> {
  List<Map<String, dynamic>> reports = [], results = [];
  bool busy = true;
  String? message, ownerId;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<List<Map<String, dynamic>>> rows(String table) async {
    final all = <Map<String, dynamic>>[];
    for (var start = 0; ; start += 500) {
      var query = Supabase.instance.client
          .from(table)
          .select()
          .eq('owner_id', ownerId!);
      if (table == 'breeder_show_history' && widget.animalId != null) {
        query = query.eq('animal_id', widget.animalId!);
      }
      final page = await query.order('id').range(start, start + 499);
      all.addAll(page);
      if (page.length < 500) return all;
    }
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      if (widget.animalId != null) {
        final animal = await Supabase.instance.client
            .from('animals')
            .select('ring_id')
            .eq('id', widget.animalId!)
            .single();
        final herd = await Supabase.instance.client
            .from('farms')
            .select('owner_id')
            .eq('id', animal['ring_id'])
            .single();
        ownerId = herd['owner_id'] as String;
      } else if (widget.ownAccount) {
        final own = await Supabase.instance.client
            .from('users')
            .select('id')
            .eq('auth_user_id', Supabase.instance.client.auth.currentUser!.id)
            .single();
        ownerId = own['id'] as String;
      } else {
        await FamilyService.refresh();
        ownerId = FamilyService.ownerId;
      }
      if (ownerId == null) throw StateError('Missing account');
      try {
        final sync = await ShowReportService.request(
          'refresh',
          ownerId: ownerId,
        );
        if (sync['skipped'] == true) {
          message =
              'Automatic receiving is off. Enable Receive show reports in Account to get new reports.';
        }
      } catch (_) {
        message =
            'Unable to refresh from Show. Displaying previously received reports. Use Refresh to retry.';
      }
      final loaded = await Future.wait([
        rows('connected_show_reports'),
        rows('breeder_show_history'),
      ]);
      if (!mounted) return;
      setState(() {
        results = loaded[1]
          ..sort(
            (a, b) => (b['record']['shows']?['start_date'] ?? '')
                .toString()
                .compareTo(
                  (a['record']['shows']?['start_date'] ?? '').toString(),
                ),
          );
        reports =
            loaded[0]
                .where(
                  (r) =>
                      widget.animalId == null ||
                      results.any(
                        (e) =>
                            e['record']['show_id'] == r['record']['show_id'] &&
                            e['exhibitor_source_id'] ==
                                r['record']['exhibitor_id'],
                      ),
                )
                .toList()
              ..sort(
                (a, b) =>
                    (b['record']['show_start_date'] ?? '').toString().compareTo(
                      (a['record']['show_start_date'] ?? '').toString(),
                    ),
              );
      });
    } catch (_) {
      if (mounted) {
        setState(() => message = 'Unable to load show reports. Please retry.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> openReport(String id) async {
    try {
      final data = await ShowReportService.request(
        'download',
        ownerId: ownerId,
        reportId: id,
      );
      final uri = Uri.parse(data['url'] as String);
      if (uri.scheme != 'https' ||
          !await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
            webOnlyWindowName: '_self',
          )) {
        throw StateError('Unable to open');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to open this report. Refresh and try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    title: widget.animalId == null ? 'Show reports' : 'Animal show history',
    actions: [
      IconButton(
        tooltip: 'Refresh reports',
        onPressed: busy ? null : load,
        icon: const Icon(Icons.refresh),
      ),
    ],
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (busy) const LinearProgressIndicator(),
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(message!),
          ),
        Text(
          'Reports & ARBA legs',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        if (!busy && reports.isEmpty)
          const Text(
            'No reports received yet. Available reports from your linked Show account will appear here.',
          ),
        for (final row in reports)
          Card(
            child: ListTile(
              leading: Icon(
                row['record']['report_name'] == 'legs'
                    ? Icons.workspace_premium_outlined
                    : Icons.picture_as_pdf_outlined,
              ),
              title: Text(row['record']['show_name'] ?? 'Show report'),
              subtitle: Text(
                [
                  reportDate(row['record']['show_start_date']),
                  row['record']['report_name'] == 'legs'
                      ? 'ARBA legs'
                      : 'Exhibitor report',
                  if (row['record']['exhibitor_name'] != null)
                    row['record']['exhibitor_name'].toString(),
                  if (row['source_available'] == false)
                    'No longer available in Show',
                ].join(' • '),
              ),
              trailing: row['source_available'] == false
                  ? null
                  : const Icon(Icons.open_in_new),
              onTap: row['source_available'] == false
                  ? null
                  : () => openReport(row['id']),
            ),
          ),
        const SizedBox(height: 24),
        Text('Show results', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        if (!busy && results.isEmpty)
          const Text('No show results received yet.'),
        for (final row in results)
          ShowResultCard(
            row: row,
            onAnimal: row['animal_id'] == null || widget.animalId != null
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          AnimalDetailScreen(animalId: row['animal_id']),
                    ),
                  ),
          ),
      ],
    ),
  );
}

class ShowResultCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback? onAnimal;
  const ShowResultCard({super.key, required this.row, this.onAnimal});
  @override
  Widget build(BuildContext context) {
    final r = Map<String, dynamic>.from(row['record'] as Map);
    final show = r['shows'] is Map ? r['shows'] as Map : {};
    final awards = (r['entry_awards'] as List? ?? [])
        .map((a) => a['award_code'].toString())
        .toSet();
    final name = [
      r['animal_name'],
      r['tattoo'],
    ].where((v) => v != null && v.toString().trim().isNotEmpty).join(' • ');
    final placement = r['is_fur'] == true
        ? r['fur_placement'] ?? r['placement']
        : r['placement'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              show['name']?.toString() ?? 'Show entry',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(reportDate(show['start_date'])),
            const SizedBox(height: 8),
            Text(
              name.isEmpty ? 'Animal not named' : name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              [
                r['breed'],
                r['variety'],
                r['class_name'],
                r['sex'],
              ].where((v) => v != null && v.toString().isNotEmpty).join(' • '),
            ),
            if (r['is_fur'] == true) const Text('Fur / wool result'),
            if (placement != null && placement.toString().isNotEmpty)
              Text('Placement: $placement'),
            if (r['result_status'] != null)
              Text('Result: ${r['result_status']}'),
            if (r['is_disqualified'] == true)
              Text(
                'Disqualified: ${r['disqualified_reason'] ?? 'Reason not recorded'}',
              ),
            if (r['scratched_at'] != null) const Text('Scratched'),
            if (awards.isNotEmpty) Text('Awards: ${awards.join(', ')}'),
            if (r['special_awards'] != null &&
                r['special_awards'].toString().isNotEmpty)
              Text('Special awards: ${r['special_awards']}'),
            if (r['fur_award'] != null) Text('Fur award: ${r['fur_award']}'),
            if (row['source_available'] == false)
              const Text(
                'Previous result — no current report available in Show.',
              ),
            if (row['animal_id'] == null)
              const Text(
                'Not linked to an animal. The result is retained here.',
              ),
            if (onAnimal != null)
              TextButton(onPressed: onAnimal, child: const Text('View animal')),
          ],
        ),
      ),
    );
  }
}
