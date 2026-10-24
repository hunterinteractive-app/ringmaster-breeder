import '../screens/production_measurements_screen.dart';
import 'adaptive_layout.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../utils/animal_labels.dart';
import '../utils/litter_lifecycle.dart';
import 'breeding_settings_dialog.dart';

class BreedingDashboard extends StatelessWidget {
  final List<Map<String, dynamic>> records;
  final Map<String, Map<String, dynamic>> settings;
  final String filter;
  final ValueChanged<String> onFilter;
  final ValueChanged<Map<String, dynamic>> onEdit, onOffspring;
  final ValueChanged<String> onOpen;
  const BreedingDashboard({
    super.key,
    required this.records,
    required this.settings,
    required this.filter,
    required this.onFilter,
    required this.onEdit,
    required this.onOffspring,
    required this.onOpen,
  });
  Map<String, dynamic> config(Map<String, dynamic> r) =>
      settings[r['dam']['species']] ?? breedingDefaults(r['dam']['species']);
  Map tracking(Map r) => r['tracking'] as Map? ?? {};
  DateTime get today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  String date(dynamic v) =>
      DateFormat('MMM d').format(v is DateTime ? v : DateTime.parse(v));
  String window(DateTime base, int a, int b) => a == b
      ? date(breedingDay(base, a))
      : '${date(breedingDay(base, a))} – ${date(breedingDay(base, b))}';
  bool dueSoon(Map<String, dynamic> r) {
    final c = config(r);
    final start = DateTime.tryParse(r['breeding_date']?.toString() ?? '');
    if (start == null) return false;
    return tracking(r)['breeding_occurred'] != false &&
        r['status'] == 'active' &&
        tracking(r)['birth_date'] == null &&
        !breedingDay(start, c['gestation_max']).isBefore(today) &&
        !breedingDay(start, c['gestation_min']).isAfter(breedingDay(today, 7));
  }

  Widget stat(
    String label,
    int value,
    IconData icon,
    Color color,
    double width,
    bool compact,
  ) => Container(
    width: width,
    padding: EdgeInsets.all(compact ? 12 : 18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      children: [
        Container(
          padding: EdgeInsets.all(compact ? 6 : 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: compact ? 20 : 24),
        ),
        SizedBox(width: compact ? 8 : 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: TextStyle(
                  fontSize: compact ? 20 : 28,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: BreederColors.text),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final active = records.where((r) => r['status'] == 'active').toList();
    final rows = records
        .where(
          (r) =>
              filter == 'All' ||
              (filter == 'Grow out'
                  ? litterIsGrowingOut(r)
                  : filter == 'Active'
                  ? r['status'] == 'active'
                  : r['status'] != 'active'),
        )
        .toList();
    rows.sort(
      (a, b) => (a['breeding_date'] ?? '9999').toString().compareTo(
        (b['breeding_date'] ?? '9999').toString(),
      ),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final compact = BreederLayout.compact(context);
        final width = box.maxWidth - (compact ? 24 : 40);
        final columns = width >= 1050
            ? 3
            : width >= 720
            ? 2
            : 1;
        final cardWidth = (width - (columns - 1) * 16) / columns;
        final statsColumns = width >= 760
            ? 4
            : width >= 280
            ? 2
            : 1;
        final statWidth = (width - (statsColumns - 1) * 12) / statsColumns;
        return SingleChildScrollView(
          padding: BreederLayout.pagePadding(context, normal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your breeding overview',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'From pairing to grow out • ${DateFormat('EEEE, MMMM d').format(today)}',
                style: const TextStyle(color: Color(0xFF606B7C)),
              ),
              const AdaptiveGap(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  stat(
                    'Active breedings',
                    active.length,
                    Icons.favorite_outline,
                    BreederColors.primary,
                    statWidth,
                    compact,
                  ),
                  stat(
                    'Birth window · next 7 days',
                    records.where(dueSoon).length,
                    Icons.event_available,
                    const Color(0xFF9C681A),
                    statWidth,
                    compact,
                  ),
                  stat(
                    'Nursing litters',
                    active
                        .where(
                          (r) =>
                              tracking(r)['birth_date'] != null &&
                              tracking(r)['wean_date'] == null,
                        )
                        .length,
                    Icons.child_care,
                    const Color(0xFF326C5D),
                    statWidth,
                    compact,
                  ),
                  stat(
                    'Kits & pups weaned',
                    records
                        .where((r) => r['status'] != 'cancelled')
                        .fold<int>(
                          0,
                          (n, r) => n + ((tracking(r)['weaned'] ?? 0) as int),
                        ),
                    Icons.pets_outlined,
                    BreederColors.text,
                    statWidth,
                    compact,
                  ),
                ],
              ),
              const AdaptiveGap(height: 24),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Breeding & litter cards',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final f in ['Active', 'Grow out', 'History', 'All'])
                        ChoiceChip(
                          label: Text(f),
                          selected: filter == f,
                          onSelected: (_) => onFilter(f),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${rows.length} records • Earliest expected birth first',
                style: const TextStyle(fontSize: 12, color: Color(0xFF606B7C)),
              ),
              const AdaptiveGap(height: 16),
              if (rows.isEmpty)
                const Card(
                  child: AdaptivePadding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No breedings here yet. Start with Actions → Record breeding in your Herd.',
                    ),
                  ),
                ),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final r in rows)
                    SizedBox(width: cardWidth, child: card(context, r)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget event(
    IconData icon,
    String label,
    String value, {
    bool emphasize = false,
  }) => AdaptivePadding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 18,
          color: emphasize ? BreederColors.primary : const Color(0xFF7B8495),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: Color(0xFF687286)),
              ),
              Text(
                value,
                style: TextStyle(
                  fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget card(BuildContext context, Map<String, dynamic> r) {
    final t = tracking(r),
        dam = r['dam'] as Map,
        sire = r['sire'] as Map? ?? {},
        c = config(r);
    final start = DateTime.tryParse(r['breeding_date']?.toString() ?? '');
    final born = t['birth_date'] != null;
    final weaned = t['wean_date'] != null;
    final isActive = r['status'] == 'active';
    final cavy = dam['species'] == 'cavy';
    final children = r['offspring'] as List? ?? [];
    final elapsed = start == null
        ? 0
        : DateTime.utc(
            today.year,
            today.month,
            today.day,
          ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
    final stage = breedingStage(r);
    final tone = born ? const Color(0xFF326C5D) : BreederColors.primary;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE3E5E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 5, color: tone),
          AdaptivePadding(
            padding: BreederLayout.pagePadding(context, normal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: tone.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        stage,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: tone,
                        ),
                      ),
                    ),
                    if (dueSoon(r))
                      const Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          'Birth window soon',
                          style: TextStyle(fontSize: 11),
                        ),
                        backgroundColor: Color(0xFFFFF1D7),
                        side: BorderSide.none,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  animalTitle(dam['name'], dam['tattoo']),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: BreederColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${dam['breed'] ?? ''} • ${cavy ? 'Cavy' : 'Rabbit'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF687286),
                  ),
                ),
                const AdaptiveGap(height: 12),
                Text(
                  'SIRE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: tone,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  sire.isEmpty
                      ? 'Unknown sire'
                      : animalTitle(sire['name'], sire['tattoo']),
                  style: const TextStyle(fontSize: 13),
                ),
                const AdaptiveGap(height: 16),
                if (!born &&
                    isActive &&
                    start != null &&
                    t['breeding_occurred'] != false) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          elapsed < 0
                              ? 'Scheduled pairing'
                              : 'Day $elapsed of gestation',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${c['gestation_min']}–${c['gestation_max']} days',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF687286),
                        ),
                      ),
                    ],
                  ),
                  const AdaptiveGap(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (elapsed / (c['gestation_max'] as int)).clamp(
                        0.0,
                        1.0,
                      ),
                      minHeight: 6,
                      color: tone,
                      backgroundColor: const Color(0xFFF0E6E9),
                    ),
                  ),
                  if (t['cage'] != null && t['cage'] != '')
                    Text('Litter cage: ${t['cage']}'),
                  if ([
                        'paired_date',
                        'split_date',
                        'scheduled_breeding_date',
                        'nest_installed',
                        'nest_removed',
                        'rebreeding_enabled',
                        'rebreeding_overridden',
                        'added',
                        'raised',
                        'bucks',
                        'does',
                        'kept',
                        'sold',
                        'show_quality',
                      ].any((k) => t[k] != null) ||
                      (t['custom_fields'] as Map? ?? {}).isNotEmpty)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Litter details'),
                      children: [
                        for (final e in const {
                          'paired_date': 'Paired',
                          'split_date': 'Separated / split',
                          'scheduled_breeding_date': 'Scheduled rebreeding',
                        }.entries)
                          if (t[e.key] != null)
                            ListTile(
                              dense: true,
                              title: Text(e.value),
                              trailing: Text(date(t[e.key])),
                            ),
                        for (final e in const {
                          'nest_installed': 'Nest box installed',
                          'nest_removed': 'Nest box removed',
                          'rebreeding_enabled': 'Rebreeding enabled',
                          'rebreeding_overridden':
                              'Rebreeding schedule overridden',
                        }.entries)
                          if (t[e.key] != null)
                            ListTile(
                              dense: true,
                              title: Text(e.value),
                              trailing: Text(t[e.key] == true ? 'Yes' : 'No'),
                            ),
                        for (final e in const {
                          'added': 'Added / fostered in',
                          'raised': 'Raised',
                          'bucks': 'Bucks in litter',
                          'does': 'Does in litter',
                          'kept': 'Kept',
                          'sold': 'Sold',
                          'show_quality': 'Show quality',
                        }.entries)
                          if (t[e.key] != null)
                            ListTile(
                              dense: true,
                              title: Text(e.value),
                              trailing: Text('${t[e.key]}'),
                            ),
                        for (final e
                            in (t['custom_fields'] as Map? ?? {}).entries)
                          ListTile(
                            title: Text(e.key.toString()),
                            subtitle: Text(e.value.toString()),
                          ),
                      ],
                    ),
                  const SizedBox(height: 10),
                  if (elapsed > c['gestation_max'])
                    const Text(
                      'Past estimated birth window',
                      style: TextStyle(fontSize: 12, color: Color(0xFF9C681A)),
                    ),
                ],
                event(
                  Icons.favorite_outline,
                  'Bred',
                  start == null
                      ? 'Not recorded'
                      : DateFormat('MMM d, yyyy').format(start),
                ),
                if (!born &&
                    start != null &&
                    t['breeding_occurred'] != false) ...[
                  event(
                    Icons.event_available,
                    'Expected birth window',
                    window(start, c['gestation_min'], c['gestation_max']),
                    emphasize: true,
                  ),
                  event(
                    Icons.task_alt,
                    'Palpation window',
                    window(start, c['palpation_min'], c['palpation_max']),
                  ),
                  if (c['nesting_day'] != null && t['nest_installed'] != true)
                    event(
                      Icons.home_outlined,
                      'Nesting box',
                      date(breedingDay(start, c['nesting_day'])),
                    ),
                ],
                event(
                  Icons.fact_check_outlined,
                  'Palpation result',
                  '${t['palpation_source'] != null && (t['check_result'] ?? 'Not checked') == 'Not checked' ? 'Previous result: ${t['palpation_source']}' : t['check_result'] ?? 'Not checked'}${t['check_date'] == null ? '' : ' • ${date(t['check_date'])}'}',
                ),
                if (born) ...[
                  event(
                    Icons.child_care,
                    cavy ? 'Pups born' : 'Kits kindled',
                    '${date(t['birth_date'])} • ${(r['import_source'] == null ? t['born_alive'] : t['born_total']) ?? 'Unknown'} ${r['import_source'] == null ? 'alive' : 'born (source)'} • ${t['born_dead'] ?? 'Unknown'} stillborn',
                    emphasize: true,
                  ),
                  event(
                    Icons.event_note,
                    weaned ? 'Weaned' : 'Expected weaning',
                    weaned
                        ? '${date(t['wean_date'])} • ${t['weaned'] ?? 'Unknown'} ${cavy ? 'pups' : 'kits'}'
                        : window(
                            DateTime.parse(t['birth_date']),
                            c['weaning_min'] * 7,
                            c['weaning_max'] * 7,
                          ),
                  ),
                ],
                if (t['recorded_deaths'] != null)
                  Text(
                    'Recorded deaths: ${t['recorded_deaths']} (litter total)',
                  ),
                if (t['weaned_males'] != null)
                  Text(
                    '${t['weaned_males']} ${cavy ? 'boars' : 'bucks'} • ${t['weaned_females']} ${cavy ? 'sows' : 'does'}',
                  ),
                if (litterIsGrowingOut(r))
                  event(
                    Icons.grass_outlined,
                    'Growing out together',
                    '${litterUnrecordedCount(r)} ${cavy ? 'pups' : 'kits'} • ${children.length} with individual records',
                    emphasize: true,
                  ),
                if ((r['notes'] ?? '').toString().isNotEmpty ||
                    (t['notes'] ?? '').toString().isNotEmpty)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 12),
                    dense: true,
                    title: const Text('Notes', style: TextStyle(fontSize: 12)),
                    children: [
                      if ((r['notes'] ?? '').toString().isNotEmpty)
                        Text(r['notes'], style: const TextStyle(fontSize: 12)),
                      if ((t['notes'] ?? '').toString().isNotEmpty)
                        Text(t['notes'], style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ProductionMeasurementsScreen(recordId: r['id']),
                      ),
                    ),
                    icon: const Icon(Icons.monitor_weight_outlined),
                    label: Text(
                      litterIsGrowingOut(r)
                          ? 'Grow-out weights & feed'
                          : 'Litter weights & feed',
                    ),
                  ),
                ),
                if (r['import_record'] is Map)
                  ExpansionTile(
                    title: const Text('Original litter details'),
                    children: [
                      for (final e in (r['import_record'] as Map).entries)
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: SelectableText('${e.key}: ${e.value}'),
                        ),
                    ],
                  ),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => onEdit(r),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Update tracking'),
                  ),
                ),
                if (r['status'] != 'cancelled' &&
                    (r['import_source'] != null ||
                        (t['weaned'] ?? 0) > children.length))
                  TextButton.icon(
                    onPressed: () => onOffspring(r),
                    icon: const Icon(Icons.add),
                    label: Text(
                      r['import_source'] == null
                          ? (litterIsGrowingOut(r)
                                ? 'Create individual records'
                                : 'Create offspring records')
                          : 'Manage offspring',
                    ),
                  ),
                if (children.isNotEmpty) ...[
                  const AdaptiveGap(height: 12),
                  Text(
                    '${children.where((c) => animalIsMale(c['animal']?['sex'] ?? '')).length} ${cavy ? 'boars' : 'bucks'} • ${children.where((c) => !animalIsMale(c['animal']?['sex'] ?? '')).length} ${cavy ? 'sows' : 'does'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final child in children)
                        ActionChip(
                          label: Text(
                            animalTitle(
                              child['animal']?['name'],
                              child['animal']?['tattoo'],
                            ),
                          ),
                          onPressed: () => onOpen(child['animal_id']),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
