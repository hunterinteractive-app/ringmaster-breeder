class PedigreeNode {
  final String? name;
  final String? breed;
  final String? variety;
  final String? tattoo;
  final String? registration;
  final String? gc;
  final String? dob;
  final double? weight;

  final PedigreeNode? sire;
  final PedigreeNode? dam;

  PedigreeNode({
    this.name,
    this.breed,
    this.variety,
    this.tattoo,
    this.registration,
    this.gc,
    this.dob,
    this.weight,
    this.sire,
    this.dam,
  });
}