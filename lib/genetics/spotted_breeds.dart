import 'color_labels.dart';
import 'mendelian.dart';

/// Conditional phenotype interpretations, not marker-test results or a claim
/// about exact markings. Missing spotting information remains unconstrained.
class SpottedBreedInput {
  final String color;
  final String pattern;
  final List<AllelePair> spotting;
  const SpottedBreedInput(this.color, this.pattern, this.spotting);
}

class SpottedBreedRules {
  static String breedKey(dynamic breed) =>
      RabbitColorLabels.breedKey(breed).replaceAll(RegExp('[^a-z]'), '');
  static bool handles(dynamic breed) => const {
    'checkeredgiant',
    'englishspot',
    'dwarfpapillon',
    'rhinelander',
  }.contains(breedKey(breed));

  static const _bases = ['black', 'blue', 'chocolate', 'lilac'];
  static const _unknown = [
    AllelePair('en', 'en'),
    AllelePair('En', 'en'),
    AllelePair('En', 'En'),
  ];
  static const scope =
      'Spotted-breed preview: color and spotting inheritance are estimated separately. A breed name does not establish the parent’s spotting genes. Missing spotting information stays unknown. White genes can hide inherited markings. Exact spot placement, amount of white and show quality are not predicted.';

  static String? _pattern(String value, String breed) => switch (value) {
    'solid' || 'solid pattern' || 'unspotted' => 'solid',
    'broken' || 'broken pattern' || 'spotted' || 'spotted pattern' => 'broken',
    'charlie' || 'charlie-pattern' || 'minimal marking (charlie)' => 'charlie',
    'checkered' when breed == 'checkeredgiant' || breed == 'rhinelander' =>
      'broken',
    'english spot' when breed == 'englishspot' => 'broken',
    'dwarf papillon' when breed == 'dwarfpapillon' => 'broken',
    _ => null,
  };

  static SpottedBreedInput? resolve(Map<String, dynamic> animal) {
    final breed = breedKey(animal['breed']);
    if (!handles(animal['breed'])) return null;
    var name = RabbitColorLabels.canonicalVariety(animal);
    String? namedPattern;
    for (final prefix in ['broken ', 'charlie ', 'unspotted ', 'solid ']) {
      if (name.startsWith(prefix)) {
        namedPattern = switch (prefix.trim()) {
          'unspotted' || 'solid' => 'solid',
          final value => value,
        };
        name = name.substring(prefix.length);
        break;
      }
    }
    final details = animal['color_details'];
    final rawPattern = details is Map
        ? RabbitColorLabels.normalize(details['pattern'])
        : '';
    final recordedPattern = _pattern(rawPattern, breed);
    if (namedPattern != null &&
        recordedPattern != null &&
        namedPattern != recordedPattern) {
      return null;
    }
    // Other pattern descriptions still go through CoatRules' compatibility
    // checks; unknown wording must never become an implicit spotted genotype.
    final pattern = recordedPattern ?? namedPattern;
    String? color;
    if (breed == 'rhinelander') {
      color = switch (name) {
        'black' || 'black/orange' || 'black and orange' => 'black harlequin',
        'blue' || 'blue/fawn' || 'blue and fawn' => 'blue harlequin',
        _ => null,
      };
    } else if (breed == 'checkeredgiant') {
      if (['black', 'blue'].contains(name)) color = name;
    } else if (breed == 'englishspot') {
      if (_bases.contains(name)) color = name;
      if ([
        'tortoise',
        'tortoise shell',
        'tortoiseshell',
        'black tortoise',
      ].contains(name)) {
        color = 'black tortoise';
      }
      // Conditional family interpretations from the club's phenotype and
      // cross references. Exact English Spot ticking/shade is not modeled.
      if (['gray', 'grey'].contains(name)) color = 'chestnut';
      if (name == 'gold') color = 'orange';
    } else if (breed == 'dwarfpapillon') {
      if (_bases.contains(name)) color = name;
      final tort = [
        'tortoise',
        'tortoise shell',
        'tortoiseshell',
      ].contains(name);
      final tri = [
        'tri color',
        'tri-color',
        'tri-colored',
        'tricolor',
        'tricolor group',
      ].contains(name);
      if (tort || tri) {
        final recordedColor = details is Map
            ? RabbitColorLabels.normalize(details['color'])
            : '';
        final base = details is Map
            ? RabbitColorLabels.normalize(details['base_color'])
            : '';
        final specified = recordedColor.isNotEmpty ? recordedColor : base;
        final family = tort ? 'tortoise' : 'harlequin';
        if (_bases.contains(specified)) color = '$specified $family';
        for (final b in _bases) {
          if (specified == '$b $family') color = specified;
        }
      }
    }
    if (color == null) return null;
    final spotting = switch (pattern) {
      'solid' => const [AllelePair('en', 'en')],
      'broken' => const [AllelePair('En', 'en')],
      'charlie' => const [AllelePair('En', 'En')],
      _ => _unknown,
    };
    return SpottedBreedInput(
      color,
      // Preserve an unrecognized/phenotype pattern so normal validation can
      // reject it or verify it against the named color family.
      recordedPattern ?? (rawPattern.isEmpty ? namedPattern ?? '' : rawPattern),
      spotting,
    );
  }

  /// Audit-only examples; never defaults for missing rabbit information.
  static Map<String, String>? detailExample(Map<String, dynamic> animal) {
    if (breedKey(animal['breed']) != 'dwarfpapillon') return null;
    return switch (RabbitColorLabels.canonicalVariety(animal)) {
      'tortoise' ||
      'tortoise shell' ||
      'tortoiseshell' => {'color': 'Black Tortoise'},
      'tri color' ||
      'tri-color' ||
      'tri-colored' ||
      'tricolor' ||
      'tricolor group' => {'color': 'Black'},
      _ => null,
    };
  }

  static const colorFamilyLimitation =
      'Gray uses an assumed agouti background; Gold uses an orange/gold color family. Exact English Spot ticking, shade and show quality are not predicted. Even a 100% family result does not guarantee a correctly colored Gray or Gold kit.';

  static String? familyLimitationFor(
    Map<String, dynamic> sire,
    Map<String, dynamic> dam,
  ) {
    if (breedKey(sire['breed']) != 'englishspot') return null;
    return [
          resolve(sire)?.color,
          resolve(dam)?.color,
        ].any((c) => ['chestnut', 'orange'].contains(c))
        ? colorFamilyLimitation
        : null;
  }

  /// Interpret repeated color details in the same breed context as the main
  /// label. This must never introduce a global gray/grey alias.
  static String colorDetailLabel(dynamic breed, String detail) {
    if (breedKey(breed) != 'englishspot') return detail;
    return switch (detail) {
      'gray' || 'grey' => 'chestnut',
      'gold' => 'orange',
      _ => detail,
    };
  }

  static String? interpretationNote(Map<String, dynamic> animal) {
    final input = resolve(animal);
    if (input == null) return null;
    final meaning = input.spotting.length > 1
        ? 'spotting is not recorded and remains unknown'
        : switch (input.spotting.single.key) {
            'en/en' => 'uses the recorded unspotted pattern',
            'En/en' => 'uses the recorded spotted pattern',
            _ => 'uses the recorded Charlie pattern',
          };
    final color = breedKey(animal['breed']) == 'englishspot'
        ? switch (input.color) {
            'chestnut' =>
              'agouti / Gray-type family (exact ticking not predicted)',
            'orange' => 'Gold / orange family (exact shade not predicted)',
            _ => input.color,
          }
        : input.color;
    return '${animal['breed']} — ${animal['variety']}: $color; $meaning';
  }

  static String outcomeLabel(
    String label, {
    required bool white,
    dynamic breed,
  }) {
    if (white) return label;
    var prefix = 'Unspotted ';
    var color = label;
    if (label.startsWith('Broken ')) {
      prefix = 'Spotted ';
      color = label.substring(7);
    } else if (label.startsWith('Charlie-pattern ')) {
      prefix = 'Minimal marking (Charlie) ';
      color = label.substring(16);
    }
    if (breedKey(breed) == 'englishspot') {
      color = switch (color) {
        'Chestnut / castor / gray' => 'Agouti / Gray-type family (black base)',
        'Orange / red / fawn family' =>
          'Gold / orange family (shade not predicted)',
        _ => color,
      };
    }
    return '$prefix$color';
  }

  static String? unresolvedIssue(Map<String, dynamic> animal) {
    final breed = breedKey(animal['breed']);
    if (['dwarfhotot', 'blancdehotot', 'hotot'].contains(breed)) {
      return '${animal['breed']} eye-band and Dutch-pattern interactions need separate rules that are not built yet. Ordinary spotting estimates would not describe those markings.';
    }
    if (!handles(animal['breed'])) return null;
    if (breed == 'dwarfpapillon' &&
        resolve(animal) == null &&
        RegExp(
          r'tort|tri',
        ).hasMatch(RabbitColorLabels.canonicalVariety(animal))) {
      return '${animal['breed']} — ${animal['variety']} needs a specific underlying color (black, blue, chocolate or lilac) in Additional color details. Conflicting or unsupported details cannot be estimated.';
    }
    return '${animal['breed']} — ${animal['variety']} has an unsupported color or conflicting color/pattern details. This spotted-breed preview does not infer a pattern from the breed name.';
  }
}
