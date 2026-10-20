import 'animal_genotype.dart';
import 'coat_rules.dart';
import 'genotype_choices.dart';
import 'mendelian.dart';

/// Saved references constrain compatible color candidates; no carrier prior or
/// new genotype is invented. Unsupported notation fails closed for review.
class SavedGenotypeConstraints {
  final AnimalGenotype record;
  final GenotypeChoices choices;
  const SavedGenotypeConstraints._(this.record, this.choices);

  static SavedGenotypeConstraints? read(Map<String, dynamic> animal) {
    final record = AnimalGenotype.read(animal['genotype']);
    if (record == null) return null;
    final choices = GenotypeChoices.read(record.notation);
    if (choices == null) {
      throw const FormatException(
        'The saved genotype includes unsupported or ambiguous notation. Review it under Change genotype → Advanced or contact support@ringmasterone.com. No estimate is shown until it can be read safely.',
      );
    }
    return SavedGenotypeConstraints._(record, choices);
  }

  bool matches(String locus, AllelePair candidate) {
    final pair = choices.pairs[locus];
    if (pair == null) return true;
    final known = [pair.first, pair.second].whereType<String>().toList();
    final remaining = [candidate.first, candidate.second];
    for (final allele in known) {
      if (!remaining.remove(allele)) return false;
    }
    return true;
  }

  CoatInput apply(CoatInput input) {
    final loci = {
      for (final entry in input.loci.entries)
        entry.key: entry.value.where((p) => matches(entry.key, p)).toList(),
    };
    for (final entry in loci.entries) {
      if (entry.value.isEmpty) {
        throw FormatException(
          'The saved genotype conflicts with the recorded color or color details at ${entry.key}. Review the genotype and color; contact support@ringmasterone.com for help.',
        );
      }
    }
    return CoatInput(input.name, loci, input.family);
  }

  String note(String role, {bool pigmentOnly = false}) =>
      '$role: using saved genotype ${record.notation} '
      '(${AnimalGenotype.bases[record.basis]}${record.source.isEmpty ? '' : '; source: ${record.source}'}). '
      '${pigmentOnly ? 'Only B/D base-pigment constraints are used in this limited preview. ' : ''}'
      'Unknown genes remain unresolved. Recorded genes are not independently verified.';
}
