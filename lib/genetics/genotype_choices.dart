import 'coat_rules.dart';

/// Editing aid only: parses complete pairs from the guided loci. It neither
/// infers genes nor certifies a reference genotype's biological accuracy.
class GenotypeChoices {
  final Map<String, ({String? first, String? second, int start, int end})>
  pairs;
  const GenotypeChoices._(this.pairs);

  static GenotypeChoices? read(String text) {
    final pairs =
        <String, ({String? first, String? second, int start, int end})>{};
    var position = 0;
    while (position < text.length) {
      if (RegExp(r'\s').hasMatch(text[position])) {
        position++;
        continue;
      }
      var found = false;
      for (final entry in coatDomains.entries) {
        final alleles = [...entry.value]
          ..sort((a, b) => b.length.compareTo(a.length));
        final choices = alleles.map(RegExp.escape).join('|');
        final match = RegExp(
          '($choices|[-_?])\\s*($choices|[-_?])',
        ).matchAsPrefix(text, position);
        if (match == null) continue;
        String? known(String token) =>
            entry.value.contains(token) ? token : null;
        final first = known(match[1]!), second = known(match[2]!);
        // Unknown/unknown has no locus identifier; do not assign it to a gene.
        if (first == null && second == null) continue;
        if (pairs.containsKey(entry.key)) return null;
        pairs[entry.key] = (
          first: first,
          second: second,
          start: position,
          end: match.end,
        );
        position = match.end;
        found = true;
        break;
      }
      if (!found) return null;
    }
    return GenotypeChoices._(pairs);
  }

  /// Updates one locus, retaining every untouched character of the source.
  /// Unsupported text must be edited in Advanced, never partially discarded.
  static String change(
    String text,
    String locus,
    String? first,
    String? second,
  ) {
    final parsed = read(text);
    final domain = coatDomains[locus];
    if (parsed == null ||
        domain == null ||
        first != null && !domain.contains(first) ||
        second != null && !domain.contains(second)) {
      throw const FormatException('Use Advanced for this genotype notation.');
    }
    final replacement = first == null && second == null
        ? ''
        : '${first ?? second}${first == null ? '-' : second ?? '-'}';
    final previous = parsed.pairs[locus];
    if (previous != null) {
      return text
          .replaceRange(previous.start, previous.end, replacement)
          .trim();
    }
    return [text.trim(), replacement].where((v) => v.isNotEmpty).join(' ');
  }
}
