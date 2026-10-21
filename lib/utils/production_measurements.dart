import 'package:xml/xml.dart';

class WoolField {
  final String label, group;
  final double? maximum;
  const WoolField(this.label, this.group, [this.maximum]);
}

const woolFields = <String, WoolField>{
  'PRIME': WoolField('Prime wool (g)', 'Harvest'),
  'GRADE2': WoolField('Grade 2 wool (g)', 'Harvest'),
  'COMBINGS': WoolField('Combings (g)', 'Harvest'),
  'FELTEDSTAINED': WoolField('Felted / stained wool (g)', 'Harvest'),
  'BODYWT': WoolField('Body weight at harvest (g)', 'Harvest'),
  'LENGTH': WoolField('Staple length (mm)', 'Fiber quality'),
  'AFD': WoolField('Average fiber diameter (microns)', 'Fiber quality'),
  'STRENGTH': WoolField('Strength (N/ktex)', 'Fiber quality'),
  'CRIMPCOUNT': WoolField('Crimps per inch', 'Fiber quality'),
  'SD': WoolField('Standard deviation (microns)', 'Fiber quality'),
  'CV': WoolField('Coefficient of variation (%)', 'Fiber quality'),
  'CEM': WoolField('Coarse edge (microns)', 'Fiber quality'),
  'CF': WoolField('Comfort factor (%)', 'Fiber quality', 100),
  'LT15': WoolField('Fibers below 15 microns (%)', 'Fiber quality', 100),
  'GT30': WoolField('Fibers above 30 microns (%)', 'Fiber quality', 100),
  'VEGMATTERBASE': WoolField('Vegetable matter base (%)', 'Fiber quality', 100),
  'WOOLBASE': WoolField('Wool base (%)', 'Fiber quality', 100),
};

const woolJudgingFields = {
  'EvalDate': 'Evaluation date (YYYY-MM-DD)',
  'Judge': 'Judge',
  'Location': 'Evaluation location',
  'Comments': 'Evaluation comments',
  'WoolPerf': 'Wool performance',
};

/// Import evidence is never rewritten by a form edit. These aliases only affect
/// the editable native record, including spelling variants in the field guide.
Map<String, dynamic> canonicalWool(Map raw) {
  final result = <String, dynamic>{};
  for (final e in raw.entries) {
    final name = e.key.toString(), upper = name.toUpperCase();
    final known =
        woolFields.containsKey(upper) ||
        const [
          'ID',
          'WID',
          'CID',
          'FLEECEWT',
          'SHEARDATE',
          'COMMENTS',
          'COLOR',
          'XMLDATA',
          'FELTEDSTAINDED',
          'VEFGMATTERBASE',
        ].contains(upper);
    result[known ? upper : name] = e.value;
  }
  if (result.containsKey('FELTEDSTAINDED')) {
    result['FELTEDSTAINED'] ??= result['FELTEDSTAINDED'];
  }
  if (result.containsKey('VEFGMATTERBASE')) {
    result['VEGMATTERBASE'] ??= result['VEFGMATTERBASE'];
  }
  result.remove('FELTEDSTAINDED');
  result.remove('VEFGMATTERBASE');
  return result;
}

Map<String, String> woolJudging(Map measurements) {
  final xml = measurements['XMLDATA']?.toString() ?? '';
  if (xml.isEmpty ||
      RegExp(r'<!DOCTYPE|<!ENTITY', caseSensitive: false).hasMatch(xml)) {
    return {};
  }
  try {
    final root = XmlDocument.parse(xml).rootElement;
    if (root.name.local != 'JudgingInfo') return {};
    final values = {
      for (final e in root.childElements) e.name.toString(): e.innerText,
    };
    if (const [
      '0100-01-01',
      '0100-01-02',
      '0100-01-03',
      '2100-12-12',
    ].contains(values['EvalDate'])) {
      values['EvalDate'] = '';
    }
    return values;
  } on XmlException {
    return {};
  }
}

String updateWoolJudging(Map<String, String> values, String? original) {
  XmlElement root;
  try {
    root = XmlDocument.parse(original ?? '').rootElement.copy();
    if (root.name.local != 'JudgingInfo') throw const FormatException();
  } catch (_) {
    root = XmlElement(XmlName('JudgingInfo'));
  }
  for (final e in values.entries) {
    final nodes = root.findElements(e.key).toList();
    if (nodes.isEmpty) {
      root.children.add(XmlElement(XmlName(e.key), [], [XmlText(e.value)]));
    } else {
      nodes.first.innerText = e.value;
    }
  }
  return root.toXmlString();
}

double? measurementNumber(dynamic v) {
  final n = num.tryParse(v?.toString() ?? '')?.toDouble();
  return n != null && n.isFinite ? n : null;
}

double? gradedWoolTotal(Map measurements) {
  final values = [
    'PRIME',
    'GRADE2',
    'COMBINGS',
    'FELTEDSTAINED',
  ].map((k) => measurementNumber(measurements[k])).whereType<double>().toList();
  return values.isEmpty ? null : values.fold<double>(0, (a, b) => a + b);
}

String measurementText(dynamic v) {
  final n = measurementNumber(v);
  return n == null
      ? 'Unknown'
      : n.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
}

/// Cumulative feed and live weight are compared on the same weighing date.
/// Missing/zero weights never manufacture a ratio.
double? feedWeightRatio(dynamic feed, dynamic weight) {
  final f = measurementNumber(feed), w = measurementNumber(weight);
  return f == null || w == null || f < 0 || w <= 0 ? null : f / w;
}

const defaultWoolSettings = <String, dynamic>{
  'unit': 'g',
  'metric': 'gross',
  'period': 'month',
  'update_body_weight': false,
  'show_on_pedigree': false,
  'factors': {'PRIME': 100, 'GRADE2': 75, 'COMBINGS': 25, 'FELTEDSTAINED': 25},
};
const woolUnits = {
  'g': 'Grams',
  'kg': 'Kilograms',
  'oz': 'Ounces',
  'lb': 'Decimal pounds',
  'lb_oz': 'Pounds & ounces',
};
const woolPeriods = {
  'day': 'Daily',
  'week': 'Weekly',
  'month': 'Monthly',
  'year': 'Annual',
  'last12': 'Last 12 months',
  'lifetime': 'Lifetime',
};
const woolMetrics = {
  'gross': 'Gross wool',
  'adjusted': 'Adjusted gross wool',
  'prime': 'Prime wool',
};
const woolWeightKeys = {
  'PRIME',
  'GRADE2',
  'COMBINGS',
  'FELTEDSTAINED',
  'BODYWT',
};

double? woolGross(Map r) {
  final m = canonicalWool(r['measurements'] as Map? ?? {});
  return gradedWoolTotal(m) ?? measurementNumber(r['fleece_grams']);
}

double? woolYield(Map r, String metric, Map factors) {
  final m = canonicalWool(r['measurements'] as Map? ?? {});
  if (metric == 'gross') return woolGross(r);
  if (metric == 'prime') return measurementNumber(m['PRIME']);
  var any = false;
  var total = 0.0;
  for (final k in ['PRIME', 'GRADE2', 'COMBINGS', 'FELTEDSTAINED']) {
    final n = measurementNumber(m[k]);
    if (n != null) {
      any = true;
      total += n * (measurementNumber(factors[k]) ?? 0) / 100;
    }
  }
  return any ? total : null;
}

String woolWeightText(dynamic grams, String unit) {
  final n = measurementNumber(grams);
  if (n == null) return 'Unknown';
  if (unit == 'lb_oz') {
    final oz = n / 28.3495, lb = (oz / 16).floor();
    return '$lb lb ${measurementText(oz - lb * 16)} oz';
  }
  final divisor = switch (unit) {
    'kg' => 1000.0,
    'oz' => 28.3495,
    'lb' => 453.592,
    _ => 1.0,
  };
  return '${measurementText(n / divisor)} $unit';
}

/// Calendar buckets sum actual dated harvests. Undated or removed records do not
/// create a reporting period; cumulative feed is never passed to this function.
Map<String, double> woolSummary(
  List<Map<String, dynamic>> rows,
  Map settings, {
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  final period = settings['period'] ?? 'month',
      metric = settings['metric'] ?? 'gross';
  final start12 = DateTime(today.year - 1, today.month, today.day);
  final result = <String, double>{};
  for (final r in rows) {
    if (r['voided'] == true) continue;
    final d = DateTime.tryParse(r['recorded_date']?.toString() ?? '');
    if (d == null || d.isAfter(DateTime(today.year, today.month, today.day))) {
      continue;
    }
    if (period == 'last12' && !d.isAfter(start12)) continue;
    final v = woolYield(
      r,
      metric,
      settings['factors'] as Map? ?? defaultWoolSettings['factors'] as Map,
    );
    if (v == null || v <= 0) continue;
    String day(DateTime date) => date.toIso8601String().substring(0, 10);
    final key = switch (period) {
      'day' => day(d),
      'week' =>
        '${day(DateTime(d.year, d.month, d.day - d.weekday + 1))} (week starting Monday)',
      'year' => '${d.year}',
      'last12' => 'Last 12 months',
      'lifetime' => 'Lifetime',
      _ => day(d).substring(0, 7),
    };
    result[key] = (result[key] ?? 0) + v;
  }
  return Map.fromEntries(
    result.entries.toList()..sort((a, b) => b.key.compareTo(a.key)),
  );
}

/// Weight entry units affect presentation only; storage and imported evidence
/// remain in grams. Pounds & ounces accepts e.g. "1 lb 4 oz".
double woolUnitDivisor(String unit) => switch (unit) {
  'kg' => 1000.0,
  'oz' => 28.3495,
  'lb' => 453.592,
  _ => 1.0,
};
String woolEntryText(dynamic grams, String unit) {
  final n = measurementNumber(grams);
  if (n == null) return '';
  if (unit == 'lb_oz') return woolWeightText(n, unit);
  return (n / woolUnitDivisor(unit))
      .toStringAsPrecision(12)
      .replaceFirst(RegExp(r'\.?0+$'), '');
}

double? woolEntryGrams(String value, String unit) {
  if (value.trim().isEmpty) return null;
  if (unit == 'lb_oz') {
    final m = RegExp(
      r'^\s*(\d+(?:\.\d+)?)\s*lb\s+(\d+(?:\.\d+)?)\s*oz\s*$',
    ).firstMatch(value);
    if (m == null) {
      throw const FormatException(
        'Enter pounds and ounces, for example 1 lb 4 oz.',
      );
    }
    final lb = double.parse(m[1]!), oz = double.parse(m[2]!);
    if (oz >= 16) throw const FormatException('Ounces must be less than 16.');
    return lb * 453.592 + oz * 28.3495;
  }
  final n = double.tryParse(value);
  if (n == null || !n.isFinite) {
    throw const FormatException('Enter a valid weight.');
  }
  return n * woolUnitDivisor(unit);
}

void attachWoolPedigreeSummary(
  Map<String, dynamic> pedigree,
  List<Map<String, dynamic>> animals,
  List<Map<String, dynamic>> settings,
  List<Map<String, dynamic>> records, {
  DateTime? now,
}) {
  final byAnimal = {for (final a in animals) a['id']: a};
  final byHerd = {for (final s in settings) s['ring_id']: s};
  for (final value in pedigree.values.whereType<Map>()) {
    value.remove('wool_summary');
    final id = value['id'] ?? value['existing_id'];
    final config = byHerd[byAnimal[id]?['ring_id']];
    if (config == null || config['show_on_pedigree'] != true) continue;
    final totals = woolSummary(
      records.where((r) => r['animal_id'] == id).toList(),
      config,
      now: now,
    );
    if (totals.isEmpty) continue;
    final first = totals.entries.first;
    value['wool_summary'] =
        '${woolMetrics[config['metric']]} · ${first.key}: ${woolWeightText(first.value, config['unit'])}';
  }
}
