import 'coat_rules.dart';

/// A reference supplied by the breeder or an import, used only as compatible
/// constraints after explicit parsing by the prediction layer.
/// Notation is retained verbatim (apart from outer whitespace), including '?'
/// and '-'. Saving it does not certify or complete the rabbit's genotype.
class AnimalGenotype {
  final String notation, basis, source;
  const AnimalGenotype({
    required this.notation,
    this.basis = 'breeder_entered',
    this.source = '',
  });

  static const bases = {
    'breeder_entered': 'Breeder entered',
    'inferred': 'Inferred',
    'imported': 'Imported',
  };

  static String? validate(String notation, String source) {
    if (notation.trim().length > 500) {
      return 'Keep the genotype under 500 characters.';
    }
    if (source.trim().length > 300) {
      return 'Keep the source under 300 characters.';
    }
    if (notation.trim().isEmpty && source.trim().isNotEmpty) {
      return 'Enter a genotype, or clear both fields to remove the saved entry.';
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    final error = validate(notation, source);
    if (error != null || !bases.containsKey(basis)) {
      throw FormatException(error ?? 'Choose how this genotype was obtained.');
    }
    return notation.trim().isEmpty
        ? {}
        : {
            'notation': notation.trim(),
            'basis': basis,
            if (source.trim().isNotEmpty) 'source': source.trim(),
          };
  }

  static AnimalGenotype? read(dynamic raw) {
    if (raw == null || raw is Map && raw.isEmpty) return null;
    if (raw is! Map ||
        raw['notation'] is! String ||
        raw['basis'] is! String ||
        !bases.containsKey(raw['basis']) ||
        raw['notation'].toString().trim().isEmpty ||
        raw['source'] != null && raw['source'] is! String ||
        raw.keys.any((k) => !['notation', 'basis', 'source'].contains(k))) {
      throw const FormatException('Saved genotype could not be read.');
    }
    final result = AnimalGenotype(
      notation: raw['notation'] as String,
      basis: raw['basis'] as String,
      source: raw['source'] as String? ?? '',
    );
    result.toJson();
    return result;
  }

  /// Only the allele copies shared by every conditional color interpretation
  /// are shown. A fully unresolved locus is omitted, never guessed homozygous.
  static String? colorInference(Map<String, dynamic> animal) {
    final input = CoatRules.resolve(animal);
    if (input == null) return null;
    final tokens = <String>[];
    for (final e in input.loci.entries) {
      final pairs = e.value;
      if (pairs.isEmpty) continue;
      if (pairs.length == 1) {
        tokens.add('${pairs.single.first}${pairs.single.second}');
        continue;
      }
      final common = coatDomains[e.key]!.where(
        (allele) => pairs.every((p) => p.first == allele || p.second == allele),
      );
      if (common.length == 1) tokens.add('${common.single}-');
    }
    return tokens.isEmpty ? null : tokens.join(' ');
  }
}
