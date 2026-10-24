import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../utils/animal_labels.dart';
import '../utils/grow_out_summary.dart';
import '../utils/production_measurements.dart';
import 'adaptive_layout.dart';

class GrowOutDashboard extends StatefulWidget {
  final List<Map<String, dynamic>> records, measurements;
  final ValueChanged<Map<String, dynamic>> onMeasurements, onOffspring, onEdit;
  const GrowOutDashboard({
    super.key,
    required this.records,
    required this.measurements,
    required this.onMeasurements,
    required this.onOffspring,
    required this.onEdit,
  });
  @override
  State<GrowOutDashboard> createState() => _GrowOutDashboardState();
}

class _GrowOutDashboardState extends State<GrowOutDashboard> {
  String species = 'All', search = '';
  String pounds(double? value) =>
      value == null ? 'Not recorded' : '${measurementText(value)} lb';
  String date(dynamic value) =>
      DateFormat('MMM d, yyyy').format(DateTime.parse(value.toString()));

  Widget metric(
    String label,
    String value,
    String detail,
    IconData icon,
    double width,
  ) => Container(
    width: width,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFE3E5E8)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: BreederColors.primary),
        const SizedBox(height: 12),
        Text(
          value,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: BreederColors.text,
          ),
        ),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          detail,
          style: const TextStyle(fontSize: 12, color: Color(0xFF606B7C)),
        ),
      ],
    ),
  );

  Widget reading(String label, String value, String detail, IconData icon) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: const Color(0xFF326C5D)),
        title: Text('$label: $value'),
        subtitle: Text(detail),
      );

  Widget groupCard(GrowOutGroup group) {
    final r = group.record, t = r['tracking'] as Map;
    final children = r['offspring'] as List? ?? [];
    final male = group.remainingSex(true), female = group.remainingSex(false);
    final birth = DateTime.tryParse(t['birth_date']?.toString() ?? '');
    final today = DateTime.now();
    final age = birth == null
        ? null
        : DateTime.utc(
            today.year,
            today.month,
            today.day,
          ).difference(DateTime.utc(birth.year, birth.month, birth.day)).inDays;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE3E5E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${group.count} growing out',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF326C5D),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            animalTitle(r['dam']['name'], r['dam']['tattoo']),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(
            '${group.cavy ? 'Cavies' : 'Rabbits'} • ${r['dam']['breed'] ?? 'Breed unknown'}',
          ),
          const SizedBox(height: 8),
          Text(
            'Sire: ${r['sire'] == null ? 'Unknown' : animalTitle(r['sire']['name'], r['sire']['tattoo'])}',
          ),
          Text(
            'Weaned ${date(t['wean_date'])}${age == null ? '' : ' • ${age ~/ 7} weeks old'}',
          ),
          if ((t['cage'] ?? '').toString().trim().isNotEmpty)
            Text('Cage: ${t['cage']}'),
          Text(
            male == null || female == null
                ? 'Sex counts not recorded'
                : '$male ${group.cavy ? 'boars' : 'bucks'} • $female ${group.cavy ? 'sows' : 'does'} remaining',
          ),
          Text('${children.length} with individual records'),
          const Divider(height: 28),
          reading(
            'Group weight',
            pounds(group.liveWeight),
            group.weight == null
                ? 'No grow-out weight yet'
                : 'Weighed ${date(group.weight!['recorded_date'])}',
            Icons.monitor_weight_outlined,
          ),
          reading(
            'Cumulative feed',
            pounds(group.cumulativeFeed),
            group.feed == null
                ? 'No grow-out feed reading yet'
                : 'Read ${date(group.feed!['recorded_date'])}',
            Icons.grass_outlined,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => widget.onMeasurements(r),
            icon: const Icon(Icons.add_chart),
            label: const Text('Weights & feed'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => widget.onOffspring(r),
            icon: const Icon(Icons.pets_outlined),
            label: const Text('Create individual records'),
          ),
          TextButton.icon(
            onPressed: () => widget.onEdit(r),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Update litter tracking'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allGroups = growOutGroups(widget.records, widget.measurements);
    final groups = allGroups.where((g) {
      if (species == 'Rabbits' && g.cavy || species == 'Cavies' && !g.cavy) {
        return false;
      }
      final r = g.record;
      return [
        r['dam']?['name'],
        r['dam']?['tattoo'],
        r['sire']?['name'],
        r['sire']?['tattoo'],
        r['tracking']['cage'],
      ].any((v) => (v ?? '').toString().toLowerCase().contains(search));
    }).toList();
    final summary = GrowOutSummary(groups);
    return LayoutBuilder(
      builder: (context, box) {
        final padding = BreederLayout.pagePadding(context, normal: 20);
        final width = box.maxWidth - padding.horizontal;
        final columns = width >= 760
            ? 4
            : width >= 280
            ? 2
            : 1;
        final metricWidth = (width - (columns - 1) * 12) / columns;
        final groupColumns = width >= 720 ? 2 : 1;
        final groupWidth = (width - (groupColumns - 1) * 16) / groupColumns;
        return SingleChildScrollView(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Grow-out overview',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Follow your weaned groups and choose which youngsters receive their own records.',
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in ['All', 'Rabbits', 'Cavies'])
                    ChoiceChip(
                      label: Text(s),
                      selected: species == s,
                      onSelected: (_) => setState(() => species = s),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Search dam, sire or cage',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) =>
                    setState(() => search = v.trim().toLowerCase()),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  metric(
                    'Grow-out groups',
                    '${groups.length}',
                    'Active groups shown',
                    Icons.grid_view_outlined,
                    metricWidth,
                  ),
                  metric(
                    'Growing out',
                    '${summary.animals}',
                    '${summary.rabbits} rabbits • ${summary.cavies} cavies',
                    Icons.pets_outlined,
                    metricWidth,
                  ),
                  metric(
                    'Latest group weights',
                    pounds(summary.weight),
                    '${summary.weighed} of ${groups.length} groups weighed',
                    Icons.monitor_weight_outlined,
                    metricWidth,
                  ),
                  metric(
                    'Cumulative litter feed',
                    pounds(summary.feed),
                    '${summary.fed} of ${groups.length} groups recorded',
                    Icons.grass_outlined,
                    metricWidth,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Totals follow the groups shown. Each group contributes its latest reading since weaning; cumulative feed readings are not added across dates. Earlier weights are not recalculated when animals receive individual records.',
                style: TextStyle(fontSize: 12, color: Color(0xFF606B7C)),
              ),
              const SizedBox(height: 24),
              if (groups.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      allGroups.isEmpty
                          ? 'No active grow-out groups yet. In Breedings & litters, record weaning and choose Grow out under After weaning.'
                          : 'No grow-out groups match these filters.',
                    ),
                  ),
                ),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final group in groups)
                    SizedBox(width: groupWidth, child: groupCard(group)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
