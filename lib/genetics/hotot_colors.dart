import 'color_labels.dart';

/// A deliberately limited B/D pigment interpretation. This does not assign
/// English/Dutch spotting alleles or predict the development of eye bands.
class HototColorRules {
  static String breedKey(dynamic value) =>
      RabbitColorLabels.breedKey(value).replaceAll(RegExp('[^a-z]'), '');
  static bool handles(dynamic breed) =>
      ['dwarfhotot', 'blancdehotot'].contains(breedKey(breed));

  static const limitation =
      'Only inherited base pigment is estimated. This does not predict whether eye bands will appear, their width or placement, body markings, or eye color. Even a 100% pigment result does not guarantee a correctly marked kit.';
  static String scopeFor(String breed) =>
      '$breed eye-band pigment model: Black, Blue, Chocolate and Lilac. $limitation Other color genes and white masking can change the visible result. Unknown carriers remain ranges; no complete genotype is inferred.';
  static const _bases = ['black', 'blue', 'chocolate', 'lilac'];
  static const _groups = ['standard', 'white', 'black/blue/chocolate/lilac'];

  static String _label(dynamic value) => RabbitColorLabels.withoutCod(
    RabbitColorLabels.normalize(value),
  ).replaceAll(RegExp(r'\s*/\s*'), '/');

  static String? _base(dynamic value) {
    final label = _label(value);
    if (_bases.contains(label)) return label;
    return RegExp(
      r'^(black|blue|chocolate|lilac) (?:eye[- ]?bands?|bands?)$',
    ).firstMatch(label)?.group(1);
  }

  static bool needsDetails(Map<String, dynamic> animal) =>
      handles(animal['breed']) &&
      _groups.contains(_label(animal['variety'])) &&
      !(breedKey(animal['breed']) == 'blancdehotot' &&
          _label(animal['variety']) == 'standard');

  static String? baseColorOf(Map<String, dynamic> animal) {
    if (!handles(animal['breed'])) return null;
    final label = _label(animal['variety']);
    final named =
        breedKey(animal['breed']) == 'blancdehotot' && label == 'standard'
        ? 'black'
        : _base(label);
    if (named != null) return named;
    if (!needsDetails(animal)) return null;
    final details = animal['color_details'];
    if (details is! Map) return null;
    return _base(details['color']) ?? _base(details['base_color']);
  }

  static String? inputIssue(Map<String, dynamic> animal) {
    final breed = animal['breed']?.toString() ?? '';
    if (animal['color_details'] != null && animal['color_details'] is! Map) {
      return '$breed: Additional color details could not be read. Check the saved details or contact support before calculating.';
    }
    if (RabbitColorLabels.normalize(animal['species']) != 'rabbit' ||
        !handles(breed)) {
      return 'Choose two rabbits of the same Hotot breed for this limited pigment preview.';
    }
    final base = baseColorOf(animal);
    if (base == null) {
      return '$breed — ${animal['variety'] ?? ''} needs a specific eye-band pigment (Black, Blue, Chocolate or Lilac) in the variety or Additional color details. White alone does not identify the pigment.';
    }
    final details = animal['color_details'];
    if (details is Map) {
      for (final entry in details.entries) {
        final value = _label(entry.value);
        if (value.isEmpty) continue;
        if (['color', 'base_color'].contains(entry.key)) {
          // A generic White annotation cannot substitute for band pigment.
          // Redundant Standard is allowed only for the reviewed Blanc label.
          final detailBase =
              value == 'standard' &&
                  breedKey(breed) == 'blancdehotot' &&
                  _label(animal['variety']) == 'standard'
              ? 'black'
              : _base(value);
          if (detailBase == base) continue;
          return '$breed has missing, conflicting or unsupported eye-band color details. The pigment descriptions must agree.';
        }
        if (entry.key == 'pattern' &&
            const [
              'hotot',
              'eye band',
              'eye bands',
              'eyeband',
              'eyebands',
              'eye-band',
              'eye-bands',
              'hotot eye bands',
              'solid',
              'solid pattern',
              'unspotted',
              'broken',
              'broken pattern',
              'spotted',
              'spotted pattern',
              'charlie',
              'charlie-pattern',
              'dutch',
            ].contains(value)) {
          // These are retained descriptions, not evidence for an En/du state.
          continue;
        }
        if (entry.key == 'eye_color' &&
            const [
              'brown',
              'dark brown',
              'blue',
              'blue gray',
              'blue-gray',
              'blue grey',
              'blue-grey',
              'china blue',
            ].contains(value)) {
          // In particular, a blue eye is not treated as proof of Vienna white.
          continue;
        }
        return '$breed has additional color or pattern information that this limited eye-band pigment preview cannot interpret yet.';
      }
    }
    return null;
  }

  static String? interpretationNote(Map<String, dynamic> animal) {
    if (!handles(animal['breed']) || inputIssue(animal) != null) return null;
    final base = baseColorOf(animal)!;
    return '${animal['breed']} — ${animal['variety']}: $base eye-band base pigment only';
  }
}
