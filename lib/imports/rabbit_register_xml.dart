import 'dart:convert';
import 'package:xml/xml.dart';

/// Rabbit Register's Other XML is parsed locally. Source fields are retained
/// alongside normalized values so unsupported history is never discarded.
class RabbitRegisterExport {
  static const maxBytes = 10 * 1024 * 1024;
  static const sections = {
    'Animals': 'animal',
    'Contacts': 'contact',
    'Winnings': 'show',
    'Litters': 'litter',
    'CritterWeights': 'weight',
  };
  final List<Map<String, dynamic>> animals;
  final List<Map<String, dynamic>> records;
  final List<String> warnings;
  final bool recovered;
  final Map<String, int> counts;

  RabbitRegisterExport._(
    this.animals,
    this.records,
    this.warnings,
    this.recovered,
    this.counts,
  );

  factory RabbitRegisterExport.parse(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('Select an XML file smaller than 10 MB.');
    }
    String source;
    try {
      source = utf8.decode(bytes).replaceFirst('\uFEFF', '').trim();
    } on FormatException {
      throw const FormatException('The export must use UTF-8 text encoding.');
    }
    if (RegExp(r'<!DOCTYPE|<!ENTITY', caseSensitive: false).hasMatch(source)) {
      throw const FormatException(
        'XML document types and entity declarations are not supported.',
      );
    }
    XmlDocument document;
    var recovered = false;
    try {
      document = XmlDocument.parse(source);
    } on XmlException {
      // Recover only the observed exporter bug: all records and the final
      // section have closed, but ExportedData has no closing tag. Never salvage
      // incomplete records or silently return a partial parse.
      if (!RegExp(
            r'</(Animals|Contacts|Winnings|Litters|CritterWeights)>$',
          ).hasMatch(source) ||
          source.contains('</ExportedData>')) {
        throw const FormatException(
          'The XML is truncated or malformed. Export it again.',
        );
      }
      try {
        document = XmlDocument.parse('$source</ExportedData>');
        recovered = true;
      } on XmlException {
        throw const FormatException(
          'The XML contains an incomplete record or section. Export it again.',
        );
      }
    }
    final root = document.rootElement;
    if (root.name.toString() != 'ExportedData') {
      throw const FormatException(
        'Select a Rabbit Register ExportedData XML file.',
      );
    }
    final warnings = <String>[
      if (recovered)
        'Rabbit Register did not finish this export. Its final closing tag was recovered. Additional sections may be missing.',
    ];
    final animals = <Map<String, dynamic>>[];
    final records = <Map<String, dynamic>>[];
    final counts = <String, int>{};
    final seen = <String>{};
    for (final section in root.childElements) {
      final sectionName = section.name.toString();
      if (counts.containsKey(sectionName)) {
        throw FormatException('Duplicate XML section: $sectionName.');
      }
      counts[sectionName] = 0;
      if (sectionName == 'Header') continue;
      final kind = sections[sectionName];
      if (kind == null) {
        throw FormatException(
          'Unsupported XML section $sectionName. Please share this export before importing.',
        );
      }
      for (final row in section.childElements) {
        if (row.name.toString() != 'Record') {
          throw FormatException('Unexpected element in $sectionName.');
        }
        final raw = <String, String>{};
        for (final field in row.childElements) {
          final key = field.name.toString();
          if (raw.containsKey(key)) {
            throw FormatException('Duplicate field $key in $sectionName.');
          }
          raw[key] = field.childElements.isEmpty
              ? field.innerText.trim()
              : field.innerXml;
        }
        final id = raw[kind == 'animal' ? 'CID' : 'ID'] ?? '';
        if (!RegExp(r'^[1-9]\d{0,9}$').hasMatch(id)) {
          throw FormatException(
            'Missing or invalid record ID in $sectionName.',
          );
        }
        if (!seen.add('$kind:$id')) {
          throw FormatException('Duplicate $kind source ID $id.');
        }
        counts[sectionName] = counts[sectionName]! + 1;
        if (kind == 'animal') {
          final storage = raw['Storage_Area'] ?? '';
          final active = storage.endsWith(':Active');
          final archived = storage.endsWith(':Archive');
          if (!active && !archived) {
            throw FormatException(
              'Rabbit $id has an unknown storage area: $storage.',
            );
          }
          final dob = _date(raw['DOB'], 'Rabbit $id birth date');
          final dod = _date(raw['DOD'], 'Rabbit $id death date');
          final sold = _date(raw['DateSold'], 'Rabbit $id sale date');
          final name = _text(raw['Name']);
          final tattoo = _text(raw['Ear_Num']);
          final sex = switch (raw['Sex']?.toLowerCase()) {
            'buck' || 'm' || 'male' => 'Buck',
            'doe' || 'f' || 'female' => 'Doe',
            _ => null,
          };
          if (name == null && tattoo == null) {
            warnings.add(
              'Rabbit $id has no name or ear number; it will be named Rabbit Register #$id.',
            );
          }
          if (raw['DOBTag'] != null && raw['DOBTag'] != '=') {
            warnings.add(
              'Rabbit $id has an approximate birth date (${raw['DOBTag']}); the qualifier is retained in source history.',
            );
          }
          animals.add({
            'source_id': id,
            'name': name ?? tattoo ?? 'Rabbit Register #$id',
            'tattoo': tattoo,
            'breed': _text(raw['Breed']),
            'variety': _text(raw['Variety']),
            'sex': sex,
            'dob': dob,
            'status': active
                ? 'active'
                : dod != null
                ? 'deceased'
                : sold != null
                ? 'sold'
                : 'archived',
            'sire_id': _reference(raw['SireKey']),
            'dam_id': _reference(raw['DamKey']),
            'registration_number': _text(raw['Reg_']),
            'grand_champion_number': _text(raw['Grand_Ch.__Num']),
            'legs': _integer(raw['Legs'], 'Rabbit $id legs'),
            'notes': _text(raw['Comments']),
            'profile_weight': _weight(
              raw['Weight'],
              'Rabbit $id profile weight',
            ),
            'raw': raw,
          });
        } else {
          records.add({
            'kind': kind,
            'source_id': id,
            'raw': raw,
            'animal_source_id': _reference(
              raw[switch (kind) {
                'show' => 'CID',
                'weight' => 'CRITTERKEY',
                'litter' => 'DAMIDKEY',
                _ => '',
              }],
            ),
            if (kind == 'litter')
              'sire_source_id': _reference(raw['SIREIDKEY']),
            if (kind == 'weight') ...{
              'weight': _weight(raw['CRITTERWT'], 'Weight $id'),
              'recorded_date': _date(raw['WEIGHINGDATE'], 'Weight $id date'),
            },
          });
        }
      }
    }
    if (animals.isEmpty || animals.length > 2000 || records.length > 20000) {
      throw const FormatException(
        'Import supports 1–2,000 rabbits and up to 20,000 history records.',
      );
    }
    final ids = animals.map((a) => a['source_id']).toSet();
    for (final a in animals) {
      for (final side in ['sire_id', 'dam_id']) {
        final parent = a[side];
        if (parent != null && !ids.contains(parent)) {
          warnings.add(
            'Rabbit ${a['source_id']} references missing ${side == 'sire_id' ? 'sire' : 'dam'} $parent. This link will remain empty; the source ID is retained.',
          );
        }
      }
    }
    for (final r in records) {
      for (final side in ['animal_source_id', 'sire_source_id']) {
        final id = r[side];
        if (id != null && !ids.contains(id)) {
          warnings.add(
            '${r['kind']} ${r['source_id']} references missing rabbit $id. Its source history will be retained without that link.',
          );
        }
      }
    }
    final absent = sections.keys.where((s) => !counts.containsKey(s)).toList();
    if (absent.isNotEmpty) {
      warnings.add(
        'Sections not included in this export: ${absent.join(', ')}.',
      );
    }
    warnings.add(
      'Profile weights have no measurement date and are retained in source history. Only dated weights enter weight history.',
    );
    return RabbitRegisterExport._(
      animals,
      records,
      warnings,
      recovered,
      counts,
    );
  }

  /// Suggest only explicit link omissions; never choose a replacement parent.
  /// Each DFS back edge must be reviewed to break the exported cycles.
  List<Map<String, String>> parentProblems(Map<String, String> sexes) {
    final nodes = {for (final a in animals) a['source_id'] as String: a};
    final problems = <String, Map<String, String>>{};
    for (final a in animals) {
      for (final side in ['sire_id', 'dam_id']) {
        final parent = nodes[a[side]];
        final sex = parent == null
            ? null
            : sexes[parent['source_id']] ?? parent['sex'];
        if (sex != null && sex != (side == 'sire_id' ? 'Buck' : 'Doe')) {
          final key = '${a['source_id']}:$side';
          problems[key] = {
            'key': key,
            'source_id': a['source_id'] as String,
            'side': side,
            'parent_id': a[side] as String,
            'name': a['name'] as String,
            'parent_name': parent!['name'] as String,
            'reason': 'Parent sex conflicts with its pedigree position',
          };
        }
      }
    }
    final done = <String>{}, visiting = <String>{};
    for (final id in nodes.keys) {
      final stack = <({String id, bool exit, String? from, String? side})>[
        (id: id, exit: false, from: null, side: null),
      ];
      while (stack.isNotEmpty) {
        final frame = stack.removeLast();
        if (frame.exit) {
          visiting.remove(frame.id);
          done.add(frame.id);
          continue;
        }
        if (visiting.contains(frame.id)) {
          final key = '${frame.from}:${frame.side}';
          problems[key] = {
            'key': key,
            'source_id': frame.from!,
            'side': frame.side!,
            'parent_id': frame.id,
            'name': nodes[frame.from]!['name'] as String,
            'parent_name': nodes[frame.id]!['name'] as String,
            'reason': 'This parent link closes a pedigree cycle',
          };
          continue;
        }
        if (done.contains(frame.id) || !nodes.containsKey(frame.id)) continue;
        visiting.add(frame.id);
        stack.add((id: frame.id, exit: true, from: null, side: null));
        for (final side in ['sire_id', 'dam_id']) {
          final parent = nodes[frame.id]![side] as String?;
          if (parent != null) {
            stack.add((id: parent, exit: false, from: frame.id, side: side));
          }
        }
      }
    }
    return problems.values.toList();
  }

  Map<String, dynamic> payload({
    Map<String, String> sexes = const {},
    Map<String, String> matches = const {},
    bool acknowledged = false,
    Set<String> omittedParents = const {},
  }) => {
    'recovered': recovered,
    'warnings_acknowledged': acknowledged,
    'animals': [
      for (final a in animals)
        {
          ...a,
          for (final side in ['sire_id', 'dam_id'])
            if (omittedParents.contains('${a['source_id']}:$side')) side: null,
          if (sexes.containsKey(a['source_id'])) 'sex': sexes[a['source_id']],
          if (matches[a['source_id']] == 'new') 'keep_separate': true,
          if (matches[a['source_id']] != null &&
              matches[a['source_id']] != 'new')
            'existing_id': matches[a['source_id']],
        },
    ],
    'records': records,
  };

  static String? _text(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();
  static String? _reference(String? value) =>
      value == '0' ? null : _text(value);
  static String? _date(String? value, String label) {
    value = _text(value);
    // Access's empty-date sentinel is not an actual event in year 100.
    if (value == null || value == '0100-01-01') return null;
    final parsed = DateTime.tryParse(value);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
        parsed == null ||
        parsed.toIso8601String().substring(0, 10) != value ||
        parsed.year < 1800 ||
        value.compareTo(DateTime.now().toIso8601String().substring(0, 10)) >
            0) {
      throw FormatException('$label is invalid: $value.');
    }
    return value;
  }

  static int? _integer(String? value, String label) {
    if (_text(value) == null) return null;
    final n = int.tryParse(value!);
    if (n == null || n < 0) throw FormatException('$label is invalid.');
    return n;
  }

  static double? _weight(String? value, String label) {
    if (_text(value) == null) return null;
    final n = double.tryParse(value!);
    if (n == 0) return null;
    final pounds = n == null ? null : n / 453.592;
    if (pounds == null || !pounds.isFinite || pounds <= 0 || pounds >= 1000) {
      throw FormatException(
        '$label is invalid. Rabbit Register XML weights must be in grams.',
      );
    }
    return double.parse(pounds.toStringAsFixed(6));
  }
}
