import 'dart:convert';

/// A Kintraks All records CSV. Columns stay textual, particularly lb.oz
/// weights and identifiers. Repeated Breeder columns are kept separately.
class KintraksExport {
  static const maxBytes = 10 * 1024 * 1024;
  final List<Map<String, dynamic>> animals;
  final List<String> warnings;
  final Map<String, int> counts;
  KintraksExport._(this.animals, this.warnings)
    : counts = {'Animals': animals.length};

  factory KintraksExport.parse(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('Select a CSV file smaller than 10 MB.');
    }
    String text;
    try {
      text = utf8.decode(bytes).replaceFirst('\uFEFF', '');
    } on FormatException {
      throw const FormatException('Export the CSV using UTF-8 text encoding.');
    }
    if (text.contains('\u0000')) {
      throw const FormatException('Select a UTF-8 CSV file.');
    }
    final rows = _csv(text);
    if (rows.length < 2) {
      throw const FormatException('The CSV contains no rabbits.');
    }
    final headers = rows.removeAt(0);
    final names = headers.map((h) => h.trim()).toList();
    for (final required in [
      'Id',
      'Fatherid',
      'Motherid',
      'Name',
      'Sex',
      'Dob',
      'Ear #',
      'Weight',
      'Deceased',
      'Sold',
    ]) {
      if (names.where((n) => n == required).length != 1) {
        throw FormatException(
          'Expected one Kintraks $required column. Choose All records and export a comma-delimited CSV.',
        );
      }
    }
    final occurrences = <String, int>{};
    final keys = <String>[];
    for (final name in names) {
      final count = (occurrences[name] ?? 0) + 1;
      occurrences[name] = count;
      if (name.isEmpty || (name != 'Breeder' && count > 1) || count > 2) {
        throw FormatException(
          'Unexpected blank or repeated CSV column: $name.',
        );
      }
      final key = name == 'Breeder' ? 'Breeder [$count]' : name;
      if (key == '_csv_headers' || keys.contains(key)) {
        throw FormatException('Ambiguous CSV column: $name.');
      }
      keys.add(key);
    }
    final animals = <Map<String, dynamic>>[];
    final warnings = <String>[
      'Choose which rabbits belong in your current herd. All other unsold, living rabbits start as archived pedigree-only animals; blank Owner fields do not prove ownership.',
      'Weights use pounds and ounces: 3.13 = 3 lb 13 oz; 3.04 = 3 lb 4 oz. Original text is preserved. Undated weights stay in source snapshots, separate from dated weight history.',
      'This CSV has animal snapshots and custom fields, not separate litter, mating, show-result, or dated weight history.',
    ];
    final ids = <String>{};
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row.length != keys.length) {
        throw FormatException(
          'CSV row ${i + 2} has ${row.length} fields; expected ${keys.length}.',
        );
      }
      final raw = <String, dynamic>{
        for (var j = 0; j < keys.length; j++) keys[j]: row[j],
        '_csv_headers': headers,
      };
      String? field(String key) => _text(raw[key] as String?);
      final id = field('Id');
      if (id == null ||
          !RegExp(r'^[1-9]\d{0,9}$').hasMatch(id) ||
          !ids.add(id)) {
        throw FormatException(
          'CSV row ${i + 2} has a missing, invalid, or duplicate Id.',
        );
      }
      final dead = _flag(field('Deceased'), 'Rabbit $id Deceased');
      final sold = _flag(field('Sold'), 'Rabbit $id Sold');
      if (occurrences['Breeder'] != null) {
        _flag(field('Breeder [1]'), 'Rabbit $id Breeder flag');
      }
      final name = field('Name'), tattoo = field('Ear #');
      final dob = _date(field('Dob'), 'Rabbit $id birth date');
      _date(field('Date Deceased'), 'Rabbit $id death date');
      _date(field('Date Sold'), 'Rabbit $id sale date');
      final sex = switch (field('Sex')?.toLowerCase()) {
        'male' || 'buck' || 'm' => 'Buck',
        'female' || 'doe' || 'f' => 'Doe',
        _ => null,
      };
      if (name == null && tattoo == null) {
        warnings.add(
          'Rabbit $id has no name or ear number; it will be named Kintraks #$id.',
        );
      }
      final fullName = [
        field('Prefix'),
        name ?? tattoo ?? 'Kintraks #$id',
        field('Suffix'),
      ].whereType<String>().join(' ');
      final legsText = field('Legs');
      var legs = legsText == null ? null : int.tryParse(legsText);
      if (legsText != null && (legs == null || legs < 0)) {
        warnings.add(
          'Rabbit $id has a non-integer leg count ($legsText). The original value stays in source history; its leg count will remain empty.',
        );
        legs = null;
      }
      animals.add({
        'source_id': id,
        'name': fullName.isEmpty ? tattoo ?? 'Kintraks #$id' : fullName,
        'tattoo': tattoo,
        'breed': field('Breed'),
        'variety': field('Colour'),
        'sex': sex,
        'dob': dob,
        'status': dead
            ? 'deceased'
            : sold
            ? 'sold'
            : 'archived',
        'pedigree_only': !dead && !sold,
        'sire_id': _reference(field('Fatherid'), id),
        'dam_id': _reference(field('Motherid'), id),
        'registration_number': field('Registration #'),
        'grand_champion_number': field('GC #'),
        'legs': legs,
        'notes': field('Notes'),
        'profile_weight': poundsAndOunces(field('Weight'), 'Rabbit $id weight'),
        'raw': raw,
      });
    }
    if (animals.isEmpty || animals.length > 2000) {
      throw const FormatException('Import supports 1–2,000 rabbits.');
    }
    final nodes = {for (final a in animals) a['source_id']: a};
    for (final a in animals) {
      for (final side in ['sire_id', 'dam_id']) {
        final parent = nodes[a[side]];
        if (a[side] != null && parent == null) {
          warnings.add(
            'Rabbit ${a['source_id']} references missing ${side == 'sire_id' ? 'sire' : 'dam'} ${a[side]}. The link will remain empty; the original ID is preserved.',
          );
        } else if (parent != null &&
            a['dob'] != null &&
            parent['dob'] != null &&
            (parent['dob'] as String).compareTo(a['dob'] as String) >= 0) {
          warnings.add(
            '${a['name']} (#${a['source_id']}) has a birth date (${a['dob']}) on or before parent ${parent['name']} (#${parent['source_id']}, ${parent['dob']}). Check the source; dates are preserved as exported.',
          );
        }
      }
    }
    for (final key in ['name', 'tattoo']) {
      final values = <String, int>{};
      for (final a in animals) {
        final value = a[key] as String?;
        if (value != null) {
          values.update(value.toLowerCase(), (n) => n + 1, ifAbsent: () => 1);
        }
      }
      final repeated = values.values.where((n) => n > 1).length;
      if (repeated > 0) {
        warnings.add(
          '$repeated repeated ${key == 'name' ? 'names' : 'ear numbers'}: source IDs stay separate.',
        );
      }
    }
    final missingBreed = animals.where((a) => a['breed'] == null).length;
    if (missingBreed > 0) {
      warnings.add(
        '$missingBreed rabbits have no breed in the export. No breed will be guessed.',
      );
    }
    return KintraksExport._(animals, warnings);
  }

  /// Reparse edits for all normal validation, preserving original source cells.
  /// Source IDs cannot be edited: they are the import/retry identity.
  KintraksExport withCorrections(Map<String, Map<String, String>> edits) {
    final original = {
      for (final a in animals) a['source_id'] as String: a['raw'] as Map,
    };
    final headers = List<String>.from(
      original.values.first['_csv_headers'] as List,
    );
    final counts = <String, int>{};
    final keys = [
      for (final h in headers)
        (() {
          final name = h.trim();
          final count = (counts[name] ?? 0) + 1;
          counts[name] = count;
          return name == 'Breeder' ? 'Breeder [$count]' : name;
        })(),
    ];
    String quote(String v) => '"${v.replaceAll('"', '""')}"';
    final rows = <List<String>>[headers];
    for (final a in animals) {
      final id = a['source_id'] as String;
      final raw = original[id]!;
      final changes = edits[id] ?? const <String, String>{};
      if (changes.keys.any((k) => k == 'Id' || !keys.contains(k))) {
        throw const FormatException(
          'Source IDs and CSV column names cannot be edited.',
        );
      }
      rows.add([
        for (final key in keys) changes[key] ?? raw[key] as String? ?? '',
      ]);
    }
    final corrected = KintraksExport.parse(
      utf8.encode(rows.map((r) => r.map(quote).join(',')).join('\r\n')),
    );
    for (final a in corrected.animals) {
      final id = a['source_id'] as String;
      a['raw'] = original[id];
      a['corrections'] = <String, String>{
        for (final e in (edits[id] ?? const <String, String>{}).entries)
          if (e.value != original[id]![e.key]) e.key: e.value,
      };
    }
    return corrected;
  }

  Map<String, dynamic> payload({
    Map<String, String> sexes = const {},
    Map<String, String> matches = const {},
    bool acknowledged = false,
    Set<String> omittedParents = const {},
    Set<String> activeIds = const {},
  }) => {
    'warnings_acknowledged': acknowledged,
    'animals': [
      for (final a in animals)
        {
          ...a,
          if (a['status'] == 'archived' &&
              activeIds.contains(a['source_id'])) ...{
            'status': 'active',
            'pedigree_only': false,
          },
          for (final side in ['sire_id', 'dam_id'])
            if (omittedParents.contains('${a['source_id']}:$side')) side: null,
          if (sexes.containsKey(a['source_id'])) 'sex': sexes[a['source_id']],
          if (matches[a['source_id']] == 'new') 'keep_separate': true,
          if (matches[a['source_id']] != null &&
              matches[a['source_id']] != 'new')
            'existing_id': matches[a['source_id']],
        },
    ],
  };

  static double? poundsAndOunces(String? text, [String label = 'Weight']) {
    if (_text(text) == null) return null;
    final m = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(text!.trim());
    if (m == null) {
      throw FormatException(
        '$label must use pounds and ounces, for example 3.13.',
      );
    }
    final pounds = int.parse(m[1]!);
    final ounces = int.parse(m[2] ?? '0');
    if (ounces > 15 || pounds >= 1000 || pounds + ounces / 16 >= 1000) {
      throw FormatException(
        '$label has invalid pounds or ounces (ounces must be 0–15).',
      );
    }
    final result = pounds + ounces / 16;
    return result == 0 ? null : result;
  }

  static String? _text(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();
  static String? _reference(String? value, String id) {
    if (value == null || value == '0') return null;
    if (!RegExp(r'^[1-9]\d{0,9}$').hasMatch(value)) {
      throw FormatException('Rabbit $id has an invalid parent ID.');
    }
    return value;
  }

  static bool _flag(String? value, String label) {
    if (value == null || value.toLowerCase() == 'false') return false;
    if (value.toLowerCase() == 'true') return true;
    throw FormatException('$label must be True or False.');
  }

  static String? _date(String? value, String label) {
    if (value == null) return null;
    final date = DateTime.tryParse(value);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
        date == null ||
        date.toIso8601String().substring(0, 10) != value ||
        date.year < 1800 ||
        value.compareTo(DateTime.now().toIso8601String().substring(0, 10)) >
            0) {
      throw FormatException('$label is invalid: $value.');
    }
    return value;
  }

  // Strict comma/quote reader: quoted line breaks and escaped quotes survive.
  // Reject partial rows/quotes rather than silently repairing breeder data.
  static List<List<String>> _csv(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    var field = StringBuffer();
    var quoted = false, closed = false, started = false;
    void finishField() {
      row.add(field.toString());
      if (row.length > 500) {
        throw const FormatException(
          'The CSV has too many columns (maximum 500).',
        );
      }
      field = StringBuffer();
      closed = false;
      started = false;
    }

    void finishRow() {
      finishField();
      if (row.any((v) => v.isNotEmpty) || row.length > 1) rows.add(row);
      if (rows.length > 2001) {
        throw const FormatException('Import supports up to 2,000 rabbits.');
      }
      row = [];
    }

    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (quoted) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            quoted = false;
            closed = true;
          }
        } else {
          field.write(c);
        }
      } else if (c == ',') {
        finishField();
      } else if (c == '\r' || c == '\n') {
        finishRow();
        if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      } else if (c == '"' && !started && !closed) {
        quoted = true;
        started = true;
      } else {
        if (closed || c == '"') {
          throw const FormatException(
            'Malformed CSV quotes. Export again using comma delimiter and double quotes.',
          );
        }
        field.write(c);
        started = true;
      }
    }
    if (quoted) {
      throw const FormatException(
        'The CSV ends inside a quoted field. Export it again.',
      );
    }
    if (started || closed || row.isNotEmpty) finishRow();
    return rows;
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
}
