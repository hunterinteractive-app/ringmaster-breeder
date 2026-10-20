import 'mendelian.dart';
import 'color_labels.dart';
import 'coat_groups.dart';
import 'spotted_breeds.dart';
import 'silvered_breeds.dart';
import 'breed_color_contexts.dart';

/// Species-level, conditional coat rules. These do not define breed standards.
/// Domains are ordered by dominance; C shade distinguishes homozygous sable.
const coatDomains = <String, List<String>>{
  'A': ['A', 'at', 'a'],
  'B': ['B', 'b'],
  'C': ['C', 'cchd', 'cchl', 'ch', 'c'],
  'D': ['D', 'd'],
  'E': ['Es', 'E', 'ej', 'e'],
  'En': ['En', 'en'],
  'V': ['V', 'v'],
};

class CoatInput {
  final String name;
  final Map<String, List<AllelePair>> loci;
  final String family;
  const CoatInput(this.name, this.loci, this.family);
}

List<AllelePair> allCoatPairs(String locus) {
  final domain = coatDomains[locus]!;
  return [
    for (var i = 0; i < domain.length; i++)
      for (var j = i; j < domain.length; j++) AllelePair(domain[i], domain[j]),
  ];
}

List<AllelePair> _dominant(
  String locus,
  String allele, {
  bool heterozygousOnly = false,
}) {
  final domain = coatDomains[locus]!;
  return [
    for (final second in domain.skip(domain.indexOf(allele)))
      if (!heterozygousOnly || second != allele) AllelePair(allele, second),
  ];
}

List<AllelePair> _fixed(String a, [String? b]) => [AllelePair(a, b ?? a)];

class CoatRules {
  static const catalogAliases = <String, String>{
    "american fuzzy lop|self group - black": "black",
    "american fuzzy lop|self group - blue": "blue",
    "american fuzzy lop|sable point - black": "sable point - black",
    "american fuzzy lop|sable point - blue": "sable point - blue",
    "american fuzzy lop|sable point - chocolate": "sable point - chocolate",
    "american fuzzy lop|sable point - lilac": "sable point - lilac",
    "american fuzzy lop|tan pattern group - black": "black otter",
    "american fuzzy lop|tan pattern group - blue": "blue otter",
    "american fuzzy lop|tan pattern group - chocolate": "chocolate otter",
    "american fuzzy lop|tan pattern group - lilac": "lilac otter",
    "english lop|self group - black": "black",
    "english lop|self group - blue": "blue",
    "english lop|self group - chocolate": "chocolate",
    "english lop|self group - lilac": "lilac",
    "french lop|self group - black": "black",
    "french lop|self group - blue": "blue",
    "french lop|self group - chocolate": "chocolate",
    "french lop|self group - lilac": "lilac",
    "holland lop|self - black": "black",
    "holland lop|self - blue": "blue",
    "holland lop|self - chocolate": "chocolate",
    "holland lop|self - lilac": "lilac",
    "jersey wooly|self - black": "black",
    "jersey wooly|self - blue": "blue",
    "jersey wooly|self - chocolate": "chocolate",
    "jersey wooly|self - lilac": "lilac",
    "mini lop|self group - black": "black",
    "mini lop|self group - blue": "blue",
    "mini lop|self group - chocolate": "chocolate",
    "mini lop|self group - lilac": "lilac",
  };
  static const families = [
    'Self: Black, Blue, Chocolate, Lilac',
    'Agouti: Chestnut/Castor/Gray, Chocolate Agouti, Opal, Lynx',
    'Otter: black, blue, chocolate and lilac bases',
    'Tortoise and fox: black, blue, chocolate and lilac bases',
    'Chinchilla, self chinchilla and silver marten families',
    'Sable, seal, smoke pearl and sable point families',
    'Steel / masked-steel families (shade not predicted)',
    'Himalayan / pointed white, ruby-eyed white and blue-eyed white',
    'Harlequin, magpie and tricolor families',
    'Broken and Charlie patterns with a specified underlying color',
    'Orange/red and cream/fawn families (shade and intensity not predicted)',
  ];
  static const scope =
      'Shared rabbit coat model. Colors are interpreted from the recorded variety and details, with unknown carriers left as ranges. Calculations assume the modeled genes are inherited independently. Plain self colors assume a full-color self background. Plain Tortoise, Sable and Seal use a black base unless another base is recorded. White results do not predict eye color. Exact shade, marking quality, silvering inheritance and some special breed patterns are not calculated. A separate experimental Lutino-family model applies only to a Lutino record with verified underlying color details.';
  static const modelLimits =
      'The model assumes ordinary Mendelian inheritance and independently inherited loci. Rare dominant black, masked alternative color interpretations, wideband/rufus intensity, white ear and exact markings need further rules. Colored rabbits may carry hidden white genes; white can conceal their other color genes. A recorded variety does not confirm a complete genotype.';

  static String normalize(dynamic value) => (value?.toString() ?? '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll('–', '-');

  static CoatInput? resolve(Map<String, dynamic> animal) {
    if (normalize(animal['species']) != 'rabbit') return null;
    if (animal['color_details'] != null && animal['color_details'] is! Map) {
      return null;
    }
    if (BreedColorContexts.kind(animal) != null) {
      final prepared = BreedColorContexts.prepare(animal);
      if (prepared == null) return null;
      animal = prepared;
    }
    final silvered = SilveredBreedRules.appliesTo(animal);
    if (silvered) {
      final prepared = SilveredBreedRules.prepare(animal);
      if (prepared == null) return null;
      animal = prepared;
    }
    final breed = RabbitColorLabels.breedKey(animal['breed']);
    var name = RabbitColorLabels.canonicalVariety(animal);
    final spottedBreed = SpottedBreedRules.handles(animal['breed']);
    final spotted = spottedBreed ? SpottedBreedRules.resolve(animal) : null;
    if (spottedBreed && spotted == null) return null;
    if (RabbitColorLabels.needsDedicatedBreedRules(animal['breed']) &&
        !spottedBreed &&
        !silvered) {
      return null;
    }
    name = spotted?.color ?? catalogAliases['$breed|$name'] ?? name;

    final details = animal['color_details'];
    final group = CoatGroup.fromLabel(name);
    var usedGroupColor = false;
    var pattern = spotted?.pattern ?? '';
    if (details is Map) {
      pattern = switch (spotted?.pattern ?? normalize(details['pattern'])) {
        'broken pattern' || 'broken group' => 'broken',
        'solid pattern' => 'solid',
        'tan pattern' => 'tan',
        final value => value,
      };
      if (details.entries.any(
        (e) =>
            !['color', 'base_color', 'pattern', 'eye_color'].contains(e.key) &&
            normalize(e.value).isNotEmpty,
      )) {
        return null;
      }
      final detailColor = RabbitColorLabels.canonicalVariety({
        ...animal,
        'variety': details['color'],
      });
      if (group != null && detailColor.isNotEmpty) {
        final candidate = group.colorLabel(detailColor);
        if (candidate == null) return null;
        name = candidate;
        usedGroupColor = true;
      }
      if (name == 'white') {
        final eye = normalize(details['eye_color']);
        if (['red', 'ruby', 'pink', 'ruby-eyed', 'red-eyed'].contains(eye)) {
          name = 'rew';
        }
        if (['blue', 'blue-eyed'].contains(eye)) name = 'bew';
      }
    }
    if (name == 'white' &&
        ['new zealand', 'florida white', 'american'].contains(breed)) {
      name = 'rew';
    }
    if (name == 'white' && breed == 'beveren') name = 'bew';
    if (name == 'standard' && breed == 'californian') {
      name = 'black pointed white';
    }
    if (breed == 'himalayan' &&
        ['black', 'blue', 'chocolate', 'lilac'].contains(name)) {
      name = '$name pointed white';
    }
    if (breed == 'mini rex' && name == 'castor') name = 'chestnut';
    if (breed == 'dutch' && ['gray', 'grey'].contains(name)) name = 'chestnut';
    if (breed == 'tan' &&
        ['black', 'blue', 'chocolate', 'lilac'].contains(name)) {
      name = '$name otter';
    }
    name = name
        .replaceAll('tortoise shell', 'tortoise')
        .replaceAll('tortoiseshell', 'tortoise');
    if (pattern == 'otter' &&
        ['black', 'blue', 'chocolate', 'lilac'].contains(name)) {
      name = '$name otter';
    }
    if (pattern == 'agouti' &&
        ['black', 'blue', 'chocolate', 'lilac'].contains(name)) {
      name = 'agouti - $name';
    }

    if (breed == 'silver marten' &&
        ['black', 'blue', 'chocolate', 'lilac'].contains(name)) {
      name = '$name silver marten';
    }
    var spotting = 'solid';
    for (final prefix in ['broken ', 'charlie ']) {
      if (name.startsWith(prefix)) {
        spotting = prefix.trim();
        name = name.substring(prefix.length);
        break;
      }
    }
    if (name.startsWith('tricolor ') || name.startsWith('tri-color ')) {
      spotting = 'broken';
      name = '${name.replaceFirst(RegExp(r"^tri-?color "), "")} harlequin';
    }
    if (spotting != 'solid' &&
        (pattern == 'solid' ||
            ['broken', 'charlie'].contains(pattern) && pattern != spotting)) {
      return null;
    }
    if (['broken', 'charlie'].contains(pattern)) spotting = pattern;
    // Palomino Lynx needs its own rules, including when wrapped in a group
    // or a broken/Charlie description.
    if (breed == 'palomino' && name == 'lynx') return null;
    var input = _colored(name);
    if (input == null) return null;
    if (group?.families != null && !group!.families!.contains(input.family)) {
      return null;
    }
    if (group?.kind == 'solid' && spotting != 'solid' ||
        group?.kind == 'broken' && spotting != 'broken' ||
        group?.kind == 'tricolor' && spotting != 'broken' ||
        group?.kind == 'colored' && input.family == 'white') {
      return null;
    }
    final loci = Map<String, List<AllelePair>>.from(input.loci);
    if (input.family != 'white') {
      loci['En'] = spotting == 'broken'
          ? _fixed('En', 'en')
          : spotting == 'charlie'
          ? _fixed('En')
          : _fixed('en');
    } else if (spotting != 'solid') {
      // White masks spotting; never infer its genotype from an invisible pattern.
      return null;
    }
    if (pattern.isNotEmpty &&
        ![
          'solid',
          'self',
          'agouti',
          'otter',
          'tan',
          'dutch',
          'broken',
          'charlie',
          'tortoise',
          'tort',
          'pointed white',
          'silver marten',
          'sable marten',
          'fox',
          'sable point',
          'shaded',
          'harlequin',
          'steel',
          'pearl',
          'non-extension self chinchilla',
        ].contains(pattern)) {
      return null;
    }
    final expectedFamilies = <String, List<String>>{
      'self': ['self', 'white'],
      'agouti': ['agouti', 'chinchilla', 'orange', 'frosty'],
      'otter': ['otter'],
      'tan': ['otter', 'silver marten', 'sable marten'],
      'silver marten': ['silver marten'],
      'sable marten': ['sable marten'],
      'fox': ['fox'],
      'sable point': ['sable point'],
      'shaded': const CoatGroup('shaded').families!,
      'harlequin': ['harlequin', 'japanese'],
      'steel': ['steel'],
      'pearl': ['pearl', 'non-extension self chinchilla', 'sable point'],
      'non-extension self chinchilla': ['non-extension self chinchilla'],
      'tortoise': ['tortoise', 'tort'],
      'tort': ['tortoise', 'tort'],
      'pointed white': ['pointed white', 'himalayan'],
    };
    if (expectedFamilies.containsKey(pattern) &&
        !expectedFamilies[pattern]!.contains(input.family)) {
      return null;
    }
    if (pattern == 'dutch' && breed != 'dutch') return null;
    if (details is Map) {
      final eye = normalize(details['eye_color']);
      if (input.family == 'white' && eye.isNotEmpty) {
        final red = [
          'red',
          'ruby',
          'pink',
          'ruby-eyed',
          'red-eyed',
        ].contains(eye);
        final blue = ['blue', 'blue-eyed'].contains(eye);
        if ((input.name == 'Ruby-eyed white' && !red) ||
            (input.name == 'Blue-eyed white' && !blue)) {
          return null;
        }
      }
      if (eye.isNotEmpty &&
          name != 'rew' &&
          name != 'bew' &&
          input.family != 'white') {
        return null;
      }
      final base = normalize(details['base_color']);
      final color = normalize(details['color']);
      // Resolve explicit color details independently: conflicting phenotype facts
      // block calculation rather than being ignored or replacing the record.
      for (final rawDetail in [
        base,
        if (!usedGroupColor) color,
        group?.base ?? '',
      ]) {
        final detail = SpottedBreedRules.colorDetailLabel(
          animal['breed'],
          RabbitColorLabels.canonicalVariety({...animal, 'variety': rawDetail}),
        );
        if (detail.isEmpty ||
            detail == name ||
            rawDetail == normalize(animal['variety']) ||
            detail == RabbitColorLabels.canonicalVariety(animal)) {
          continue;
        }
        if (input.family == 'white' && detail == 'white') continue;
        if (input.family == 'white') return null;
        final other = _colored(detail);
        if (other == null) return null;
        final compared =
            ['black', 'blue', 'chocolate', 'lilac'].contains(detail)
            ? ['B', 'D']
            : ['A', 'B', 'C', 'D', 'E'];
        for (final locus in compared) {
          final keys = other.loci[locus]!.map((p) => p.key).toSet();
          loci[locus] = loci[locus]!
              .where((p) => keys.contains(p.key))
              .toList();
          if (loci[locus]!.isEmpty) return null;
        }
      }
    }
    // A Dutch breed/color label or its Dutch marking annotation does not
    // establish English spotting. The Dutch predictor excludes En outcomes.
    if (breed == 'dutch' && spotting == 'solid') {
      loci['En'] = allCoatPairs('En');
    }
    if (spotted != null) loci['En'] = spotted.spotting;
    return CoatInput(input.name, loci, input.family);
  }

  static String? detailInterpretationNote(Map<String, dynamic> animal) {
    final group = CoatGroup.fromLabel(
      RabbitColorLabels.canonicalVariety(animal),
    );
    final details = animal['color_details'];
    if (group == null || details is! Map || resolve(animal) == null) {
      return null;
    }
    final color = details['color']?.toString().trim() ?? '';
    if (color.isEmpty) return null;
    return '${animal['breed']}: ${animal['variety']} uses the saved color details ($color)';
  }

  static CoatInput? _colored(String raw) {
    final name = raw;
    final all = {
      for (final locus in coatDomains.keys) locus: allCoatPairs(locus),
    };
    if ([
      'rew',
      'ruby-eyed white',
      'ruby eyed white',
      'red-eyed white',
      'red eyed white',
      'albino',
    ].contains(name)) {
      return CoatInput('Ruby-eyed white', {...all, 'C': _fixed('c')}, 'white');
    }
    if (['bew', 'blue-eyed white', 'blue eyed white'].contains(name)) {
      return CoatInput('Blue-eyed white', {
        ...all,
        // Albino cc masks Vienna too and produces ruby-eyed white, so it
        // cannot describe a recorded blue-eyed white parent. Other hidden
        // color genes, including a single c allele, remain unresolved.
        'C': allCoatPairs('C').where((p) => !p.isRecessive('c')).toList(),
        'V': _fixed('v'),
      }, 'white');
    }
    const bases = ['black', 'blue', 'chocolate', 'lilac'];
    String? base;
    var family = 'self';
    var a = 'a', c = 'C', e = 'E';
    var shadeHeterozygous = false;
    var unknownB = false, unknownD = false;
    if (bases.contains(name)) {
      base = name;
    } else if ([
      'chestnut',
      'chestnut agouti',
      'castor',
      'copper',
      'agouti - black',
    ].contains(name)) {
      base = 'black';
      a = 'A';
      family = 'agouti';
    } else if ([
      'chocolate agouti',
      'cinnamon',
      'amber',
      'agouti - chocolate',
    ].contains(name)) {
      base = 'chocolate';
      a = 'A';
      family = 'agouti';
    } else if (['opal', 'agouti - blue'].contains(name)) {
      base = 'blue';
      a = 'A';
      family = 'agouti';
    } else if (['lynx', 'agouti - lilac'].contains(name)) {
      base = 'lilac';
      a = 'A';
      family = 'agouti';
    } else if (['chinchilla', 'black chinchilla'].contains(name)) {
      base = 'black';
      a = 'A';
      c = 'cchd';
      family = 'chinchilla';
    } else if (['squirrel', 'blue chinchilla'].contains(name)) {
      base = 'blue';
      a = 'A';
      c = 'cchd';
      family = 'chinchilla';
    } else if ([
      'orange',
      'red',
      'gold',
      'golden',
      'golden yellow',
    ].contains(name)) {
      base = 'black';
      a = 'A';
      e = 'e';
      unknownB = true;
      family = 'orange';
    } else if (['cream', 'fawn (nd)', 'fawn(nd)'].contains(name)) {
      base = 'blue';
      a = 'A';
      e = 'e';
      unknownB = true;
      family = 'orange';
    } else if (['frosty', 'ermine', 'frosted pearl'].contains(name)) {
      base = 'black';
      a = 'A';
      c = 'cchd';
      e = 'e';
      unknownB = true;
      family = 'frosty';
    } else {
      // Named bases are explicit. Group names below retain unknown B/D
      // instead of assigning an unrecorded black base.
      final matches = <String, (String, String, String, bool)>{
        'otter': ('at', 'C', 'E', false),
        'tortoise': ('a', 'C', 'e', false),
        'tort': ('a', 'C', 'e', false),
        'fox': ('at', 'C', 'e', false),
        'chinchilla': ('A', 'cchd', 'E', false),
        'self chinchilla': ('a', 'cchd', 'E', false),
        'silver marten': ('at', 'cchd', 'E', false),
        'sable': ('a', 'cchl', 'E', true),
        'siamese sable': ('a', 'cchl', 'E', true),
        'seal': ('a', 'cchl', 'E', false),
        'sable point': ('a', 'cchl', 'e', false),
        'sable agouti': ('A', 'cchl', 'E', false),
        'sable marten': ('at', 'cchl', 'E', false),
        'pointed white': ('a', 'ch', 'E', false),
        'himalayan': ('a', 'ch', 'E', false),
        'harlequin': ('A', 'C', 'ej', false),
        'japanese': ('A', 'C', 'ej', false),
        'magpie': ('A', 'cchd', 'ej', false),
        'steel': ('A', 'C', 'Es', false),
        'silver-tipped steel': ('A', 'cchd', 'Es', false),
        'pearl': ('a', 'cchd', 'e', false),
        'non-extension self chinchilla': ('a', 'cchd', 'e', false),
      };
      for (final entry in matches.entries) {
        for (final b in bases) {
          if (name == '$b ${entry.key}' ||
              name == '${entry.key} - $b' ||
              name == '${entry.key} ($b)') {
            base = b;
            a = entry.value.$1;
            c = entry.value.$2;
            e = entry.value.$3;
            shadeHeterozygous = entry.value.$4;
            family = entry.key;
          }
        }
      }
      if ([
        'tortoise',
        'tortoiseshell',
        'tortoise shell',
        'tort',
      ].contains(name)) {
        base = 'black';
        e = 'e';
        family = 'tortoise';
      }
      if (['siamese sable', 'sable'].contains(name)) {
        base = 'black';
        c = 'cchl';
        shadeHeterozygous = true;
        family = 'sable';
      }
      if (name == 'seal') {
        base = 'black';
        c = 'cchl';
        family = 'seal';
      }
      if (name == 'sable point') {
        base = 'black';
        c = 'cchl';
        e = 'e';
        shadeHeterozygous = true;
        family = 'sable point';
        shadeHeterozygous = false;
      }
      if (['smoke pearl', 'siamese smoke pearl'].contains(name)) {
        base = 'blue';
        c = 'cchl';
        shadeHeterozygous = true;
        family = 'sable';
      }
      if (name == 'smoke pearl marten') {
        base = 'blue';
        a = 'at';
        c = 'cchl';
        shadeHeterozygous = true;
        family = 'sable marten';
      }
    }
    if ([
      'pointed white',
      'himalayan',
      'otter',
      'fox',
      'silver marten',
      'sable marten',
      'tans',
      'japanese',
      'magpie',
      'steel',
      'fawn',
    ].contains(name)) {
      base = 'black';
      unknownB = true;
      unknownD = true;
      switch (name) {
        case 'otter' || 'tans':
          a = 'at';
          family = 'otter';
        case 'fox':
          a = 'at';
          e = 'e';
          family = 'fox';
        case 'silver marten':
          a = 'at';
          c = 'cchd';
          family = 'silver marten';
        case 'sable marten':
          a = 'at';
          c = 'cchl';
          shadeHeterozygous = true;
          family = 'sable marten';
          shadeHeterozygous = false;
        case 'pointed white' || 'himalayan':
          c = 'ch';
          family = 'pointed white';
        case 'japanese':
          e = 'ej';
          family = 'harlequin';
        case 'magpie':
          c = 'cchd';
          e = 'ej';
          family = 'magpie';
        case 'steel':
          a = 'A';
          e = 'Es';
          family = 'steel';
        case 'fawn':
          a = 'A';
          e = 'e';
          family = 'orange';
      }
    }
    if (name == 'frosty' || name == 'ermine' || name == 'frosted pearl') {
      unknownD = true;
    }
    if (base == null) return null;
    final chocolate = ['chocolate', 'lilac'].contains(base),
        dilute = ['blue', 'lilac'].contains(base);
    final loci = <String, List<AllelePair>>{
      'A': a == 'a' ? _fixed('a') : _dominant('A', a),
      'B': unknownB
          ? allCoatPairs('B')
          : chocolate
          ? _fixed('b')
          : _dominant('B', 'B'),
      'C': family == 'seal'
          ? _fixed('cchl')
          : _dominant('C', c, heterozygousOnly: shadeHeterozygous),
      'D': unknownD
          ? allCoatPairs('D')
          : dilute
          ? _fixed('d')
          : _dominant('D', 'D'),
      'E': _dominant('E', e),
      'En': _fixed('en'),
      'V': _dominant('V', 'V'),
    };
    if (family == 'pearl') {
      // Both documented Pearl backgrounds share aa/ee. Their C alternatives
      // remain a union of actual pairs, never an averaged genotype or prior.
      loci['C'] = [..._dominant('C', 'cchd'), ..._dominant('C', 'cchl')];
    }
    if (family == 'silver-tipped steel') {
      // This named conditional context follows the reviewed Es/E definition.
      // Offspring Es/Es or Es/lower remain in the broad masked-steel family.
      loci['E'] = _fixed('Es', 'E');
      family = 'steel';
    }
    // Pointed white and harlequin can mask A/E. Keep those loci unconstrained
    // within the supported model rather than claiming self or agouti evidence.
    if (c == 'ch') {
      loci['A'] = allCoatPairs('A');
      loci['E'] = allCoatPairs('E');
    }
    if (a == 'a' && e == 'E' && c != 'ch') {
      loci['E'] = [..._dominant('E', 'Es'), ..._dominant('E', 'E')];
    }
    if (e == 'ej') loci['A'] = allCoatPairs('A');
    return CoatInput(name, loci, family);
  }
}

class CoatOutcome {
  final String label, base;
  final bool tortoise, broken, white;
  const CoatOutcome(
    this.label,
    this.base, {
    this.tortoise = false,
    this.broken = false,
    this.white = false,
  });
}
