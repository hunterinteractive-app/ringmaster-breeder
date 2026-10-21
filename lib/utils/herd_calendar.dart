import 'package:intl/intl.dart';
import 'animal_labels.dart';
import '../widgets/breeding_settings_dialog.dart';

DateTime calendarDate(dynamic value) {
  final d = value is DateTime ? value : DateTime.parse(value.toString());
  return DateTime(d.year, d.month, d.day);
}

class HerdCalendarEvent {
  final String title, animal, category, animalId;
  final DateTime start, end;
  final bool estimated;
  final String? note;
  final Map<String, dynamic>? breeding;
  final Map<String, dynamic>? show;
  const HerdCalendarEvent({
    required this.title,
    required this.animal,
    required this.category,
    required this.animalId,
    required this.start,
    required this.end,
    this.estimated = false,
    this.note,
    this.breeding,
    this.show,
  });
  bool occursOn(DateTime day) => !day.isBefore(start) && !day.isAfter(end);
}

List<HerdCalendarEvent> herdCalendarEvents(
  List<Map<String, dynamic>> breedings,
  Map<String, Map<String, dynamic>> settings,
  List<Map<String, dynamic>> health,
) {
  final events = <HerdCalendarEvent>[];
  for (final r in breedings) {
    final dam = r['dam'] as Map;
    final t = r['tracking'] as Map? ?? {};
    final status = t['status'] ?? r['status'];
    if (status == 'cancelled') continue;
    final c = {
      ...breedingDefaults(dam['species']),
      ...?settings[dam['species']],
    };
    final base = r['breeding_date'] == null
        ? null
        : calendarDate(r['breeding_date']);
    void add(
      String title,
      String category,
      DateTime start, [
      DateTime? end,
      bool estimated = false,
    ]) {
      final finish = end ?? start;
      final hasWindow = finish != start;
      final note = hasWindow
          ? 'Expected window: ${DateFormat('MM-dd-yy').format(start)} – ${DateFormat('MM-dd-yy').format(finish)}. Based on your herd’s breeding settings; actual dates may vary.'
          : null;
      for (final date in hasWindow ? [start, finish] : [start]) {
        events.add(
          HerdCalendarEvent(
            title: hasWindow
                ? '$title • ${date == start ? 'Due window starts' : 'Final due day'}'
                : title,
            category: category,
            animal: animalTitle(dam['name'], dam['tattoo']),
            animalId: dam['id'],
            start: date,
            end: date,
            note: note,
            estimated: estimated,
            breeding: r,
          ),
        );
      }
    }

    if (base != null && t['breeding_occurred'] != false) {
      add('Breeding recorded', 'Breeding', base);
    }
    if (t['paired_date'] != null) {
      add('Paired', 'Breeding', calendarDate(t['paired_date']));
    }
    if (t['split_date'] != null) {
      add('Separated / split', 'Breeding', calendarDate(t['split_date']));
    }
    if (t['scheduled_breeding_date'] != null &&
        t['rebreeding_enabled'] != false &&
        status == 'active') {
      add(
        'Scheduled rebreeding',
        'Breeding',
        calendarDate(t['scheduled_breeding_date']),
      );
    }
    if (t['breeding_occurred'] == false && base != null && status == 'active') {
      add('Scheduled breeding', 'Breeding', base);
    }
    if (t['check_date'] != null) {
      add(
        'Palpation • ${t['check_result'] ?? 'Recorded'}',
        'Palpation',
        calendarDate(t['check_date']),
      );
    }
    if (t['birth_date'] != null) {
      final birth = calendarDate(t['birth_date']);
      add(dam['species'] == 'cavy' ? 'Pups born' : 'Kindled', 'Birth', birth);
      if (t['wean_date'] == null && status == 'active') {
        add(
          'Expected weaning',
          'Weaning',
          breedingDay(birth, c['weaning_min'] * 7),
          breedingDay(birth, c['weaning_max'] * 7),
          true,
        );
      }
    } else if (base != null &&
        t['breeding_occurred'] != false &&
        status == 'active' &&
        t['check_result'] != 'Negative') {
      if (t['check_date'] == null) {
        add(
          'Palpation window',
          'Palpation',
          breedingDay(base, c['palpation_min']),
          breedingDay(base, c['palpation_max']),
          true,
        );
      }
      if (c['nesting_day'] != null && t['nest_installed'] != true) {
        add(
          'Add nesting box',
          'Nesting',
          breedingDay(base, c['nesting_day']),
          null,
          true,
        );
      }
      add(
        'Expected birth',
        'Birth',
        breedingDay(base, c['gestation_min']),
        breedingDay(base, c['gestation_max']),
        true,
      );
    }
    if (t['wean_date'] != null) {
      add('Weaned', 'Weaning', calendarDate(t['wean_date']));
    }
  }
  for (final h in health) {
    final a = h['animal'] as Map;
    for (final field in [
      'administered_date',
      'readminister_date',
      'expires_date',
    ]) {
      if (h[field] == null) continue;
      final d = calendarDate(DateTime.parse(h[field].toString()).toLocal());
      final prefix = field == 'readminister_date'
          ? 'Follow-up due'
          : field == 'expires_date'
          ? 'Expires'
          : 'Health record';
      events.add(
        HerdCalendarEvent(
          title: '$prefix • ${h['title'] ?? h['record_type'] ?? 'Health'}',
          animal: animalTitle(a['name'], a['tattoo']),
          category: 'Health',
          animalId: a['id'],
          start: d,
          end: d,
        ),
      );
    }
  }
  events.sort((a, b) {
    final date = a.start.compareTo(b.start);
    return date != 0 ? date : a.animal.compareTo(b.animal);
  });
  return events;
}

List<HerdCalendarEvent> enteredShowEvents(List<Map<String, dynamic>> shows) {
  final seen = <String>{};
  return [
    for (final show in shows)
      if (show['start_date'] != null &&
          (show['entry_count'] as num? ?? 0) > 0 &&
          seen.add(show['id'].toString()))
        HerdCalendarEvent(
          title: show['name'] ?? 'Entered show',
          animal: '${show['entry_count']} active entries • RingMaster Show',
          category: 'Shows',
          animalId: '',
          start: calendarDate(show['start_date']),
          end: calendarDate(show['start_date']),
          show: show,
          note: [
            if ((show['location_name'] ?? '').toString().isNotEmpty)
              show['location_name'],
            if (show['end_date'] != null &&
                show['end_date'] != show['start_date'])
              'Show dates: ${DateFormat('MM-dd-yy').format(calendarDate(show['start_date']))} – ${DateFormat('MM-dd-yy').format(calendarDate(show['end_date']))}',
            'Entered shows for this herd owner’s linked account.',
          ].join(' • '),
        ),
    for (final show in shows)
      if (show['is_favorite'] == true &&
          show['entry_close_at'] != null &&
          seen.add('deadline-${show['id']}'))
        HerdCalendarEvent(
          title: 'Entry deadline • ${show['name'] ?? 'Favorite show'}',
          animal: 'Favorite show • RingMaster Show',
          category: 'Shows',
          animalId: '',
          start: calendarDate(DateTime.parse(show['entry_close_at']).toLocal()),
          end: calendarDate(DateTime.parse(show['entry_close_at']).toLocal()),
          show: {...show, 'calendar_kind': 'deadline'},
          note:
              'Entries close ${DateFormat('MM-dd-yy h:mm a').format(DateTime.parse(show['entry_close_at']).toLocal())} (your local time). Device calendar alerts: 1 day and 2 hours before; support depends on your calendar app.',
        ),
  ];
}
