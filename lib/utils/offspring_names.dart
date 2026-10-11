import 'dart:math';

const offspringNames = [
  'Maple',
  'Jasper',
  'Clover',
  'Willow',
  'Hazel',
  'Aspen',
  'Cedar',
  'Juniper',
  'Pebble',
  'Meadow',
  'Poppy',
  'Daisy',
  'Fern',
  'Basil',
  'Sage',
  'Olive',
  'Peaches',
  'Honey',
  'Cocoa',
  'Mocha',
  'Toffee',
  'Cinnamon',
  'Nutmeg',
  'Ginger',
  'Biscuit',
  'Waffles',
  'Mochi',
  'Truffle',
  'Pumpkin',
  'Mango',
  'Pearl',
  'Opal',
  'Ruby',
  'Amber',
  'Jade',
  'Onyx',
  'Topaz',
  'Copper',
  'Luna',
  'Nova',
  'Comet',
  'Cosmo',
  'Orion',
  'Stella',
  'Sunny',
  'Skye',
  'River',
  'Brook',
  'Rain',
  'Storm',
  'Frost',
  'Snowdrop',
  'Cloud',
  'Breeze',
  'Teddy',
  'Pip',
  'Scout',
  'Finn',
  'Milo',
  'Remy',
  'Wren',
  'Robin',
  'Echo',
  'Piper',
  'Misty',
  'Marigold',
  'Blossom',
  'Petal',
  'Clementine',
  'Saffron',
];

String normalizedTattoo(dynamic value) =>
    (value ?? '').toString().trim().toLowerCase();

String shortenedTattoo(String name) {
  final letters = name.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
  final consonants = letters.replaceAll(RegExp('[AEIOU]'), '');
  final base = consonants.length >= 3 ? consonants : letters;
  return base.isEmpty ? 'KIT' : base.substring(0, min(3, base.length));
}

/// Fill blanks only. Reserve all typed tattoos before generating any new ones.
List<Map<String, dynamic>> generateOffspringNames(
  List<Map<String, dynamic>> young,
  List<Map<String, dynamic>> herd, {
  Random? random,
}) {
  final names = [...offspringNames]..shuffle(random ?? Random());
  final usedNames = {
    ...herd,
    ...young,
  }.map((a) => normalizedTattoo(a['name'])).toSet();
  final usedTattoos = {
    ...herd,
    ...young,
  }.map((a) => normalizedTattoo(a['tattoo'])).toSet();
  var next = 0;
  return young.map((original) {
    final animal = Map<String, dynamic>.from(original);
    if (normalizedTattoo(animal['name']).isEmpty) {
      String candidate;
      do {
        candidate =
            '${names[next % names.length]}${next < names.length ? '' : (next ~/ names.length) + 1}';
        next++;
      } while (usedNames.contains(normalizedTattoo(candidate)));
      animal['name'] = candidate;
      usedNames.add(normalizedTattoo(candidate));
    }
    if (normalizedTattoo(animal['tattoo']).isEmpty) {
      final base = shortenedTattoo(animal['name'].toString());
      var candidate = base;
      var suffix = 2;
      while (usedTattoos.contains(normalizedTattoo(candidate))) {
        candidate = '$base${suffix++}';
      }
      animal['tattoo'] = candidate;
      usedTattoos.add(normalizedTattoo(candidate));
    }
    return animal;
  }).toList();
}
