import 'mendelian.dart';
import 'coat_rules.dart';
import 'coat_groups.dart';
import 'coat_solver.dart';
import 'color_labels.dart';
import 'spotted_breeds.dart';
import 'silvered_breeds.dart';
import 'breed_color_contexts.dart';
import 'lutino_prediction.dart';
import 'hotot_colors.dart';
import 'saved_genotype_constraints.dart';

enum BaseCoatColor {
  black('Black'),
  blue('Blue'),
  chocolate('Chocolate'),
  lilac('Lilac');

  final String label;
  const BaseCoatColor(this.label);
  bool get chocolateBased => this == chocolate || this == lilac;
  bool get dilute => this == blue || this == lilac;
}

enum CarrierKnowledge { unknown, yes, no }

class ColorCarrierDetails {
  final CarrierKnowledge chocolate, dilute, tortoise;
  final CarrierKnowledge albino, vienna, selfPattern, harlequin;
  const ColorCarrierDetails({
    this.chocolate = CarrierKnowledge.unknown,
    this.dilute = CarrierKnowledge.unknown,
    this.tortoise = CarrierKnowledge.unknown,
    this.albino = CarrierKnowledge.unknown,
    this.vienna = CarrierKnowledge.unknown,
    this.selfPattern = CarrierKnowledge.unknown,
    this.harlequin = CarrierKnowledge.unknown,
  });
  ColorCarrierDetails copyWith({
    CarrierKnowledge? chocolate,
    CarrierKnowledge? dilute,
    CarrierKnowledge? tortoise,
    CarrierKnowledge? albino,
    CarrierKnowledge? vienna,
    CarrierKnowledge? selfPattern,
    CarrierKnowledge? harlequin,
  }) => ColorCarrierDetails(
    chocolate: chocolate ?? this.chocolate,
    dilute: dilute ?? this.dilute,
    tortoise: tortoise ?? this.tortoise,
    albino: albino ?? this.albino,
    vienna: vienna ?? this.vienna,
    selfPattern: selfPattern ?? this.selfPattern,
    harlequin: harlequin ?? this.harlequin,
  );
}

class ColorPhenotype {
  final BaseCoatColor base;
  final bool tortoise;
  const ColorPhenotype(this.base, {this.tortoise = false});
}

class ColorChanceRange {
  final BaseCoatColor color;
  final double minimum, maximum;
  final bool tortoise;
  final String? displayLabel, swatch;
  final bool broken;
  final bool isColorFamily;
  const ColorChanceRange(
    this.color,
    this.minimum,
    this.maximum, {
    this.tortoise = false,
    this.displayLabel,
    this.swatch,
    this.broken = false,
    this.isColorFamily = false,
  });
  bool get isExact => (maximum - minimum).abs() < 1e-10;
  String get label =>
      displayLabel ??
      (tortoise ? 'Tortoise (${color.label.toLowerCase()} base)' : color.label);
}

class MarkingChanceRange {
  final String label;
  final double minimum, maximum;
  const MarkingChanceRange(this.label, this.minimum, this.maximum);
}

class ColorPrediction {
  final List<ColorChanceRange> colors;
  final int scenarioCount;
  final String title, scope;
  final List<MarkingChanceRange> markings;
  final String? limitation, limitationTitle;
  final List<String> parentInterpretations, unresolvedInformation;
  const ColorPrediction(
    this.colors,
    this.scenarioCount, {
    required this.title,
    required this.scope,
    this.markings = const [],
    this.limitation,
    this.limitationTitle,
    this.parentInterpretations = const [],
    this.unresolvedInformation = const [],
  });
  bool get hasRanges => colors.any((c) => !c.isExact);
}

String _normalized(dynamic value) =>
    value?.toString().trim().toLowerCase() ?? '';

/// Explicitly reviewed input coverage. Recognition for showing is a separate
/// question: output colors must never be filtered out by a breed standard.
class RabbitColorProfile {
  final String breed;
  final List<String> aliases;
  final List<BaseCoatColor> solidColors;
  final bool modelsTortoise;
  final bool tanPattern;
  final bool shared;
  final bool eyebandOnly;
  const RabbitColorProfile(
    this.breed, {
    this.aliases = const [],
    this.solidColors = BaseCoatColor.values,
    this.modelsTortoise = false,
    this.tanPattern = false,
    this.shared = false,
    this.eyebandOnly = false,
  });

  String get supportedInputs => [
    ...solidColors.map((c) => c.label),
    if (modelsTortoise) 'Tortoise (black, blue, chocolate or lilac base)',
  ].join(', ');
  String get resultTitle => eyebandOnly
      ? '$breed eye-band pigment estimates'
      : '$breed ${modelsTortoise ? 'color' : 'base-color'} estimates';
  String get scope {
    if (eyebandOnly) return HototColorRules.scopeFor(breed);
    if (shared && tanPattern) {
      return 'Tan coat model: a plain Black, Blue, Chocolate or Lilac variety is interpreted as the corresponding full-color tan-pattern family. Hidden self, shaded, white and extension carriers remain unknown where the recorded color does not identify them. $tanModelLimits ${CoatRules.scope}';
    }
    if (dutchColorOnly) {
      return 'Dutch underlying-color model. Plain self colors and Tortoise use their conditional recorded-color backgrounds; Gray uses chestnut/agouti. Compatible hidden shaded, white and extension genes stay unknown. $dutchModelLimits ${CoatRules.scope}';
    }
    if (shared) return '$breed coat model. ${CoatRules.scope}';
    if (tanPattern) {
      return 'Tan base-color model: Black, Blue, Chocolate, and Lilac. It assumes the offspring have Tan markings, full color, and normal dark-pigment extension. Other patterns, hidden genes outside this model, and the depth of tan markings are not calculated yet.';
    }
    if (modelsTortoise) {
      return 'Dutch color model: Black, Blue, Chocolate, Lilac and their tortoise versions. It assumes a self-patterned color background and full color. Dutch white marking placement and quality, gray/agouti, steel, chinchilla, golden yellow and other hidden genes are not calculated yet. A plain Tortoise record is interpreted as black-based Tortoise.';
    }
    return '$breed base-color model. Supported parent varieties: $supportedInputs. It assumes self-colored, full-color coats with normal dark-pigment extension. White, broken, shaded, other patterns and hidden genes outside the model are not calculated yet.';
  }

  bool get dutchColorOnly => shared && breed == 'Dutch';
  static const dutchModelLimits =
      'These estimates describe underlying color families only. Dutch white markings, their amount and placement, blaze, cheeks, saddle, stops, other spotting and show quality are not predicted. A 100% color-family result does not guarantee a correctly marked Dutch kit. No Dutch marking genotype is inferred.';

  static const tanModelLimits =
      'The depth of red/tan markings, rufus/wideband modifiers, exact markings and show quality are not predicted. Possible hidden-gene outcomes do not mean those genes are known to be present or common in this herd.';

  bool matchesBreed(dynamic value) => eyebandOnly
      ? HototColorRules.breedKey(breed) == HototColorRules.breedKey(value)
      : [breed, ...aliases].any((b) => _normalized(b) == _normalized(value));

  ColorPhenotype? phenotypeOf(Map<String, dynamic> animal) {
    final variety = eyebandOnly
        ? HototColorRules.baseColorOf(animal)
        : RabbitColorLabels.canonicalVariety(animal);
    for (final color in solidColors) {
      if (variety == color.label.toLowerCase()) return ColorPhenotype(color);
    }
    if (!modelsTortoise) return null;
    final base = _tortoiseAliases[variety];
    return base == null ? null : ColorPhenotype(base, tortoise: true);
  }

  String? inputIssue(Map<String, dynamic> animal) {
    if (animal['color_details'] != null && animal['color_details'] is! Map) {
      return 'A selected rabbit’s Additional color details could not be read. Check the saved details or contact support before calculating.';
    }
    if (shared) {
      return CoatRules.resolve(animal) == null
          ? RabbitColorPredictions.unresolvedIssue(animal)
          : null;
    }
    if (_normalized(animal['species']) != 'rabbit' ||
        !matchesBreed(animal['breed'])) {
      return 'Choose two rabbits of the same supported breed. Mixed-breed predictions are not available yet.';
    }
    if (eyebandOnly) return HototColorRules.inputIssue(animal);
    final phenotype = phenotypeOf(animal);
    if (phenotype == null) {
      return '$breed predictions currently accept these recorded varieties: $supportedInputs. Missing varieties, white and other patterns need additional rules before an estimate can be shown.';
    }
    final details = animal['color_details'];
    if (details is Map) {
      for (final entry in details.entries) {
        final value = _normalized(entry.value);
        if (value.isEmpty) continue;
        if (entry.key == 'base_color' &&
            value == phenotype.base.label.toLowerCase()) {
          continue;
        }
        if (entry.key == 'color' &&
            [
              phenotype.base.label.toLowerCase(),
              _normalized(animal['variety']),
              RabbitColorLabels.canonicalVariety(animal),
            ].contains(value)) {
          continue;
        }
        if (entry.key == 'pattern' &&
            ((tanPattern && value == 'tan') ||
                (modelsTortoise && value == 'dutch') ||
                (!tanPattern &&
                    !modelsTortoise &&
                    ['self', 'solid'].contains(value)) ||
                (modelsTortoise &&
                    phenotype.tortoise &&
                    ['tortoise', 'tort'].contains(value)))) {
          continue;
        }
        return 'A selected rabbit has additional color or pattern details that this calculator cannot use yet. No estimate is shown for that combination.';
      }
    }
    return null;
  }

  static const _tortoiseAliases = <String, BaseCoatColor>{
    'tortoise': BaseCoatColor.black,
    'tort': BaseCoatColor.black,
    'tortoiseshell': BaseCoatColor.black,
    'tortoise shell': BaseCoatColor.black,
    'black tortoise': BaseCoatColor.black,
    'black tort': BaseCoatColor.black,
    'tort. - black': BaseCoatColor.black,
    'blue tortoise': BaseCoatColor.blue,
    'blue tort': BaseCoatColor.blue,
    'tort. - blue': BaseCoatColor.blue,
    'chocolate tortoise': BaseCoatColor.chocolate,
    'chocolate tort': BaseCoatColor.chocolate,
    'tort. - choc.': BaseCoatColor.chocolate,
    'lilac tortoise': BaseCoatColor.lilac,
    'lilac tort': BaseCoatColor.lilac,
    'tort. - lilac': BaseCoatColor.lilac,
  };
}

class RabbitColorPredictions {
  static const profiles = <RabbitColorProfile>[
    RabbitColorProfile(
      'Beveren',
      solidColors: [BaseCoatColor.black, BaseCoatColor.blue],
      shared: true,
    ),
    RabbitColorProfile('Dutch', modelsTortoise: true, shared: true),
    RabbitColorProfile('Havana', aliases: ['Havanna'], shared: true),
    RabbitColorProfile(
      'Lilac',
      solidColors: [BaseCoatColor.lilac],
      shared: true,
    ),
    RabbitColorProfile('Polish', shared: true),
    RabbitColorProfile('Tan', tanPattern: true, shared: true),
    RabbitColorProfile('Dwarf Hotot', eyebandOnly: true),
    RabbitColorProfile('Blanc de Hotot', eyebandOnly: true),
  ];

  static RabbitColorProfile? profileFor(Map<String, dynamic> animal) {
    if (_normalized(animal['species']) != 'rabbit' ||
        _normalized(animal['breed']).isEmpty) {
      return null;
    }
    return profiles.where((p) => p.matchesBreed(animal['breed'])).firstOrNull ??
        RabbitColorProfile(animal['breed'].toString().trim(), shared: true);
  }

  static bool _usesLegacy(Map<String, dynamic> sire, Map<String, dynamic> dam) {
    final profile = profileFor(sire);
    return profile != null &&
        !profile.shared &&
        profile.matchesBreed(dam['breed']) &&
        profile.inputIssue(sire) == null &&
        profile.inputIssue(dam) == null;
  }

  static String unresolvedIssue(Map<String, dynamic> animal) {
    final breed = animal['breed']?.toString().trim() ?? '';
    final variety = animal['variety']?.toString().trim() ?? '';
    if (animal['color_details'] != null && animal['color_details'] is! Map) {
      return '$breed — $variety: Additional color details could not be read. Check the saved details or contact support before calculating.';
    }
    if (HototColorRules.handles(animal['breed'])) {
      return HototColorRules.inputIssue(animal) ??
          'This pairing needs two compatible Hotot eye-band pigment records.';
    }
    final contextIssue = BreedColorContexts.unresolvedIssue(animal);
    if (contextIssue != null) return contextIssue;
    if (SilveredBreedRules.appliesTo(animal)) {
      return SilveredBreedRules.unresolvedIssue(animal) ??
          '$breed — $variety has missing, conflicting or unsupported underlying color details. Silvering itself cannot identify the base color genes.';
    }
    final spottedIssue = SpottedBreedRules.unresolvedIssue(animal);
    if (spottedIssue != null) return spottedIssue;
    if (variety.isEmpty) {
      return 'A selected rabbit needs a recorded variety before its colors can be estimated.';
    }
    final group = CoatGroup.fromLabel(
      RabbitColorLabels.canonicalVariety(animal),
    );
    if (['broken', 'tricolor'].contains(group?.kind)) {
      return '$breed — $variety needs its underlying color in Color details. A pattern name alone does not identify the color genes.';
    }
    if (CoatRules.normalize(variety) == 'white') {
      return '$breed — White needs a clear ruby-eyed or blue-eyed white identification. White can hide the color genes underneath.';
    }
    if (group != null) {
      return '$breed — $variety is a color group. Enter a specific color in Additional color details. The color, pattern and base color must agree; if you are unsure, contact support for help.';
    }
    return '$breed — $variety needs additional color or breed-specific rules, or has conflicting color details. No estimate is shown for this record yet.';
  }

  static String? inputIssue(
    Map<String, dynamic> sire,
    Map<String, dynamic> dam,
  ) {
    final profile = profileFor(sire);
    if (profile == null || profileFor(dam) == null) {
      return 'Choose two rabbits with a recorded breed and variety.';
    }
    if (!profile.matchesBreed(dam['breed'])) {
      return 'Choose two rabbits of the same breed. Mixed-breed predictions are not available yet.';
    }
    final legacy = _usesLegacy(sire, dam);
    if (profile.eyebandOnly) {
      final issue = profile.inputIssue(sire) ?? profile.inputIssue(dam);
      if (issue != null) return issue;
    } else if (!legacy) {
      if (CoatRules.resolve(sire) == null) return unresolvedIssue(sire);
      if (CoatRules.resolve(dam) == null) return unresolvedIssue(dam);
    }
    for (final (role, animal) in [('Buck', sire), ('Doe', dam)]) {
      try {
        final saved = SavedGenotypeConstraints.read(animal);
        if (legacy) {
          if (_genotypes(
            profile.phenotypeOf(animal)!,
            const ColorCarrierDetails(),
            profile.modelsTortoise,
            saved,
          ).isEmpty) {
            return '$role: the saved genotype conflicts with the recorded base color. Review the genotype or contact support@ringmasterone.com for help.';
          }
        } else {
          saved?.apply(CoatRules.resolve(animal)!);
        }
      } on FormatException catch (e) {
        return '$role: ${e.message}';
      }
    }
    return null;
  }

  static String scopeFor(Map<String, dynamic> sire, Map<String, dynamic> dam) {
    final modelScope = _usesLegacy(sire, dam)
        ? profileFor(sire)!.scope
        : profileFor(sire)?.shared == true
        ? profileFor(sire)!.scope
        : CoatRules.scope;
    final notes = [
      RabbitColorLabels.interpretationNote(sire),
      HototColorRules.interpretationNote(sire),
      SpottedBreedRules.interpretationNote(sire),
      SilveredBreedRules.interpretationNote(sire),
      BreedColorContexts.interpretationNote(sire),
      CoatRules.detailInterpretationNote(sire),
      RabbitColorLabels.interpretationNote(dam),
      HototColorRules.interpretationNote(dam),
      SpottedBreedRules.interpretationNote(dam),
      SilveredBreedRules.interpretationNote(dam),
      BreedColorContexts.interpretationNote(dam),
      CoatRules.detailInterpretationNote(dam),
    ].whereType<String>().toSet();
    final familyLimit = SpottedBreedRules.familyLimitationFor(sire, dam);
    if (familyLimit != null) notes.add(familyLimit);
    final contextLimit = BreedColorContexts.limitationFor(sire, dam);
    if (contextLimit != null) notes.add(contextLimit);
    final scope = SpottedBreedRules.handles(sire['breed'])
        ? '${SpottedBreedRules.scope} $modelScope'
        : (SilveredBreedRules.appliesTo(sire) ||
              SilveredBreedRules.appliesTo(dam))
        ? '${SilveredBreedRules.scope} $modelScope'
        : modelScope;
    return notes.isEmpty ? scope : '${notes.join('; ')}. $scope';
  }

  /// Only show carrier questions when the phenotype establishes the dominant
  /// appearance and leaves the recessive allele unresolved at that locus.
  static Set<String> carrierLoci(Map<String, dynamic> animal) {
    final profile = profileFor(animal);
    if (profile == null) return {};
    if (!profile.shared && profile.inputIssue(animal) == null) {
      final p = profile.phenotypeOf(animal)!;
      return {
        if (!p.base.chocolateBased) 'B',
        if (!p.base.dilute) 'D',
        if (profile.modelsTortoise && !p.tortoise) 'E',
      };
    }
    final original = CoatRules.resolve(animal);
    if (original == null) return {};
    final CoatInput input;
    try {
      input = SavedGenotypeConstraints.read(animal)?.apply(original) ?? original;
    } on FormatException {
      return {};
    }
    bool unresolved(String locus, String allele) {
      final pairs = input.loci[locus]!;
      return pairs.every((p) => !p.isRecessive(allele)) &&
          pairs.any((p) => p.first == allele || p.second == allele) &&
          pairs.any((p) => p.first != allele && p.second != allele);
    }

    return {
      if (unresolved('B', 'b')) 'B',
      if (unresolved('D', 'd')) 'D',
      if (unresolved('E', 'e')) 'E',
      if (unresolved('C', 'c')) 'c',
      if (unresolved('V', 'v')) 'v',
      if (unresolved('A', 'a')) 'a',
      if (unresolved('E', 'ej')) 'ej',
    };
  }

  static CoatInput _withCarriers(
    CoatInput input,
    ColorCarrierDetails carriers,
  ) {
    final loci = Map<String, List<AllelePair>>.from(input.loci);
    for (final (locus, allele, knowledge) in [
      ('B', 'b', carriers.chocolate),
      ('D', 'd', carriers.dilute),
      ('E', 'e', carriers.tortoise),
      ('C', 'c', carriers.albino),
      ('V', 'v', carriers.vienna),
      ('A', 'a', carriers.selfPattern),
      ('E', 'ej', carriers.harlequin),
    ]) {
      if (knowledge == CarrierKnowledge.unknown) continue;
      // A recessive phenotype already fixes the locus; a carrier question is
      // inapplicable and must not erase that observed phenotype.
      if (loci[locus]!.every((p) => p.isRecessive(allele))) continue;
      loci[locus] = loci[locus]!.where((p) {
        final contains = p.first == allele || p.second == allele;
        return knowledge == CarrierKnowledge.yes
            ? contains && !p.isRecessive(allele)
            : !contains;
      }).toList();
    }
    return CoatInput(input.name, loci, input.family);
  }

  /// Cross-check temporary carrier facts before enabling the calculator. Two
  /// separately plausible E-series carrier claims can be impossible together.
  static String? carrierIssue(
    Map<String, dynamic> sire,
    Map<String, dynamic> dam, {
    ColorCarrierDetails sireCarriers = const ColorCarrierDetails(),
    ColorCarrierDetails damCarriers = const ColorCarrierDetails(),
  }) {
    if (inputIssue(sire, dam) != null) return null;
    for (final (role, animal, carriers) in [
      ('Buck', sire, sireCarriers),
      ('Doe', dam, damCarriers),
    ]) {
      if (_usesLegacy(sire, dam)) {
        final profile = profileFor(animal)!;
        if (_genotypes(
          profile.phenotypeOf(animal)!,
          carriers,
          profile.modelsTortoise,
          SavedGenotypeConstraints.read(animal),
        ).isEmpty) {
          return '$role: carrier choices conflict with the saved genotype. Leave them Unknown or review the saved entry. Contact support@ringmasterone.com for help.';
        }
        continue;
      }
      final original = CoatRules.resolve(animal)!;
      final constrained =
          SavedGenotypeConstraints.read(animal)?.apply(original) ?? original;
      final input = _withCarriers(constrained, carriers);
      if (input.loci.values.any((pairs) => pairs.isEmpty)) {
        return '$role: the selected known carrier information conflicts with the modeled color or another carrier choice. Review these temporary choices or leave them Unknown. Contact support@ringmasterone.com for help.';
      }
    }
    return null;
  }

  static List<String> _unknownInformation(
    CoatInput sire,
    CoatInput dam, {
    required bool dutch,
  }) => [
    for (final (role, input) in [('Buck', sire), ('Doe', dam)])
      if (input.loci.entries.any(
        (e) => (!dutch || e.key != 'En') && e.value.length > 1,
      ))
        '$role: ${[
          for (final e in const {'A': 'pattern genes', 'B': 'black/chocolate genes', 'C': 'shading and albino-white genes', 'D': 'dilution genes', 'E': 'extension and Harlequin genes', 'V': 'Vienna-white genes', 'En': 'spotting genes'}.entries)
            if ((!dutch || e.key != 'En') && input.loci[e.key]!.length > 1) e.value,
        ].join(', ')} remain unknown.',
  ];

  static String _interpretation(
    String role,
    Map<String, dynamic> animal,
    CoatInput input,
  ) =>
      '$role: ${animal['breed']} — ${animal['variety']}; modeled as ${input.name}.'
      '${SavedGenotypeConstraints.read(animal)?.note(role) == null ? '' : ' ${SavedGenotypeConstraints.read(animal)!.note(role)}'}';

  static List<MarkingChanceRange> _markings(CoatInput sire, CoatInput dam) {
    final distributions = [
      for (final s in sire.loci['En']!)
        for (final d in dam.loci['En']!) inheritLocus(s, d),
    ];
    return [
      for (final state in const {
        'solid': 'Unspotted',
        'broken': 'Spotted',
        'charlie': 'Minimal marking (Charlie)',
      }.entries)
        (() {
          final chances = [
            for (final distribution in distributions)
              distribution
                  .where((c) => coatClass('En', c.genotype) == state.key)
                  .fold(0.0, (sum, c) => sum + c.probability),
          ]..sort();
          return MarkingChanceRange(state.value, chances.first, chances.last);
        })(),
    ];
  }

  /// No prior probabilities are invented for unknown genotypes. Each compatible
  /// parental scenario is calculated separately, and its extrema are reported.
  /// Shared profiles retain every supported unresolved locus; restricted profiles
  /// use only their explicitly documented B/D or B/D/E assumptions.
  static ColorPrediction predict({
    required Map<String, dynamic> sire,
    required Map<String, dynamic> dam,
    ColorCarrierDetails sireCarriers = const ColorCarrierDetails(),
    ColorCarrierDetails damCarriers = const ColorCarrierDetails(),
  }) {
    final issue =
        inputIssue(sire, dam) ??
        carrierIssue(
          sire,
          dam,
          sireCarriers: sireCarriers,
          damCarriers: damCarriers,
        );
    if (issue != null) throw ArgumentError(issue);
    if (!_usesLegacy(sire, dam)) {
      final sireInput = CoatRules.resolve(sire)!,
          damInput = CoatRules.resolve(dam)!;
      final s = _withCarriers(
        SavedGenotypeConstraints.read(sire)?.apply(sireInput) ?? sireInput,
        sireCarriers,
      );
      final d = _withCarriers(
        SavedGenotypeConstraints.read(dam)?.apply(damInput) ?? damInput,
        damCarriers,
      );
      final dutch = profileFor(sire)!.dutchColorOnly;
      final coats = solveCoats(s, d, includeSpotting: !dutch);
      final lutino =
          LutinoPredictions.applies(sire) || LutinoPredictions.applies(dam);
      final result = lutino
          ? LutinoPredictions.apply(
              coats,
              LutinoPredictions.applies(sire)
                  ? LutinoPredictions.affected
                  : LutinoPredictions.unknown,
              LutinoPredictions.applies(dam)
                  ? LutinoPredictions.affected
                  : LutinoPredictions.unknown,
            )
          : coats;
      final spotted = SpottedBreedRules.handles(sire['breed']);
      final silvered =
          (SilveredBreedRules.appliesTo(sire) ||
          SilveredBreedRules.appliesTo(dam));
      final limitations = <String?>[
        if (silvered) SilveredBreedRules.limitation,
        if (dutch) RabbitColorProfile.dutchModelLimits,
        BreedColorContexts.limitationFor(sire, dam),
        SpottedBreedRules.familyLimitationFor(sire, dam),
        if (profileFor(sire)?.tanPattern == true)
          RabbitColorProfile.tanModelLimits,
      ].whereType<String>().toSet();
      return ColorPrediction(
        [
          for (final c in result.colors)
            ColorChanceRange(
              BaseCoatColor.values
                      .where((b) => b.name == c.outcome.base)
                      .firstOrNull ??
                  BaseCoatColor.black,
              c.minimum,
              c.maximum,
              displayLabel: spotted
                  ? SpottedBreedRules.outcomeLabel(
                      c.outcome.label,
                      white: c.outcome.white,
                      breed: sire['breed'],
                    )
                  : silvered
                  ? SilveredBreedRules.outcomeLabel(c.outcome.label)
                  : BreedColorContexts.outcomeLabel(c.outcome.label, sire, dam),
              swatch: c.outcome.base,
              tortoise: c.outcome.tortoise,
              broken: c.outcome.broken,
              isColorFamily:
                  !const [
                    'Black',
                    'Blue',
                    'Chocolate',
                    'Lilac',
                  ].contains(c.outcome.label) ||
                  silvered,
            ),
        ],
        result.scenarioCount,
        parentInterpretations: [
          _interpretation('Buck', sire, s),
          _interpretation('Doe', dam, d),
        ],
        unresolvedInformation: [
          ..._unknownInformation(s, d, dutch: dutch),
          if (lutino &&
              (!LutinoPredictions.applies(sire) ||
                  !LutinoPredictions.applies(dam)))
            'The other parent’s experimental Lutino-factor status remains unknown.',
        ],
        title: lutino
            ? '${profileFor(sire)!.breed} experimental Lutino-family estimates'
            : silvered
            ? '${profileFor(sire)!.breed} underlying-color estimates'
            : dutch
            ? 'Dutch underlying-color estimates'
            : '${profileFor(sire)!.breed} coat-color estimates',
        markings: spotted ? _markings(s, d) : const [],
        limitation: limitations.isEmpty ? null : limitations.join(' '),
        limitationTitle: lutino
            ? 'Experimental Lutino-family model'
            : silvered
            ? 'Silvering is not predicted'
            : dutch
            ? 'Dutch markings are not predicted'
            : 'Color-family estimates only',
        scope: scopeFor(sire, dam),
      );
    }
    return _predictBaseColors(
      profile: profileFor(sire)!,
      sire: sire,
      dam: dam,
      sireCarriers: sireCarriers,
      damCarriers: damCarriers,
      scope: scopeFor(sire, dam),
    );
  }

  /// Explicit restricted calculation for comparison and exact B/D(/E) tests.
  /// The breeder UI calls predict(), which uses the broader engine for migrated profiles.
  /// This method never infers a complete genotype from known B/D carriers.
  static ColorPrediction predictBaseColors({
    required Map<String, dynamic> sire,
    required Map<String, dynamic> dam,
    ColorCarrierDetails sireCarriers = const ColorCarrierDetails(),
    ColorCarrierDetails damCarriers = const ColorCarrierDetails(),
  }) {
    final matched = profiles
        .where((p) => p.matchesBreed(sire['breed']))
        .firstOrNull;
    if (matched == null) {
      throw ArgumentError('No restricted base-color profile for this breed.');
    }
    final profile = RabbitColorProfile(
      matched.breed,
      aliases: matched.aliases,
      solidColors: matched.solidColors,
      modelsTortoise: matched.modelsTortoise,
      tanPattern: matched.tanPattern,
      eyebandOnly: matched.eyebandOnly,
    );
    final issue = profile.inputIssue(sire) ?? profile.inputIssue(dam);
    if (issue != null) throw ArgumentError(issue);
    return _predictBaseColors(
      profile: profile,
      sire: sire,
      dam: dam,
      sireCarriers: sireCarriers,
      damCarriers: damCarriers,
      scope: profile.scope,
    );
  }

  static ColorPrediction _predictBaseColors({
    required RabbitColorProfile profile,
    required Map<String, dynamic> sire,
    required Map<String, dynamic> dam,
    required ColorCarrierDetails sireCarriers,
    required ColorCarrierDetails damCarriers,
    required String scope,
  }) {
    final scenarios = <Map<(BaseCoatColor, bool), double>>[];
    final sires = _genotypes(
      profile.phenotypeOf(sire)!,
      sireCarriers,
      profile.modelsTortoise,
      SavedGenotypeConstraints.read(sire),
    );
    final dams = _genotypes(
      profile.phenotypeOf(dam)!,
      damCarriers,
      profile.modelsTortoise,
      SavedGenotypeConstraints.read(dam),
    );
    if (sires.isEmpty || dams.isEmpty) {
      throw ArgumentError(
        'Saved genotype or carrier choices conflict with the recorded base color. Contact support@ringmasterone.com for help.',
      );
    }
    for (final s in sires) {
      for (final d in dams) {
        final probabilities = <(BaseCoatColor, bool), double>{};
        for (final b in inheritLocus(s.b, d.b)) {
          for (final density in inheritLocus(s.d, d.d)) {
            for (final e in inheritLocus(s.e, d.e)) {
              final color = b.genotype.isRecessive('b')
                  ? (density.genotype.isRecessive('d')
                        ? BaseCoatColor.lilac
                        : BaseCoatColor.chocolate)
                  : (density.genotype.isRecessive('d')
                        ? BaseCoatColor.blue
                        : BaseCoatColor.black);
              final outcome = (
                color,
                profile.modelsTortoise && e.genotype.isRecessive('e'),
              );
              final chance =
                  b.probability * density.probability * e.probability;
              probabilities.update(
                outcome,
                (p) => p + chance,
                ifAbsent: () => chance,
              );
            }
          }
        }
        scenarios.add(probabilities);
      }
    }
    final ranges = <ColorChanceRange>[];
    for (final tortoise in [false, if (profile.modelsTortoise) true]) {
      for (final color in BaseCoatColor.values) {
        final chances =
            scenarios.map((s) => s[(color, tortoise)] ?? 0.0).toList()..sort();
        if (chances.last > 0) {
          ranges.add(
            ColorChanceRange(
              color,
              chances.first,
              chances.last,
              tortoise: tortoise,
              displayLabel: profile.eyebandOnly
                  ? '${color.label} base pigment'
                  : null,
            ),
          );
        }
      }
    }
    return ColorPrediction(
      List.unmodifiable(ranges),
      scenarios.length,
      title: profile.resultTitle,
      parentInterpretations: [
        for (final (role, animal) in [('Buck', sire), ('Doe', dam)])
          if (SavedGenotypeConstraints.read(animal) case final saved?)
            saved.note(role, pigmentOnly: profile.eyebandOnly),
      ],
      limitation: profile.eyebandOnly ? HototColorRules.limitation : null,
      limitationTitle: profile.eyebandOnly ? 'Eye-band pigment only' : null,
      scope: scope,
    );
  }

  static List<({AllelePair b, AllelePair d, AllelePair e})> _genotypes(
    ColorPhenotype phenotype,
    ColorCarrierDetails carriers,
    bool extension, [
    SavedGenotypeConstraints? saved,
  ]) => [
    for (final b in _options(
      'B',
      'b',
      phenotype.base.chocolateBased,
      carriers.chocolate,
    ))
      if (saved?.matches('B', b) ?? true)
        for (final d in _options(
          'D',
          'd',
          phenotype.base.dilute,
          carriers.dilute,
        ))
          if (saved?.matches('D', d) ?? true)
            for (final e
                in extension
                    ? _options('E', 'e', phenotype.tortoise, carriers.tortoise)
                    : const [AllelePair('E', 'E')])
              if (!extension || (saved?.matches('E', e) ?? true))
                (b: b, d: d, e: e),
  ];

  static List<AllelePair> _options(
    String dominant,
    String recessive,
    bool expressed,
    CarrierKnowledge knowledge,
  ) {
    if (expressed) return [AllelePair(recessive, recessive)];
    return [
      if (knowledge != CarrierKnowledge.yes) AllelePair(dominant, dominant),
      if (knowledge != CarrierKnowledge.no) AllelePair(dominant, recessive),
    ];
  }
}
