bool animalIsMale(String sex) =>
    ['m', 'male', 'buck', 'boar'].contains(sex.toLowerCase());
String sexLabel(String species, String sex) => species.toLowerCase() == 'cavy'
    ? (animalIsMale(sex) ? 'Boar' : 'Sow')
    : (animalIsMale(sex) ? 'Buck' : 'Doe');
bool animalIsLocked(String status) => status == 'sold' || status == 'deceased';

String animalTitle(String? name, String? earNumber) {
  final label = name?.trim() ?? '';
  final ear = earNumber?.trim() ?? '';
  if (label.isEmpty) return ear.isEmpty ? 'Unnamed' : ear;
  return ear.isEmpty ? label : '$label * $ear';
}
