/// Interpretation of recorded labels only. This never updates rabbit records or
/// treats a breed/COD label as proof of a complete genotype. Source notes and
/// conditional phenotype interpretations: docs/genetics/name-mappings.md.
class RabbitColorLabels {
  static String normalize(dynamic value) => (value?.toString() ?? '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll('–', '-');

  static String withoutCod(String value) =>
      value.replaceFirst(RegExp(r'\s*\(\s*cod\s*\)\s*$'), '').trim();

  static String breedKey(dynamic value) => withoutCod(normalize(value))
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('’', "'")
      .replaceAll('‘', "'");

  /// Standard is a showroom label. Each interpretation is breed-specific and
  /// remains conditional on the recorded breed/color being accurate.
  static const standardColors = <String, String>{
    'american chinchilla': 'chinchilla',
    'american sable': 'sable',
    'blue holicer': 'blue',
    'cinnamon': 'black tortoise',
    'cinnimini': 'black tortoise',
    'czech frosty': 'frosty',
    'florida white': 'ruby eyed white',
    'giant chinchilla': 'chinchilla',
    'lilac': 'lilac',
    'mini californian': 'black pointed white',
    'standard chinchilla': 'chinchilla',
    'thrianta': 'red',
  };

  static String canonicalVariety(Map<String, dynamic> animal) {
    var name = withoutCod(normalize(animal['variety']));
    // Keep the encoded pattern: removing parentheses must not make a broken
    // rabbit solid, or silently turn a recorded Charlie into a broken.
    final suffix = RegExp(r'^(.*?)\s*\((broken|charlie)\)$').firstMatch(name);
    if (suffix != null) name = '${suffix[2]} ${suffix[1]!.trim()}';
    // Preserve the abbreviated tortoise inputs accepted by the original
    // Dutch preview when using the broader coat interpreter.
    name = name.replaceAllMapped(
      RegExp(r'(^| )(tort\.) - (black|blue|choc\.|lilac)$'),
      (m) => '${m[1]}${m[3] == 'choc.' ? 'chocolate' : m[3]} tortoise',
    );
    final breed = breedKey(animal['breed']);
    if (name == 'standard') return standardColors[breed] ?? name;
    // The Cinnamon breed's coat interpretation differs from generic chocolate
    // agouti, which is also called cinnamon in other breed/color vocabularies.
    if (breed == 'cinnamon' && name == 'cinnamon') return 'black tortoise';
    return name;
  }

  static String? interpretationNote(Map<String, dynamic> animal) {
    final raw = withoutCod(normalize(animal['variety']));
    final canonical = canonicalVariety(animal);
    if (raw == 'standard' && canonical != raw ||
        breedKey(animal['breed']) == 'cinnamon' && raw == 'cinnamon') {
      return '${animal['breed']}: ${animal['variety']} is interpreted as $canonical';
    }
    return null;
  }

  /// Use the same guard for punctuation/accent/COD spellings. Normalizing a
  /// label must never unlock a breed whose special context is not implemented.
  static bool needsDedicatedBreedRules(dynamic breed) => const {
    'dwarfhotot',
    'blancdehotot',
    'hotot',
    'englishspot',
    'checkeredgiant',
    'rhinelander',
    'dwarfpapillon',
    'silver',
    'silverfox',
    'argentbrun',
    'argentebrun',
    'argentesthubert',
    'champagnedargent',
    'cremedargent',
    'cremedargente',
  }.contains(breedKey(breed).replaceAll(RegExp('[^a-z]'), ''));
}
