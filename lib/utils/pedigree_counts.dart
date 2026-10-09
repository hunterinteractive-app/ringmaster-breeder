/// Count ancestry slots, never network fetches. The subject is not an ancestor.
Map<String, int> pedigreeCounts(Map<String, dynamic> pedigree) {
  final counts = <String, int>{};
  for (final entry in pedigree.entries) {
    if (entry.key == 'animal' || entry.value is! Map) continue;
    final id = entry.value['id'] as String?;
    if (id != null) counts.update(id, (count) => count + 1, ifAbsent: () => 1);
  }
  return counts;
}
