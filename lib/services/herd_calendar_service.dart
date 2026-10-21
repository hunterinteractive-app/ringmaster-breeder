import 'dart:math' as math;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/herd_calendar.dart';
import '../widgets/breeding_settings_dialog.dart';
import 'pagination.dart';

class CalendarWindow {
  final DateTime start, end;
  CalendarWindow.around(DateTime month)
    : start = DateTime(month.year, month.month - 1),
      end = DateTime(month.year, month.month + 2);
  bool includes(HerdCalendarEvent e) =>
      !e.end.isBefore(start) && e.start.isBefore(end);
}

class HerdCalendarService {
  final SupabaseClient client;
  HerdCalendarService(this.client);
  static const breedingColumns =
      '*,dam:animals!breeding_records_dam_id_fkey!inner(*),sire:animals!breeding_records_sire_id_fkey(*),tracking:breeding_tracking(*),offspring:breeding_offspring(*)';
  static String day(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<List<HerdCalendarEvent>> load(
    String ringId,
    CalendarWindow window,
  ) async {
    final saved = await fetchAllPages(
      (a, b) => client
          .from('breeding_settings')
          .select()
          .eq('ring_id', ringId)
          .order('species', ascending: true)
          .range(a, b),
    );
    final settings = {for (final s in saved) s['species'] as String: s};
    var breedingDays = 0, weaningDays = 0;
    for (final species in ['rabbit', 'cavy']) {
      final s = {...breedingDefaults(species), ...?settings[species]};
      for (final key in [
        'gestation_min',
        'gestation_max',
        'palpation_min',
        'palpation_max',
        'nesting_day',
      ]) {
        breedingDays = math.max(breedingDays, (s[key] as int?) ?? 0);
      }
      weaningDays = math.max(weaningDays, (s['weaning_max'] as int) * 7);
    }
    final start = day(window.start), end = day(window.end);
    final birthStart = day(
      DateTime(
        window.start.year,
        window.start.month,
        window.start.day - weaningDays,
      ),
    );
    final results = await Future.wait([
      fetchAllPages(
        (a, b) => client
            .from('breeding_records')
            .select(breedingColumns)
            .eq('dam.ring_id', ringId)
            .gte(
              'breeding_date',
              day(
                DateTime(
                  window.start.year,
                  window.start.month,
                  window.start.day - breedingDays,
                ),
              ),
            )
            .lt('breeding_date', end)
            .order('id', ascending: true)
            .range(a, b),
      ),
      // Tracking dates may fall years after the original breeding date.
      fetchAllPages(
        (a, b) => client
            .from('breeding_tracking')
            .select('breeding:breeding_records!inner($breedingColumns)')
            .eq('breeding.dam.ring_id', ringId)
            .or(
              'and(check_date.gte.$start,check_date.lt.$end),and(wean_date.gte.$start,wean_date.lt.$end),and(birth_date.gte.$birthStart,birth_date.lt.$end),and(paired_date.gte.$start,paired_date.lt.$end),and(split_date.gte.$start,split_date.lt.$end),and(scheduled_breeding_date.gte.$start,scheduled_breeding_date.lt.$end)',
            )
            .order('breeding_id', ascending: true)
            .range(a, b),
      ),
      fetchAllPages(
        (a, b) => client
            .from('animal_health_records')
            .select('*,animal:animals!inner(id,name,tattoo,ring_id)')
            .eq('animal.ring_id', ringId)
            .or(
              [
                for (final f in [
                  'administered_date',
                  'readminister_date',
                  'expires_date',
                ])
                  'and($f.gte.$start,$f.lt.$end)',
              ].join(','),
            )
            .order('id', ascending: true)
            .range(a, b),
      ),
    ]);
    final breedings = {for (final r in results[0]) r['id']: r};
    for (final row in results[1]) {
      final r = Map<String, dynamic>.from(row['breeding'] as Map);
      breedings[r['id']] = r;
    }
    return herdCalendarEvents(
      breedings.values.toList(),
      settings,
      results[2],
    ).where(window.includes).toList();
  }
}
