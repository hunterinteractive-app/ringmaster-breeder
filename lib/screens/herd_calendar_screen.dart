import '../services/herd_calendar_service.dart';
import '../widgets/calendar_subscription_dialog.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/herd_calendar.dart';
import '../utils/animal_labels.dart';
import '../widgets/ringmaster_page_shell.dart';
import '../theme/app_theme.dart';
import 'breeding_tracker_screen.dart';
import 'health_records_screen.dart';

class HerdCalendarScreen extends StatefulWidget {
  final String ringId;
  final Widget? herdPicker;
  final Future<List<HerdCalendarEvent>> Function(CalendarWindow)? windowLoader;
  final Future<List<HerdCalendarEvent>> Function()? loader;
  const HerdCalendarScreen({
    super.key,
    required this.ringId,
    this.loader,
    this.windowLoader,
    this.herdPicker,
  });
  @override
  State<HerdCalendarScreen> createState() => _HerdCalendarScreenState();
}

class _HerdCalendarScreenState extends State<HerdCalendarScreen> {
  DateTime selected = calendarDate(DateTime.now());
  late DateTime month = DateTime(selected.year, selected.month);
  List<HerdCalendarEvent> events = [];
  bool loading = true;
  String? error, showNotice;
  String filter = 'All';
  bool agenda = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  int _request = 0;
  @override
  void didUpdateWidget(covariant HerdCalendarScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ringId != widget.ringId) load();
  }

  Future<void> load() async {
    final request = ++_request;
    final window = CalendarWindow.around(month);
    setState(() {
      loading = true;
      events = [];
      error = null;
      showNotice = null;
    });
    try {
      final value = widget.windowLoader != null
          ? await widget.windowLoader!(window)
          : widget.loader != null
          ? await widget.loader!()
          : await HerdCalendarService(
              Supabase.instance.client,
            ).load(widget.ringId, window);
      if (!mounted || request != _request) return;
      String? notice;
      if (widget.loader == null && widget.windowLoader == null) {
        try {
          final response = await Supabase.instance.client.functions.invoke(
            'show-calendar',
            body: {
              'ring_id': widget.ringId,
              'start_date': HerdCalendarService.day(window.start),
              'end_date': HerdCalendarService.day(window.end),
            },
          );
          final data = Map<String, dynamic>.from(response.data as Map);
          if (data['error'] != null) {
            throw StateError(data['error']);
          }
          value.addAll(
            enteredShowEvents(
              List<Map<String, dynamic>>.from(data['shows'] ?? []),
            ),
          );
          notice = data['connected'] == true
              ? 'Entered shows and favorite deadlines refreshed from RingMaster Show.'
              : 'Connect RingMaster Show in Account to see your entered shows and favorite deadlines here.';
        } catch (_) {
          notice =
              'Entered shows could not refresh. Herd dates are available; use Refresh to try again.';
        }
      }
      if (!mounted || request != _request) return;
      final bounded = value.where(window.includes).toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      setState(() {
        events = bounded;
        showNotice = notice;
      });
    } catch (_) {
      if (mounted && request == _request) {
        setState(() => error = 'Unable to load calendar. Please try again.');
      }
    } finally {
      if (mounted && request == _request) setState(() => loading = false);
    }
  }

  Future<void> open(HerdCalendarEvent event) async {
    if (event.show != null) {
      final show = event.show!;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(event.title),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (show['calendar_kind'] == 'deadline')
                    Text(event.note ?? ''),
                  Text(
                    '${DateFormat('MM-dd-yy').format(calendarDate(show['start_date']))}${show['end_date'] == null ? '' : ' – ${DateFormat('MM-dd-yy').format(calendarDate(show['end_date']))}'}',
                  ),
                  if (show['location_name'] != null)
                    Text(show['location_name']),
                  if (show['location_address'] != null)
                    Text(show['location_address']),
                  const SizedBox(height: 16),
                  Text(
                    '${show['entry_count']} active entries',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (final e in show['entries'] as List? ?? [])
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(animalTitle(e['animal_name'], e['tattoo'])),
                      subtitle: Text(
                        [
                              e['exhibitor_name'],
                              e['breed'],
                              e['variety'],
                              e['class_name'],
                              e['sex'],
                            ]
                            .where((v) => v != null && v.toString().isNotEmpty)
                            .join(' • '),
                      ),
                    ),
                  const Text(
                    'Manage these entries in RingMaster Show. Refresh the calendar to receive changes.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
      return;
    }
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
    'Shows' => const Color(0xFF996A27),
    'Health' => const Color(0xFF337665),
    'Birth' => BreederColors.primary,
    'Weaning' => const Color(0xFF576BA0),
    'Palpation' => const Color(0xFF996A27),
    'Nesting' => const Color(0xFF805A8B),
    _ => const Color(0xFF5C6874),
  };
  void move(int delta) {
    setState(() {
      month = DateTime(month.year, month.month + delta);
      selected = month;
    });
    load();
  }

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
      isCalendarPage: true,
      onRefresh: load,
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (widget.herdPicker != null) widget.herdPicker!,
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    CalendarSubscriptionDialog(ringId: widget.ringId),
              ),
              icon: const Icon(Icons.phonelink),
              label: const Text('Connect device calendar'),
            ),
          ),
          Text(
            'Your herd, day by day',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          const Text(
            'Breeding, health, shows and favorite entry deadlines. Expected dates follow your breeding settings.',
          ),
          if (showNotice != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(showNotice!),
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
                'Shows',
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
                        onPressed: () {
                          setState(() {
                            selected = calendarDate(DateTime.now());
                            month = DateTime(selected.year, selected.month);
                          });
                          load();
                        },
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
                    event.category == 'Shows'
                        ? Icons.emoji_events_outlined
                        : event.category == 'Health'
                        ? Icons.medical_services_outlined
                        : Icons.event,
                    color: color(event.category),
                  ),
                ),
                title: Text(event.title),
                subtitle: Text(
                  '${event.animal}\n${DateFormat('MM-dd-yy').format(event.start)}${event.start == event.end ? '' : ' – ${DateFormat('MM-dd-yy').format(event.end)}'}${event.estimated ? ' • Expected' : ''}${event.note == null ? '' : '\n${event.note}'}',
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
