import 'color_labels.dart';

/// Reviewed breed-specific descriptions. The shared solver still validates
/// the copied details; these mappings never modify the saved animal.
class BreedColorContexts {
  static String _label(dynamic value) =>
      RabbitColorLabels.withoutCod(RabbitColorLabels.normalize(value));
  static String? kind(Map<String, dynamic> animal) {
    final breed = RabbitColorLabels.breedKey(animal['breed']);
    final name = _label(animal['variety']);
    if (breed == 'belgian hare' && name == 'rufus') return 'rufus';
    if (breed == 'belgian hare' && name == 'tan') return 'hare tan';
    if (breed == 'satin' && name == 'californian') return 'satin pointed';
    if (['english angora', 'french angora', 'satin angora'].contains(breed) &&
        name == 'pearl') {
      return 'angora pearl';
    }
    if (['satin', 'mini satin'].contains(breed) && name == 'siamese') {
      return 'satin siamese';
    }
    if (['rex', 'mini rex'].contains(breed) && name == 'brindle') {
      return 'rex brindle';
    }
    if (breed == 'mini rex' && name == 'tan') return 'mini rex tan';
    if (breed == 'palomino' && name == 'lynx') return 'palomino lynx';
    if (breed == 'netherland dwarf' && name == 'lutino') return 'dwarf lutino';
    if (breed == 'flemish giant' && name == 'sandy') return 'flemish sandy';
    if (breed == 'flemish giant' &&
        ['steel gray', 'steel grey'].contains(name)) {
      return 'flemish steel';
    }
    if (breed == 'flemish giant' &&
        ['light gray', 'light grey'].contains(name)) {
      return 'flemish light gray';
    }
    return null;
  }

  static bool needsDetails(Map<String, dynamic> animal) => [
    'hare tan',
    'satin pointed',
    'angora pearl',
    'satin siamese',
    'rex brindle',
    'mini rex tan',
    'palomino lynx',
    'dwarf lutino',
  ].contains(kind(animal));
  static const _bases = ['black', 'blue', 'chocolate', 'lilac'];
  static String? _color(String context, dynamic value) {
    final label = _label(value);
    if (context == 'dwarf lutino') {
      // Only explicit underlying families are usable. Lutino/Dove/Shadow
      // names alone do not identify the complete A/B/C/D/E background.
      return const {
        'black': 'black',
        'blue': 'blue',
        'chocolate': 'chocolate',
        'lilac': 'lilac',
        'chestnut': 'chestnut',
        'chocolate agouti': 'chocolate agouti',
        'opal': 'opal',
        'lynx': 'lynx',
        'orange': 'orange',
        'cream': 'cream',
        'black otter': 'black otter',
        'blue otter': 'blue otter',
        'chocolate otter': 'chocolate otter',
        'lilac otter': 'lilac otter',
        'black tortoise': 'black tortoise',
        'blue tortoise': 'blue tortoise',
        'chocolate tortoise': 'chocolate tortoise',
        'lilac tortoise': 'lilac tortoise',
      }[label];
    }
    if (context == 'rufus') return label == 'rufus' ? 'chestnut' : null;
    if (context == 'flemish sandy') return label == 'sandy' ? 'chestnut' : null;
    if (context == 'flemish steel') {
      return [
            'steel gray',
            'steel grey',
            'black silver-tipped steel',
          ].contains(label)
          ? 'black silver-tipped steel'
          : null;
    }
    if (context == 'palomino lynx') {
      // Require an explicit underlying family; the showroom Lynx name alone
      // is disputed and must never silently select genetic lynx or cream.
      return switch (label) {
        'lilac agouti' || 'agouti - lilac' => 'agouti - lilac',
        'cream' || 'dilute non-extension agouti' => 'cream',
        _ => null,
      };
    }
    if (context == 'satin siamese' || context == 'angora pearl') {
      for (final base in _bases) {
        if (context == 'angora pearl' &&
            [base, '$base pearl', 'pearl - $base'].contains(label)) {
          return '$base pearl';
        }
        if ([
          '$base sallander',
          '$base chinchilla pearl',
          '$base non-extension self chinchilla',
        ].contains(label)) {
          return '$base non-extension self chinchilla';
        }
        if (['$base sable pearl', '$base sable point'].contains(label)) {
          return '$base sable point';
        }
        if (context == 'satin siamese' &&
            ['$base sable', '$base seal'].contains(label)) {
          return label;
        }
      }
      return null;
    }
    if (context == 'rex brindle') {
      for (final base in _bases) {
        final partner = ['blue', 'lilac'].contains(base) ? 'fawn' : 'orange';
        if ([
          base,
          '$base/$partner',
          '$base / $partner',
          '$base and $partner',
          '$base brindle',
        ].contains(label)) {
          return '$base harlequin';
        }
      }
      return null;
    }
    if (context == 'flemish light gray') {
      return [
            'light gray',
            'light grey',
            'chinchilla',
            'black chinchilla',
          ].contains(label)
          ? 'black chinchilla'
          : null;
    }
    final family = ['hare tan', 'mini rex tan'].contains(context)
        ? 'otter'
        : 'pointed white';
    for (final base in _bases) {
      if ([
        base,
        '$base $family',
        if (['hare tan', 'mini rex tan'].contains(context)) '$base tan',
        if (context == 'satin pointed') '$base himalayan',
        if (context == 'satin pointed') '$base californian',
      ].contains(label)) {
        return '$base $family';
      }
    }
    return null;
  }

  static String? colorOf(Map<String, dynamic> animal) {
    final context = kind(animal);
    if (context == null) return null;
    if (context == 'rufus') return 'chestnut';
    if (context == 'flemish sandy') return 'chestnut';
    if (context == 'flemish steel') return 'black silver-tipped steel';
    if (context == 'flemish light gray') return 'black chinchilla';
    final details = animal['color_details'];
    if (context == 'mini rex tan' &&
        (details is! Map || _label(details['pattern']) != 'tan')) {
      return null;
    }
    if (context == 'palomino lynx') {
      if (details is! Map) return null;
      final color = _color(context, details['color']);
      final pattern = _label(details['pattern']);
      if (color == 'agouti - lilac' && pattern == 'agouti' ||
          color == 'cream' && pattern == 'non-extension') {
        return color;
      }
      return null;
    }
    if (context == 'dwarf lutino') {
      if (details is! Map) return null;
      final color = _color(context, details['color']);
      final pattern = _label(details['pattern']);
      final expected = _bases.contains(color)
          ? 'self'
          : [
              'chestnut',
              'chocolate agouti',
              'opal',
              'lynx',
              'orange',
              'cream',
            ].contains(color)
          ? 'agouti'
          : color?.endsWith('otter') == true
          ? 'otter'
          : 'tortoise';
      return color != null && pattern == expected ? color : null;
    }
    return details is Map
        ? _color(context, details['color']) ??
              _color(context, details['base_color'])
        : null;
  }

  static Map<String, dynamic>? prepare(Map<String, dynamic> animal) {
    final context = kind(animal), color = colorOf(animal);
    if (context == null || color == null) return null;
    final details = animal['color_details'];
    return {
      ...animal,
      'variety': color,
      if (details is Map)
        'color_details': {
          for (final e in details.entries)
            e.key: ['color', 'base_color'].contains(e.key)
                ? _color(context, e.value) ?? e.value
                : e.key == 'pattern'
                ? _pattern(context, color, e.value)
                : e.value,
        },
    };
  }

  static dynamic _pattern(String context, String color, dynamic value) {
    final pattern = _label(value);
    if (context == 'satin pointed' &&
        ['himalayan', 'californian'].contains(pattern)) {
      return 'pointed white';
    }
    if (context == 'rex brindle' && pattern == 'brindle') return 'harlequin';
    if (context == 'palomino lynx' && pattern == 'non-extension') {
      return 'agouti';
    }
    if (['angora pearl', 'satin siamese'].contains(context) &&
        ['pearl', 'siamese', 'shaded'].contains(pattern)) {
      if (color.endsWith('non-extension self chinchilla')) {
        return 'non-extension self chinchilla';
      }
      return color.endsWith(' pearl') ? 'pearl' : 'shaded';
    }
    return value;
  }

  static String? unresolvedIssue(Map<String, dynamic> animal) {
    final context = kind(animal);
    if (context == null) return null;
    if (needsDetails(animal) && colorOf(animal) == null) {
      if (context == 'satin siamese') {
        return '${animal['breed']} — Siamese needs a verified underlying color family in Additional color details, such as Black Sable, Black Sable Point or Black Sallander. A pigment color alone cannot distinguish these backgrounds. Contact support if it is unknown.';
      }
      if (context == 'dwarf lutino') {
        return 'Netherland Dwarf — Lutino needs its verified underlying color and pattern in Additional color details, such as Color Black with Pattern Self, or Color Orange with Pattern Agouti. Lutino can hide this information; do not guess from its pale appearance. Contact support if it is unknown.';
      }
      if (context == 'palomino lynx') {
        return 'Palomino — Lynx needs a verified underlying family: Color Lilac Agouti with Pattern Agouti, or Color Cream with Pattern Non-extension. These are different interpretations; do not choose one by appearance alone. Contact support if the background is unknown.';
      }
      if (context == 'mini rex tan') {
        return 'Mini Rex — Tan needs a recorded Black, Blue, Chocolate or Lilac base and an explicit Tan pattern in Additional color details. The label alone does not establish this legacy variety’s background. Exact tan intensity and wideband are not predicted.';
      }
      if (context == 'rex brindle') {
        return '${animal['breed']} — Brindle needs its actual color pair in Additional color details: Black/Orange, Blue/Fawn, Chocolate/Orange or Lilac/Fawn. Color mixing and show markings are not predicted.';
      }
      if (context == 'angora pearl') {
        return '${animal['breed']} — Pearl needs its actual Black, Blue, Chocolate or Lilac color in Additional color details. Unknown chinchilla/sable background remains a range; do not guess the pigment.';
      }
      return '${animal['breed']} — ${animal['variety']} includes Black, Blue, Chocolate and Lilac. Save the actual color in Additional color details before calculating; the group name alone does not identify it.';
    }
    return '${animal['breed']} — ${animal['variety']} has conflicting or unsupported color details for this breed interpretation.';
  }

  static String? interpretationNote(Map<String, dynamic> animal) {
    final color = colorOf(animal);
    if (color == null) return null;
    if (needsDetails(animal)) {
      return '${animal['breed']}: ${animal['variety']} uses the saved color details ($color)';
    }
    return '${animal['breed']} — ${animal['variety']}: $color family under the stated model';
  }

  static const rufusLimitation =
      'Rufus is estimated using a conditional black-based agouti background. The depth of red, wideband/rufus modifiers, wavy ticking, ear lacing and show quality are not predicted. A color-family result does not guarantee the Belgian Hare Rufus appearance.';
  static const lightGrayLimitation =
      'Flemish Giant Light Gray is estimated as a black-based chinchilla color family. Exact gray shade, ticking, ring definition, coat changes with age and show quality are not predicted. A color-family result does not guarantee the complete Light Gray appearance.';
  static const sandyLimitation =
      'Sandy uses a conditional black-based agouti color family. Wideband inheritance, red intensity, band width, ticking and show quality are not predicted; an agouti result does not guarantee the complete Sandy appearance.';
  static const steelLimitation =
      'Steel Gray uses a conditional black-based silver-tipped steel background with Es/E parents. The steel-family percentage includes offspring with hidden Steel, including those inheriting two Steel copies (Es/Es), which can look nearly solid. It is not the chance of visibly ticked Steel Gray. Exact ticking, shade and show quality are not predicted; a steel-family result does not promise visible Steel Gray.';
  static const pearlLimitation =
      'Pearl estimates use the recorded pigment on a self non-extension background. Unless a specific Sallander or Sable Pearl background is recorded, both chinchilla and sable backgrounds remain possible. Wool shade, sheen, points and show quality are not predicted.';
  static const siameseLimitation =
      'Siamese uses only the explicitly recorded underlying color family. Chinchilla-based Sallander and sable backgrounds are not interchangeable. Exact shading, contrast, sheen, eye color and show quality are not predicted.';
  static const brindleLimitation =
      'Brindle estimates cover the recorded pigment pair and conditional ej brindling inheritance. They do not predict intermixing, bars, patches or marking quality. A brindling-family result is not a guarantee of Brindle rather than Harlequin appearance or show eligibility.';
  static const miniRexTanLimitation =
      'Mini Rex Tan uses only the explicitly recorded pigment and Tan pattern as an underlying otter/tan family. Wideband inheritance, belly color, tan intensity and show quality are not predicted. This does not establish the legacy variety’s recognition status.';
  static const palominoLimitation =
      'Palomino Lynx uses only the explicitly verified underlying family saved in the record. Genetic lilac agouti and cream are different backgrounds; the Lynx label alone does not identify one. Exact pearl-gray shading, banding, modifiers and show quality are not predicted.';
  static const lutinoLimitation =
      'Lutino uses an experimental, conditional recessive p-factor model and the verified underlying family saved in the record. The other parent’s unrecorded p-factor status stays unknown. Lutino-modified family labels do not predict exact pastel shade, eye color, intensity or show quality; white can hide the effect. These are not complete or breed-validated Lutino predictions.';
  static String? limitationFor(
    Map<String, dynamic> sire,
    Map<String, dynamic> dam,
  ) {
    final contexts = [sire, dam].map(kind).toSet();
    final limits = [
      if (contexts.contains('rufus')) rufusLimitation,
      if (contexts.contains('flemish light gray')) lightGrayLimitation,
      if (contexts.contains('flemish sandy')) sandyLimitation,
      if (contexts.contains('flemish steel')) steelLimitation,
      if (contexts.contains('angora pearl')) pearlLimitation,
      if (contexts.contains('satin siamese')) siameseLimitation,
      if (contexts.contains('rex brindle')) brindleLimitation,
      if (contexts.contains('mini rex tan')) miniRexTanLimitation,
      if (contexts.contains('palomino lynx')) palominoLimitation,
      if (contexts.contains('dwarf lutino')) lutinoLimitation,
    ];
    return limits.isEmpty ? null : limits.join(' ');
  }

  static Map<String, String>? detailExample(Map<String, dynamic> animal) =>
      switch (kind(animal)) {
        'satin siamese' => {'color': 'Black Sallander', 'pattern': 'Siamese'},
        'palomino lynx' => {'color': 'Lilac Agouti', 'pattern': 'Agouti'},
        'mini rex tan' => {'color': 'Black', 'pattern': 'Tan'},
        'rex brindle' => {'color': 'Black/Orange', 'pattern': 'Brindle'},
        'dwarf lutino' => {'color': 'Black', 'pattern': 'Self'},
        _ => needsDetails(animal) ? {'color': 'Black'} : null,
      };

  static String outcomeLabel(
    String label,
    Map<String, dynamic> sire,
    Map<String, dynamic> dam,
  ) {
    final contexts = [sire, dam].map(kind).toSet();
    if (contexts.contains('rex brindle')) {
      label = label.replaceAll(
        'Harlequin family',
        'Brindling color family (distribution not predicted)',
      );
    }
    if (contexts.contains('flemish steel') &&
        label.toLowerCase().contains('steel')) {
      label = '$label (may be masked)';
    }
    return label;
  }
}
