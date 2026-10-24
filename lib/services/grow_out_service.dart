import '../offline/offline_runtime.dart';
import '../utils/litter_lifecycle.dart';
import 'pagination.dart';

Future<List<Map<String, dynamic>>> loadGrowOutMeasurements(
  List<Map<String, dynamic>> records, {
  Future<List<Map<String, dynamic>>> Function(List<String>, int, int)? readPage,
}) async {
  final ids = records
      .where(litterIsGrowingOut)
      .map((r) => r['id'] as String)
      .toList();
  final readings = <Map<String, dynamic>>[];
  for (var start = 0; start < ids.length; start += 100) {
    final batch = ids.sublist(start, (start + 100).clamp(0, ids.length));
    readings.addAll(
      await fetchAllPages((from, to) async {
        if (readPage != null) return readPage(batch, from, to);
        return List<Map<String, dynamic>>.from(
          await OfflineRuntime.client
              .from('litter_weights')
              .select()
              .inFilter('breeding_id', batch)
              .eq('voided', false)
              .order('recorded_date', ascending: false)
              .order('id')
              .range(from, to),
        );
      }),
    );
  }
  return readings;
}
