import 'package:intl/intl.dart';

const majorShowAwards = <String, String>{
  'BIS': 'Best in Show',
  'RIS': 'Reserve in Show',
  '1RIS': 'First Reserve in Show',
  '2RIS': 'Second Reserve in Show',
  'BOB': 'Best of Breed',
  'BOSB': 'Best Opposite of Breed',
  'BOV': 'Best of Variety',
  'BOSV': 'Best Opposite of Variety',
  'BOG': 'Best of Group',
  'BOSG': 'Best Opposite of Group',
  'BEST 4-CLASS': 'Best 4-Class',
  'BEST 6-CLASS': 'Best 6-Class',
  'BEST JUNIOR': 'Best Junior',
  'BEST INTERMEDIATE': 'Best Intermediate',
  'BEST SENIOR': 'Best Senior',
  'BJB': 'Best Junior of Breed',
  'BIB': 'Best Intermediate of Breed',
  'BSB': 'Best Senior of Breed',
  'BJV': 'Best Junior of Variety',
  'BIV': 'Best Intermediate of Variety',
  'BSV': 'Best Senior of Variety',
};

String canonicalAward(String value) {
  final upper = value.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
  for (final entry in majorShowAwards.entries) {
    if (entry.key == upper || entry.value.toUpperCase() == upper) {
      return entry.key;
    }
  }
  return upper;
}

List<String> showAwards(Map<String, dynamic> r) {
  final awards = <String>{};
  void add(dynamic value) {
    if (value is List) {
      for (final item in value) {
        add(item);
      }
    } else if (value is String) {
      for (final text in value.split(RegExp(r'[,;\n|]+'))) {
        final code = canonicalAward(text);
        if (code.isNotEmpty) awards.add(code);
      }
    }
  }

  for (final item in r['entry_awards'] as List? ?? []) {
    if (item is Map) add(item['award_code']);
  }
  add(r['special_awards']);
  if (r['is_fur'] == true) add(r['fur_award']);
  for (final item in r['result_details'] as List? ?? []) {
    if (item is Map) add(item['award']);
  }
  return awards.toList();
}

String? showPlacement(Map<String, dynamic> r) {
  final direct = r['is_fur'] == true
      ? r['fur_placement'] ?? r['placement']
      : r['placement'];
  if (direct != null && direct.toString().trim().isNotEmpty) {
    return direct.toString().trim();
  }
  for (final item in r['result_details'] as List? ?? []) {
    final value = item is Map ? item['placing_label']?.toString().trim() : null;
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

String placingLabel(String? value) {
  if (value == null) return 'Not recorded';
  final n = int.tryParse(value);
  if (n == null || n < 1) return value;
  final suffix = n % 100 >= 11 && n % 100 <= 13
      ? 'th'
      : switch (n % 10) {
          1 => 'st',
          2 => 'nd',
          3 => 'rd',
          _ => 'th',
        };
  return '$n$suffix place';
}

List<String> pedigreeWins(Map<String, dynamic> row) {
  if (row['source_available'] == false) return [];
  if ((row['record'] as Map?)?['pedigree_rank']?.toString().toLowerCase() ==
      'hide') {
    return [];
  }
  final r = Map<String, dynamic>.from(row['record'] as Map);
  final status = (r['result_status'] ?? '').toString().toLowerCase();
  if (r['is_disqualified'] == true ||
      r['is_shown'] == false ||
      r['scratched_at'] != null ||
      status.contains('disqualified') ||
      status == 'no show' ||
      status == 'unworthy of award') {
    return [];
  }
  final awards = showAwards(r).where(majorShowAwards.containsKey).toList();
  if (awards.isEmpty) return [];
  final show = r['shows'] is Map ? r['shows'] as Map : {};
  final date = DateTime.tryParse(show['start_date']?.toString() ?? '');
  return [
    '${awards.join(', ')} • ${date == null ? 'Date unknown' : DateFormat('MM/dd/yyyy').format(date)} • ${show['name'] ?? 'Show'}',
  ];
}

/// Adds generated pedigree details separately, leaving manually entered notes intact.
void attachPedigreeWins(
  Map<String, dynamic> pedigree,
  List<Map<String, dynamic>> rows,
) {
  for (final value in pedigree.values) {
    if (value is! Map) continue;
    final id = value['id'] ?? value['existing_id'];
    if (id == null) continue;
    final manualLines = (value['leg_details'] ?? '')
        .toString()
        .split('\n')
        .map((s) => s.trim())
        .toSet();
    final lines = <String>{};
    for (final row in rows.where((r) => r['animal_id'] == id)) {
      lines.addAll(pedigreeWins(row));
    }
    value['synced_show_details'] = lines
        .where((s) => !manualLines.contains(s))
        .join('\n');
  }
}
