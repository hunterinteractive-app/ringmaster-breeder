import 'color_labels.dart';

/// Conditional underlying color families only. Silvering is deliberately not
/// assigned a genotype: expression can vary, including in heterozygotes.
/// Evidence and assumptions: docs/genetics/silvered-breeds.md.
class SilveredBreedRules {
  static String breedKey(dynamic value) => RabbitColorLabels.breedKey(
    value,
  ).replaceAll(RegExp(r'[\u0300-\u036f]'), '').replaceAll(RegExp('[^a-z]'), '');

  static const _colors = <String, Map<String, String>>{
    'silver': {
      'black': 'black',
      'blue': 'blue',
      'brown': 'chestnut',
      'fawn': 'orange',
    },
    'silverfox': {
      'black': 'black',
      'blue': 'blue',
      'chocolate': 'chocolate',
      'lilac': 'lilac',
    },
    'argentbrun': {'standard': 'chocolate', 'chocolate': 'chocolate'},
    'argentebrun': {'standard': 'chocolate', 'chocolate': 'chocolate'},
    'champagnedargent': {'standard': 'black', 'black': 'black'},
    'champagnedargente': {'standard': 'black', 'black': 'black'},
    'cremedargent': {'standard': 'orange', 'orange': 'orange'},
    'cremedargente': {'standard': 'orange', 'orange': 'orange'},
    'argentesthubert': {
      'chesnut agouti': 'chestnut', // Preserve the captured catalog spelling.
      'chestnut agouti': 'chestnut',
      'chestnut': 'chestnut',
      'chocolate agouti': 'chocolate agouti',
      'opal': 'opal',
      'lynx': 'lynx',
    },
  };
  static bool handles(dynamic breed) => _colors.containsKey(breedKey(breed));
  static String _label(dynamic value) =>
      RabbitColorLabels.withoutCod(RabbitColorLabels.normalize(value));
  static bool needsDetails(Map<String, dynamic> animal) =>
      [
        'englishlop',
        'frenchlop',
        'minilop',
      ].contains(breedKey(animal['breed'])) &&
      _label(animal['variety']).replaceAll(RegExp(r'\s*/\s*'), '/') ==
          'silver/silver fox';

  static bool appliesTo(Map<String, dynamic> animal) =>
      handles(animal['breed']) ||
      needsDetails(animal) ||
      (breedKey(animal['breed']) == 'netherlanddwarf' &&
          _label(animal['variety']) == 'champagne');

  // An explicit underlying family is usable without interpreting an ambiguous
  // showroom Brown/Fawn label or asserting a silvering genotype.
  static String? _underlying(dynamic value) {
    final label = _label(value);
    return switch (label) {
      'black' ||
      'blue' ||
      'chocolate' ||
      'lilac' ||
      'chestnut' ||
      'chocolate agouti' ||
      'opal' ||
      'lynx' ||
      'orange' ||
      'cream' => label,
      'chestnut agouti' => 'chestnut',
      _ => null,
    };
  }

  static String? colorOf(Map<String, dynamic> animal) {
    if (needsDetails(animal)) {
      final details = animal['color_details'];
      return details is Map
          ? _underlying(details['color']) ?? _underlying(details['base_color'])
          : null;
    }
    if (breedKey(animal['breed']) == 'netherlanddwarf' &&
        _label(animal['variety']) == 'champagne') {
      return 'black';
    }
    return _colors[breedKey(animal['breed'])]?[_label(animal['variety'])];
  }

  static Map<String, String>? detailExample(Map<String, dynamic> animal) =>
      needsDetails(animal) ? {'color': 'Black'} : null;

  static String? unresolvedIssue(Map<String, dynamic> animal) {
    if (!needsDetails(animal)) return null;
    return '${animal['breed']} — ${animal['variety']} needs a specific underlying color in Additional color details. Black or Blue can identify a base; Brown and Fawn alone are ambiguous here. Missing, conflicting or unsupported descriptions block this estimate. Silvering is not predicted.';
  }

  static const limitation =
      'These cards show underlying color families only. Whether silvering appears, how much develops, its placement and the age it develops are not predicted. Even a 100% color-family result does not guarantee a silvered kit or its adult appearance. Shade, ticking, smut and show quality are not calculated.';
  static const scope =
      'Silver/argent underlying-color preview. The recorded variety is interpreted using a conditional full-color self, agouti or orange background. Unknown carriers remain ranges. No silvering genotype is inferred. $limitation';

  /// Work on copies so imported labels and saved descriptions remain intact.
  /// Other details still pass through the shared compatibility checks.
  static Map<String, dynamic>? prepare(Map<String, dynamic> animal) {
    final color = colorOf(animal);
    if (color == null) return null;
    final details = animal['color_details'];
    return {
      ...animal,
      'variety': color,
      if (details is Map)
        'color_details': {
          for (final entry in details.entries)
            entry.key: _prepareDetail(animal, entry.key, entry.value),
        },
    };
  }

  static dynamic _prepareDetail(
    Map<String, dynamic> animal,
    dynamic key,
    dynamic value,
  ) {
    final breed = animal['breed'];
    if (['color', 'base_color'].contains(key)) {
      if (needsDetails(animal)) return _underlying(value) ?? value;
      if (breedKey(breed) == 'netherlanddwarf' &&
          _label(value) == 'champagne') {
        return 'black';
      }
      return _colors[breedKey(breed)]?[_label(value)] ?? value;
    }
    if (key == 'pattern' && ['silvered', 'silvering'].contains(_label(value))) {
      return ''; // Description only, not proof of si/si or Si/si.
    }
    return value;
  }

  static String? interpretationNote(Map<String, dynamic> animal) {
    final color = colorOf(animal);
    return color == null
        ? null
        : needsDetails(animal)
        ? '${animal['breed']}: ${animal['variety']} uses the saved color details ($color family underneath silvering)'
        : '${animal['breed']} — ${animal['variety']}: $color family underneath silvering';
  }

  static String outcomeLabel(String label) =>
      '$label family (silvering not predicted)';
}
