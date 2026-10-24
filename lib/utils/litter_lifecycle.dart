int litterUnrecordedCount(Map<String, dynamic> row) {
  final tracking = row['tracking'] as Map? ?? {};
  return ((tracking['weaned'] as int? ?? 0) -
          (row['offspring'] as List? ?? []).length)
      .clamp(0, 100);
}

bool litterIsGrowingOut(Map<String, dynamic> row) {
  final tracking = row['tracking'] as Map? ?? {};
  return (tracking['status'] ?? row['status']) == 'active' &&
      tracking['weaning_destination'] == 'grow_out' &&
      tracking['wean_date'] != null &&
      litterUnrecordedCount(row) > 0;
}

String breedingStage(Map<String, dynamic> row) {
  final t = row['tracking'] as Map? ?? {};
  if ((t['status'] ?? row['status']) == 'cancelled') return 'Cancelled';
  if ((t['status'] ?? row['status']) == 'completed') return 'Completed';
  if (litterIsGrowingOut(row)) return 'Grow out';
  if (t['wean_date'] != null) return 'Weaned';
  if (t['birth_date'] != null) return 'Nursing litter';
  if (t['breeding_occurred'] == false) return 'Scheduled breeding';
  return t['check_result'] == 'Positive'
      ? 'Confirmed pregnant'
      : 'Awaiting birth';
}

bool needsOffspring(Map<String, dynamic> row) {
  final t = row['tracking'] as Map? ?? {};
  return row['import_source'] == null &&
      t['weaning_destination'] != 'grow_out' &&
      t['wean_date'] != null &&
      (t['weaned'] ?? 0) > 0 &&
      (t['status'] ?? row['status']) != 'cancelled' &&
      ((row['offspring'] as List?) ?? []).isEmpty;
}
