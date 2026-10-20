import '../offline/offline_runtime.dart';

/// Read-only catalog union. Breed choice never filters the variety list.
class WhatIfCatalog {
  final List<String> breeds, varieties;
  const WhatIfCatalog({this.breeds = const [], this.varieties = const []});

  factory WhatIfCatalog.fromRows(List<Map<String, dynamic>> rows) {
    List<String> sorted(Iterable<dynamic> values) {
      final unique = <String, String>{};
      for (final value in values) {
        final name =
            value?.toString().trim().replaceAll(RegExp(r'\s+'), ' ') ?? '';
        if (name.isNotEmpty) unique.putIfAbsent(name.toLowerCase(), () => name);
      }
      return unique.values.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }

    final rabbits = rows.where((r) => r['species'] == 'rabbit').toList();
    return WhatIfCatalog(
      breeds: sorted(rabbits.map((r) => r['name'])),
      varieties: sorted([
        for (final row in rabbits)
          for (final variety in (row['varieties'] as List? ?? const [])) ...[
            variety['name'],
            variety['standard_name'],
          ],
      ]),
    );
  }

  static Future<WhatIfCatalog> load() async => WhatIfCatalog.fromRows(
    List<Map<String, dynamic>>.from(
      await OfflineRuntime.client
          .from('breeds')
          .select(
            'name,species,is_recognized,varieties(name,is_recognized,standard_name,standard_reference,catalog_kind)',
          )
          .order('name'),
    ),
  );
}
