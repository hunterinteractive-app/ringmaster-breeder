/// Read every ordered page. Advancing by the actual response length also works
/// when a server imposes a smaller page cap. Errors never return partial data.
Future<List<Map<String, dynamic>>> fetchAllPages(
  Future<List<Map<String, dynamic>>> Function(int from, int to) query,
) async {
  final rows = <Map<String, dynamic>>[];
  while (true) {
    final page = await query(rows.length, rows.length + 499);
    if (page.isEmpty) return rows;
    rows.addAll(page);
  }
}
