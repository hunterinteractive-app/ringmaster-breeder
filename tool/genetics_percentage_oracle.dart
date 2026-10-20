/// Independent audit-only Punnett-square enumerator. No production genetics
/// code is imported. Labels describe the current conditional family contract,
/// not a second source of biological evidence or precise phenotype validation.
typedef Genes = Map<String, List<String>>;

Genes known({String pattern = 'at', String b = 'Bb', String d = 'Dd'}) => {
  'A': [pattern, pattern],
  'B': b.split(''),
  'C': ['C', 'C'],
  'D': d.split(''),
  'E': ['E', 'E'],
  'En': ['en', 'en'],
  'V': ['V', 'V'],
};

String observedFamily(Genes g, {bool spotting = true}) {
  bool both(String locus, String allele) => g[locus]!.every((a) => a == allele);
  bool has(String locus, String allele) => g[locus]!.contains(allele);
  const supported = {
    'A': ['A', 'at', 'a'],
    'B': ['B', 'b'],
    'C': ['C', 'cchd', 'cchl', 'ch', 'c'],
    'D': ['D', 'd'],
    'E': ['Es', 'E', 'ej', 'e'],
    'En': ['En', 'en'],
    'V': ['V', 'v'],
    'P': ['P', 'p'],
  };
  for (final entry in supported.entries) {
    final pair = g[entry.key];
    if (entry.key == 'P' && pair == null) continue;
    if (pair == null ||
        pair.length != 2 ||
        pair.any((a) => !entry.value.contains(a))) {
      throw ArgumentError('Outside audit oracle scope: ${entry.key}');
    }
  }
  if (both('C', 'c') || both('V', 'v')) {
    return 'White (eye color not predicted)';
  }
  final base = both('B', 'b')
      ? (both('D', 'd') ? 'lilac' : 'chocolate')
      : (both('D', 'd') ? 'blue' : 'black');
  final agouti = has('A', 'A'), tan = !has('A', 'A') && has('A', 'at');
  final full = has('C', 'C'), chin = !full && has('C', 'cchd');
  final shaded = !full && !chin && has('C', 'cchl');
  final steel = has('E', 'Es');
  final harlequin = !steel && !has('E', 'E') && has('E', 'ej');
  final nonextension = both('E', 'e');
  String label;
  if (!full && !chin && !shaded) {
    label = 'Himalayan / pointed white ($base base)';
  } else if (shaded) {
    if (harlequin) {
      label = 'Shaded harlequin family ($base base)';
    } else if (nonextension) {
      label = 'Sable-point family ($base base)';
    } else if (!agouti && !tan) {
      label = '${both('C', 'cchl') ? 'Seal' : 'Sable'} family ($base base)';
    } else if (steel) {
      label = 'Shaded steel family ($base base)';
    } else {
      label = 'Sable ${agouti ? 'agouti' : 'marten'} family ($base base)';
    }
  } else if (harlequin) {
    label = '${chin ? 'Magpie' : 'Harlequin'} family ($base base)';
  } else if (nonextension) {
    if (agouti) {
      label = chin
          ? 'Frosted-pearl / ermine family'
          : both('D', 'd')
          ? 'Cream / dilute-fawn family'
          : 'Orange / red / fawn family';
    } else if (tan) {
      label = chin
          ? 'Non-extension marten family ($base base)'
          : 'Fox / torted-otter family ($base base)';
    } else {
      label = chin
          ? 'Non-extension self-chinchilla family ($base base)'
          : 'Tortoise ($base base)';
    }
  } else if (!agouti && !tan) {
    // Self masks Es, including double Steel; do not relabel it as visible Steel.
    label = chin
        ? 'Self chinchilla ($base base)'
        : '${base[0].toUpperCase()}${base.substring(1)}';
  } else if (steel) {
    label = agouti
        ? '${chin ? 'Silver' : 'Gold'}-tipped steel family ($base base)'
        : '${chin ? 'Chinchilla tan-pattern' : 'Tan-pattern'} family with steel ($base base)';
  } else if (tan) {
    label = chin
        ? 'Silver marten ($base base)'
        : 'Otter / tan pattern ($base base)';
  } else if (chin) {
    label = base == 'black'
        ? 'Chinchilla'
        : base == 'blue'
        ? 'Squirrel / blue chinchilla'
        : 'Chinchilla ($base base)';
  } else {
    label = {
      'black': 'Chestnut / castor / gray',
      'blue': 'Opal',
      'chocolate': 'Chocolate agouti / amber',
      'lilac': 'Lynx',
    }[base]!;
  }
  if (spotting && !both('En', 'en')) {
    label = '${both('En', 'En') ? 'Charlie-pattern' : 'Broken'} $label';
  }
  if (g.containsKey('P') && both('P', 'p')) {
    label = 'Lutino-modified family: $label (shade not predicted)';
  }
  return label;
}

Map<String, double> square(Genes sire, Genes dam, {bool spotting = true}) {
  final loci = sire.keys.toList(), counts = <String, int>{};
  if (loci.toSet().difference(dam.keys.toSet()).isNotEmpty ||
      sire.length != dam.length) {
    throw ArgumentError('Parents must specify the same audit loci');
  }
  final child = <String, List<String>>{};
  void copy(int index, int weight) {
    if (index == loci.length) {
      final label = observedFamily(child, spotting: spotting);
      counts.update(label, (n) => n + weight, ifAbsent: () => weight);
      return;
    }
    final l = loci[index], s = sire[l]!, d = dam[l]!;
    if (s.length != 2 || d.length != 2) {
      throw ArgumentError('Need two allele copies');
    }
    // Identical allele copies retain their multiplicity, without recursing
    // four identical branches. This is integer counting, not locus probabilities.
    final copies = <String, (List<String>, int)>{};
    for (var code = 0; code < 4; code++) {
      final pair = [s[code ~/ 2], d[code % 2]];
      final key = pair.join('|');
      copies.update(
        key,
        (old) => (old.$1, old.$2 + 1),
        ifAbsent: () => (pair, 1),
      );
    }
    for (final choice in copies.values) {
      child[l] = choice.$1;
      copy(index + 1, weight * choice.$2);
    }
  }

  copy(0, 1);
  final total = counts.values.reduce((a, b) => a + b);
  return {for (final e in counts.entries) e.key: e.value / total};
}
