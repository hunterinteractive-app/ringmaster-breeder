/// One allele from each parent. No dominance or breed naming is assumed here.
class AllelePair {
  final String first, second;
  const AllelePair(this.first, this.second);

  String get key => ([first, second]..sort()).join('/');
  bool isRecessive(String allele) => first == allele && second == allele;
}

class InheritedPair {
  final AllelePair genotype;
  final double probability;
  const InheritedPair(this.genotype, this.probability);
}

/// Each of a parent's two allele copies is transmitted with probability 1/2.
/// Duplicate offspring genotypes are combined, including homozygous parents.
List<InheritedPair> inheritLocus(AllelePair sire, AllelePair dam) {
  final pairs = <String, AllelePair>{};
  final probabilities = <String, double>{};
  for (final paternal in [sire.first, sire.second]) {
    for (final maternal in [dam.first, dam.second]) {
      final pair = AllelePair(paternal, maternal);
      pairs[pair.key] = pair;
      probabilities.update(pair.key, (p) => p + .25, ifAbsent: () => .25);
    }
  }
  return [
    for (final entry in probabilities.entries)
      InheritedPair(pairs[entry.key]!, entry.value),
  ];
}
