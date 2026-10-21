import '../widgets/managed_record_dialogs.dart';
import '../services/sales_service.dart';
import '../widgets/adaptive_layout.dart';
import '../offline/offline_runtime.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/family_service.dart';
import '../services/show_report_service.dart';
import '../widgets/ringmaster_page_shell.dart';
import 'animal_detail_screen.dart';
import '../utils/show_results.dart';

String reportDate(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date == null
      ? 'Date not recorded'
      : DateFormat('MMM d, yyyy').format(date);
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
      var query = OfflineRuntime.client
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
        final animal = await OfflineRuntime.client
            .from('animals')
            .select('ring_id')
            .eq('id', widget.animalId!)
            .single();
        final herd = await OfflineRuntime.client
            .from('farms')
            .select('owner_id')
            .eq('id', animal['ring_id'])
            .single();
        ownerId = herd['owner_id'] as String;
      } else if (widget.ownAccount) {
        final own = await OfflineRuntime.client
            .from('users')
            .select('id')
            .eq('auth_user_id', OfflineRuntime.client.auth.currentUser!.id)
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

  Future<void> editResult([Map<String, dynamic>? row]) async {
    if (ownerId == null) return;
    try {
      final herds = await OfflineRuntime.client
          .from('farms')
          .select('id')
          .eq('owner_id', ownerId!)
          .eq('is_demo', false);
      final animals = <Map<String, dynamic>>[];
      if (herds.isNotEmpty) {
        for (var from = 0; ; from += 500) {
          var query = OfflineRuntime.client
              .from('animals')
              .select('id,name,tattoo')
              .inFilter('ring_id', herds.map((h) => h['id']).toList());
          if (widget.animalId != null) query = query.eq('id', widget.animalId!);
          final page = await query
              .order('name')
              .order('id')
              .range(from, from + 499);
          animals.addAll(List<Map<String, dynamic>>.from(page));
          if (page.length < 500) break;
        }
      }
      if (animals.isEmpty && row == null) {
        throw StateError('Add an animal before recording a show result.');
      }
      final id = row?['id'] as String? ?? SalesService.newId();
      if (!mounted) return;
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ShowResultEditorDialog(
          initial: row ?? {},
          animals: animals,
          writer: (animal, data) async {
            await OfflineRuntime.client.rpc(
              'save_managed_show_result',
              params: {
                'p_id': id,
                'p_animal': animal,
                'p_data': data,
                'p_revision': row?['revision'] ?? 0,
              },
            );
          },
        ),
      );
      if (saved == true) await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is StateError
                  ? e.message.toString()
                  : 'Unable to open the show editor. Reconnect and retry.',
            ),
          ),
        );
      }
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
      if (!['https', 'blob'].contains(uri.scheme) ||
          !await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
            webOnlyWindowName: '_self',
          )) {
        throw StateError('Unable to open');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is StateError
                  ? error.message.toString()
                  : 'Unable to open this report. Refresh and try again.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    title: widget.animalId == null ? 'Show reports' : 'Animal show history',
    onRefresh: busy ? null : load,
    floatingActionButton: busy
        ? null
        : FloatingActionButton(
            onPressed: () => editResult(),
            tooltip: 'Add show result',
            child: const Icon(Icons.add),
          ),
    body: ListView(
      padding: BreederLayout.pagePadding(context, normal: 24),
      children: [
        if (busy) const LinearProgressIndicator(),
        if (message != null)
          AdaptivePadding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(message!),
          ),
        Container(
          padding: BreederLayout.pagePadding(context, normal: 24),
          decoration: BoxDecoration(
            color: const Color(0xFF42101A),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.emoji_events_outlined, color: Color(0xFFE8CB8E)),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'From the show table',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: BreederLayout.compact(context) ? 20 : 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const AdaptiveGap(height: 8),
              const Text(
                'Placings, awards and the reports behind them.',
                style: TextStyle(color: Colors.white70),
              ),
              const AdaptiveGap(height: 22),
              Wrap(
                spacing: BreederLayout.compact(context) ? 16 : 28,
                runSpacing: 12,
                children: [
                  _summary('${results.length}', 'Entries'),
                  _summary(
                    '${results.where((r) => pedigreeWins(r).isNotEmpty).length}',
                    'Major-win entries',
                  ),
                  _summary(
                    '${reports.where((r) => r['source_available'] != false).length}',
                    'Reports',
                  ),
                ],
              ),
            ],
          ),
        ),
        const AdaptiveGap(height: 24),
        Text('Show results', style: Theme.of(context).textTheme.headlineSmall),
        const AdaptiveGap(height: 8),
        if (!busy && results.isEmpty)
          const Card(
            child: AdaptivePadding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Your show results will appear here once reports are available.',
              ),
            ),
          ),
        for (final row in results)
          ShowResultCard(
            row: row,
            onEdit:
                [
                  'rabbit_register',
                  'breeder_manual',
                ].contains(row['source_app'])
                ? () => editResult(row)
                : null,
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
        const AdaptiveGap(height: 24),
        Card(
          child: ExpansionTile(
            initiallyExpanded: results.isEmpty,
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Reports & ARBA legs'),
            subtitle: Text(
              '${reports.length} files • Original reports from Show',
            ),
            children: [
              if (!busy && reports.isEmpty)
                const AdaptivePadding(
                  padding: EdgeInsets.all(20),
                  child: Text('No report files received yet.'),
                ),
              for (final row in reports)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 8,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFF6E8E9),
                    child: Icon(
                      row['record']['report_name'] == 'legs'
                          ? Icons.workspace_premium_outlined
                          : Icons.picture_as_pdf_outlined,
                      color: const Color(0xFF42101A),
                    ),
                  ),
                  title: Text(
                    row['record']['show_name'] ?? 'Show report',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
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
            ],
          ),
        ),
      ],
    ),
  );
  Widget _summary(String value, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: TextStyle(
          color: Colors.white,
          fontSize: BreederLayout.compact(context) ? 20 : 28,
          fontWeight: FontWeight.bold,
        ),
      ),
      Text(label, style: TextStyle(color: Colors.white70)),
    ],
  );
}

class ShowResultCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback? onAnimal, onEdit;
  const ShowResultCard({
    super.key,
    required this.row,
    this.onAnimal,
    this.onEdit,
  });
  @override
  Widget build(BuildContext context) {
    final r = Map<String, dynamic>.from(row['record'] as Map);
    final show = r['shows'] is Map ? r['shows'] as Map : {};
    final awards = showAwards(r);
    final placement = showPlacement(r);
    final name = [
      r['animal_name'],
      r['tattoo'],
    ].where((v) => v != null && v.toString().trim().isNotEmpty).join(' • ');
    final hasWins = pedigreeWins(row).isNotEmpty;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 5,
            color: hasWins ? const Color(0xFFB48A42) : const Color(0xFF42101A),
          ),
          AdaptivePadding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      show['name']?.toString() ?? 'Show entry',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Chip(
                      avatar: const Icon(
                        Icons.calendar_today_outlined,
                        size: 16,
                      ),
                      label: Text(reportDate(show['start_date'])),
                      side: BorderSide.none,
                      backgroundColor: const Color(0xFFF2F3F4),
                    ),
                  ],
                ),
                const AdaptiveGap(height: 12),
                Text(
                  name.isEmpty ? 'Animal not named' : name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [r['breed'], r['variety'], r['class_name'], r['sex']]
                      .where((v) => v != null && v.toString().isNotEmpty)
                      .join(' • '),
                ),
                const AdaptiveGap(height: 20),
                Wrap(
                  spacing: 24,
                  runSpacing: 16,
                  children: [
                    Container(
                      width: 170,
                      padding: BreederLayout.pagePadding(context, normal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF6E8E9),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            r['is_fur'] == true
                                ? 'FUR / WOOL PLACING'
                                : 'CLASS PLACING',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                          const AdaptiveGap(height: 8),
                          Text(
                            placingLabel(placement),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF42101A),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AWARDS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                        const AdaptiveGap(height: 8),
                        if (awards.isEmpty)
                          const Text('No awards recorded')
                        else
                          ...awards.map(
                            (a) => AdaptivePadding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Chip(
                                avatar: const Icon(
                                  Icons.emoji_events_outlined,
                                  size: 18,
                                  color: Color(0xFF805C20),
                                ),
                                label: Text(
                                  majorShowAwards[a] == null
                                      ? a
                                      : '$a • ${majorShowAwards[a]}',
                                  maxLines: 2,
                                ),
                                side: BorderSide.none,
                                backgroundColor: const Color(0xFFFAF0D9),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const AdaptiveGap(height: 16),
                if (placement == null && awards.isEmpty)
                  const Text(
                    'Show has not supplied a placing or award for this entry.',
                    style: TextStyle(color: Color(0xFF647086)),
                  ),
                if (r['judge'] != null) Text('Judge: ${r['judge']}'),
                if (r['is_leg'] == true) const Text('ARBA leg recorded'),
                if (r['is_youth'] == true) const Text('Youth show'),
                if (r['number_in_class'] != null)
                  Text('In class: ${r['number_in_class']}'),
                if (r['number_of_exhibitors'] != null)
                  Text('Exhibitors: ${r['number_of_exhibitors']}'),
                if (r['total_shown'] != null)
                  Text('Total shown: ${r['total_shown']}'),
                if (r['other_winnings'] != null)
                  Text('Other winnings: ${r['other_winnings']}'),
                if (r['comments'] != null) Text(r['comments'].toString()),
                if (r['source'] != null) Text('Source: ${r['source']}'),
                if (r['result_status'] != null)
                  Text('Result: ${r['result_status']}'),
                if (r['is_disqualified'] == true)
                  Text(
                    'Disqualified: ${r['disqualified_reason'] ?? 'Reason not recorded'}',
                  ),
                if (r['scratched_at'] != null) const Text('Scratched'),
                if (row['source_available'] == false)
                  const Text(
                    'Previous result — no current report available in Show.',
                  ),
                if (hasWins && row['animal_id'] != null)
                  const AdaptivePadding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Major wins included on pedigree',
                      style: TextStyle(
                        color: Color(0xFF32664C),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (row['animal_id'] == null)
                  const Text(
                    'Not linked to an animal. The result is retained here.',
                  ),
                if (onEdit != null)
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit show result'),
                  ),
                if (onAnimal != null)
                  TextButton.icon(
                    onPressed: onAnimal,
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('View animal'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
