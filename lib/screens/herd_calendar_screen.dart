import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/herd_calendar.dart';
import '../widgets/ringmaster_page_shell.dart';
import '../theme/app_theme.dart';
import 'breeding_tracker_screen.dart';
import 'health_records_screen.dart';

class HerdCalendarScreen extends StatefulWidget {
  final String ringId;
  final Future<List<HerdCalendarEvent>> Function()? loader;
  const HerdCalendarScreen({super.key, required this.ringId, this.loader});
  @override
  State<HerdCalendarScreen> createState() => _HerdCalendarScreenState();
}

class _HerdCalendarScreenState extends State<HerdCalendarScreen> {
  DateTime selected = calendarDate(DateTime.now());
  late DateTime month = DateTime(selected.year, selected.month);
  List<HerdCalendarEvent> events = [];
  bool loading = true;
  String? error;
  String filter = 'All';
  bool agenda = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<List<Map<String, dynamic>>> pages(dynamic Function(int) query) async {
    final rows = <Map<String, dynamic>>[];
    for (int offset = 0; ; offset += 500) {
      final batch = List<Map<String, dynamic>>.from(await query(offset));
      rows.addAll(batch);
      if (batch.length < 500) return rows;
    }
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (widget.loader != null) {
        final value = await widget.loader!();
        if (mounted) setState(() => events = value);
        return;
      }
      final db = Supabase.instance.client;
      final results = await Future.wait([
        pages(
          (offset) => db
              .from('breeding_records')
              .select(
                '*,dam:animals!breeding_records_dam_id_fkey!inner(*),sire:animals!breeding_records_sire_id_fkey(*),tracking:breeding_tracking(*),offspring:breeding_offspring(*)',
              )
              .eq('dam.ring_id', widget.ringId)
              .order('id')
              .range(offset, offset + 499),
        ),
        pages(
          (offset) => db
              .from('animal_health_records')
              .select('*,animal:animals!inner(id,name,tattoo,ring_id)')
              .eq('animal.ring_id', widget.ringId)
              .order('id')
              .range(offset, offset + 499),
        ),
        pages(
          (offset) => db
              .from('breeding_settings')
              .select()
              .eq('ring_id', widget.ringId)
              .order('species')
              .range(offset, offset + 499),
        ),
      ]);
      final value = herdCalendarEvents(results[0], {
        for (final s in results[2]) s['species']: s,
      }, results[1]);
      if (mounted) setState(() => events = value);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Unable to load calendar. Please try again.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> open(HerdCalendarEvent event) async {
    if (event.breeding != null) {
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => LitterTrackingDialog(record: event.breeding!),
      );
      if (saved == true && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => BreedingTrackerScreen(ringId: widget.ringId),
          ),
        );
      }
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => HealthRecordsScreen(animalId: event.animalId),
        ),
      );
    }
    if (mounted) await load();
  }

  Color color(String category) => switch (category) {
    'Health' => const Color(0xFF337665),
    'Birth' => BreederColors.primary,
    'Weaning' => const Color(0xFF576BA0),
    'Palpation' => const Color(0xFF996A27),
    'Nesting' => const Color(0xFF805A8B),
    _ => const Color(0xFF5C6874),
  };
  void move(int delta) => setState(() {
    month = DateTime(month.year, month.month + delta);
    selected = month;
  });
  @override
  Widget build(BuildContext context) {
    final visible = events
        .where((e) => filter == 'All' || e.category == filter)
        .toList();
    final last = DateTime(month.year, month.month + 1, 0);
    final list = visible
        .where(
          (e) => agenda
              ? !e.end.isBefore(month) && !e.start.isAfter(last)
              : e.occursOn(selected),
        )
        .toList();
    return RingMasterPageShell(
      title: 'Herd calendar',
      onRefresh: load,
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Your herd, day by day',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          const Text(
            'Breeding milestones and health dates, together. Expected dates follow your breeding settings.',
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in [
                'All',
                'Breeding',
                'Palpation',
                'Nesting',
                'Birth',
                'Weaning',
                'Health',
              ])
                ChoiceChip(
                  label: Text(category),
                  selected: filter == category,
                  onSelected: (_) => setState(() => filter = category),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous month',
                        onPressed: () => move(-1),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Text(
                          DateFormat('MMMM yyyy').format(month),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next month',
                        onPressed: () => move(1),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () => setState(() {
                          selected = calendarDate(DateTime.now());
                          month = DateTime(selected.year, selected.month);
                        }),
                        child: const Text('Today'),
                      ),
                      ChoiceChip(
                        label: const Text('Month'),
                        selected: !agenda,
                        onSelected: (_) => setState(() => agenda = false),
                      ),
                      ChoiceChip(
                        label: const Text('Agenda'),
                        selected: agenda,
                        onSelected: (_) => setState(() => agenda = true),
                      ),
                    ],
                  ),
                  if (!agenda) ...[
                    Row(
                      children: [
                        for (final day in [
                          'Sun',
                          'Mon',
                          'Tue',
                          'Wed',
                          'Thu',
                          'Fri',
                          'Sat',
                        ])
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                day,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                      ],
                    ),
                    LayoutBuilder(
                      builder: (context, box) {
                        final offset = month.weekday % 7;
                        final cells = ((offset + last.day) / 7).ceil() * 7;
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: cells,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 7,
                                mainAxisExtent: box.maxWidth < 500 ? 58 : 84,
                              ),
                          itemBuilder: (context, index) {
                            final day = index - offset + 1;
                            if (day < 1 || day > last.day) {
                              return const SizedBox.shrink();
                            }
                            final date = DateTime(month.year, month.month, day);
                            final matches = visible
                                .where((e) => e.occursOn(date))
                                .toList();
                            final active = date == selected;
                            final today = date == calendarDate(DateTime.now());
                            return Semantics(
                              label:
                                  '${DateFormat('MMMM d yyyy').format(date)}, ${matches.length} events',
                              selected: active,
                              child: InkWell(
                                onTap: () => setState(() => selected = date),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  margin: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: active
                                        ? BreederColors.primary
                                        : today
                                        ? const Color(0xFFF8E4E7)
                                        : null,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '$day',
                                        style: TextStyle(
                                          color: active
                                              ? Colors.white
                                              : BreederColors.text,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (matches.isNotEmpty)
                                        Text(
                                          '${matches.length} •',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: active
                                                ? Colors.white
                                                : BreederColors.primary,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (loading) const LinearProgressIndicator(),
          if (error != null)
            Card(
              child: ListTile(
                title: Text(error!),
                trailing: TextButton(
                  onPressed: load,
                  child: const Text('Retry'),
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            agenda ? 'This month' : DateFormat('EEEE, MMMM d').format(selected),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (!loading && error == null && list.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No events for this selection.'),
              ),
            ),
          for (final event in list)
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                leading: CircleAvatar(
                  backgroundColor: color(event.category).withValues(alpha: .12),
                  child: Icon(
                    event.category == 'Health'
                        ? Icons.medical_services_outlined
                        : Icons.event,
                    color: color(event.category),
                  ),
                ),
                title: Text(event.title),
                subtitle: Text(
                  '${event.animal}\n${DateFormat('MM-dd-yy').format(event.start)}${event.start == event.end ? '' : ' – ${DateFormat('MM-dd-yy').format(event.end)}'}${event.estimated ? ' • Expected' : ''}',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => open(event),
              ),
            ),
        ],
      ),
    );
  }
}
