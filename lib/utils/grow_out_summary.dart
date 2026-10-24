import 'animal_labels.dart';
import 'litter_lifecycle.dart';
import 'production_measurements.dart';

/// Readings are cumulative feed / group live-weight snapshots, never quantities
/// to sum across dates or divide by today's changing group membership.
class GrowOutGroup {
  final Map<String, dynamic> record;
  final Map<String, dynamic>? weight, feed;
  GrowOutGroup(this.record, List<Map<String, dynamic>> readings, DateTime today)
    : weight = _latest(record, readings, 'weight', today),
      feed = _latest(record, readings, 'feed_weight', today);

  int get count => litterUnrecordedCount(record);
  bool get cavy => record['dam']['species'] == 'cavy';
  double? get liveWeight => measurementNumber(weight?['weight']);
  double? get cumulativeFeed => measurementNumber(feed?['feed_weight']);
  int? remainingSex(bool male) {
    final total = record['tracking'][male ? 'weaned_males' : 'weaned_females'];
    if (total == null) return null;
    final linked = (record['offspring'] as List? ?? []).where(
      (o) => male
          ? animalIsMale(o['animal']?['sex'] ?? '')
          : ['F', 'Doe', 'Sow'].contains(o['animal']?['sex']),
    );
    return ((total as int) - linked.length).clamp(0, count);
  }

  static Map<String, dynamic>? _latest(
    Map<String, dynamic> record,
    List<Map<String, dynamic>> rows,
    String field,
    DateTime today,
  ) {
    final weaned = record['tracking']['wean_date'].toString();
    final through = today.toIso8601String().substring(0, 10);
    final candidates =
        rows.where((r) {
          final date = r['recorded_date']?.toString();
          final value = measurementNumber(r[field]);
          return r['breeding_id'] == record['id'] &&
              r['voided'] != true &&
              date != null &&
              DateTime.tryParse(date) != null &&
              date.compareTo(weaned) >= 0 &&
              date.compareTo(through) <= 0 &&
              value != null &&
              (field == 'weight' ? value > 0 : value >= 0);
        }).toList()..sort((a, b) {
          final date = b['recorded_date'].toString().compareTo(
            a['recorded_date'].toString(),
          );
          return date != 0
              ? date
              : a['id'].toString().compareTo(b['id'].toString());
        });
    return candidates.firstOrNull;
  }
}

class GrowOutSummary {
  final List<GrowOutGroup> groups;
  GrowOutSummary(this.groups);
  int get animals => groups.fold(0, (n, g) => n + g.count);
  int get rabbits =>
      groups.where((g) => !g.cavy).fold(0, (n, g) => n + g.count);
  int get cavies => animals - rabbits;
  int get weighed => groups.where((g) => g.liveWeight != null).length;
  int get fed => groups.where((g) => g.cumulativeFeed != null).length;
  double? get weight => weighed == 0
      ? null
      : groups.fold<double>(0, (n, g) => n + (g.liveWeight ?? 0));
  double? get feed => fed == 0
      ? null
      : groups.fold<double>(0, (n, g) => n + (g.cumulativeFeed ?? 0));
}

List<GrowOutGroup> growOutGroups(
  List<Map<String, dynamic>> records,
  List<Map<String, dynamic>> readings, {
  DateTime? now,
}) {
  final byLitter = <dynamic, List<Map<String, dynamic>>>{};
  for (final r in readings) {
    byLitter.putIfAbsent(r['breeding_id'], () => []).add(r);
  }
  return records
      .where(litterIsGrowingOut)
      .map(
        (r) => GrowOutGroup(r, byLitter[r['id']] ?? [], now ?? DateTime.now()),
      )
      .toList()
    ..sort(
      (a, b) => a.record['tracking']['wean_date'].toString().compareTo(
        b.record['tracking']['wean_date'].toString(),
      ),
    );
}
