import 'animal_genotype.dart';
import 'breed_color_contexts.dart';
import 'coat_rules.dart';
import 'coat_solver.dart';
import 'color_prediction.dart';
import 'hotot_colors.dart';
import 'lutino_prediction.dart';
import 'saved_genotype_constraints.dart';
import 'silvered_breeds.dart';
import 'spotted_breeds.dart';

/// Temporary parents use the same inheritance engine as saved rabbits. Each
/// parent's own breed interprets its color; offspring use shared family names.
class WhatIfPredictions {
  static const support = 'Contact support@ringmasterone.com for help.';
  static const limits =
      'This experiment estimates color families only. It does not predict breed, '
      'size, fur type, exact shade, marking quality or show eligibility. Choosing '
      'a variety does not establish that it is recognized for that breed.';

  static String temporaryWording(String text) => text
      .replaceAll('using saved genotype', 'using hypothetical genotype')
      .replaceAll('saved genotype', 'hypothetical genotype')
      .replaceAll('recorded color', 'selected color')
      .replaceAll('recorded variety', 'selected variety')
      .replaceAll('saved in the record', 'entered for this experiment')
      .replaceAll('saved color details', 'temporary color details');

  static bool _sameBreed(Map<String, dynamic> s, Map<String, dynamic> d) =>
      RabbitColorPredictions.profileFor(s)?.matchesBreed(d['breed']) == true;

  static String? inputIssue(Map<String, dynamic> s, Map<String, dynamic> d) {
    for (final (role, parent) in [('Buck', s), ('Doe', d)]) {
      if (parent['species'] != 'rabbit' ||
          parent['breed']?.toString().trim().isNotEmpty != true ||
          parent['variety']?.toString().trim().isNotEmpty != true) {
        return '$role: choose or type a breed and variety.';
      }
    }
    if (_sameBreed(s, d)) {
      final issue = RabbitColorPredictions.inputIssue(s, d);
      return issue == null ? null : '${temporaryWording(issue)} $support';
    }
    if ([s, d].any((p) => HototColorRules.handles(p['breed']))) {
      return 'Mixed-breed Hotot predictions are not built yet. The eye-band '
          'pigment model cannot predict the complete coat of this cross. $support';
    }
    if ([s, d].any(LutinoPredictions.applies)) {
      return 'Mixed-breed experimental Lutino predictions are not built yet. $support';
    }
    for (final (role, parent) in [('Buck', s), ('Doe', d)]) {
      final input = CoatRules.resolve(parent);
      if (input == null) {
        return '$role: ${temporaryWording(RabbitColorPredictions.unresolvedIssue(parent))} $support';
      }
      try {
        SavedGenotypeConstraints.read(parent)?.apply(input);
      } on FormatException catch (e) {
        return '$role: ${temporaryWording(e.message.toString())} $support';
      }
    }
    return null;
  }

  static ColorPrediction predict({
    required Map<String, dynamic> sire,
    required Map<String, dynamic> dam,
  }) {
    final issue = inputIssue(sire, dam);
    if (issue != null) throw ArgumentError(issue);
    if (_sameBreed(sire, dam)) {
      final result = RabbitColorPredictions.predict(sire: sire, dam: dam);
      return ColorPrediction(
        result.colors,
        result.scenarioCount,
        title: 'What If: ${result.title}',
        scope: temporaryWording(result.scope),
        limitation: '$limits ${temporaryWording(result.limitation ?? '')}'
            .trim(),
        limitationTitle: result.limitationTitle,
        markings: result.markings,
        parentInterpretations: result.parentInterpretations
            .map(temporaryWording)
            .toList(),
        unresolvedInformation: result.unresolvedInformation
            .map(temporaryWording)
            .toList(),
      );
    }
    CoatInput resolve(Map<String, dynamic> p) {
      final input = CoatRules.resolve(p)!;
      return SavedGenotypeConstraints.read(p)?.apply(input) ?? input;
    }

    final s = resolve(sire), d = resolve(dam);
    final dutch = [
      sire,
      dam,
    ].any((p) => RabbitColorPredictions.profileFor(p)?.dutchColorOnly == true);
    final result = solveCoats(s, d, includeSpotting: !dutch);
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
            displayLabel: c.outcome.label,
            swatch: c.outcome.base,
            tortoise: c.outcome.tortoise,
            broken: c.outcome.broken,
            isColorFamily: true,
          ),
      ],
      result.scenarioCount,
      title: 'What If: mixed-breed color families',
      scope:
          '${CoatRules.scope} '
          'Each parent uses its own breed’s color interpretation. Results use shared color-family names.',
      limitationTitle: 'Color families, with uncertain traits',
      limitation: [
        limits,
        if (dutch) RabbitColorProfile.dutchModelLimits,
        if (SpottedBreedRules.familyLimitationFor(sire, dam)
            case final String note)
          note,
        if ([sire, dam].any(SilveredBreedRules.appliesTo))
          SilveredBreedRules.limitation,
        if ([
          sire,
          dam,
        ].any((p) => RabbitColorPredictions.profileFor(p)?.tanPattern == true))
          RabbitColorProfile.tanModelLimits,
        if (BreedColorContexts.limitationFor(sire, dam) case final String note)
          note,
      ].map(temporaryWording).join(' '),
      parentInterpretations: [
        for (final (role, parent, input) in [
          ('Buck', sire, s),
          ('Doe', dam, d),
        ])
          '$role: ${parent['breed']} — ${parent['variety']}; modeled as ${input.name}.'
              '${AnimalGenotype.read(parent['genotype']) == null ? '' : ' Hypothetical genotype: ${AnimalGenotype.read(parent['genotype'])!.notation}.'}',
      ],
      unresolvedInformation: [
        for (final (role, input) in [('Buck', s), ('Doe', d)])
          if (input.loci.entries.any(
            (e) => (!dutch || e.key != 'En') && e.value.length > 1,
          ))
            '$role: some genes remain Unknown. Ranges include compatible hidden-gene outcomes; they do not mean those genes are known to be present.',
      ],
    );
  }
}
