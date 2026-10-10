bool hasCodLabel(String value) =>
    RegExp(r'\(\s*cod\s*\)\s*$', caseSensitive: false).hasMatch(value);

Map<String, String> colorDetails(Map<String, dynamic> animal) =>
    Map<String, String>.from(
      animal['color_details'] ?? const <String, String>{},
    );

String varietyLabel(Map<String, dynamic> animal) {
  final variety = animal['variety']?.toString().trim() ?? '';
  final details = colorDetails(animal);
  final parts = <String>[variety];
  for (final key in [
    'color',
    'pattern',
    'base_color',
    'tipping',
    'eye_color',
  ]) {
    final value = details[key]?.trim() ?? '';
    if (value.isNotEmpty &&
        !parts.any((p) => p.toLowerCase() == value.toLowerCase())) {
      parts.add(value);
    }
  }
  return parts.where((p) => p.isNotEmpty).join(' • ');
}

String? codDetailsError(
  String breed,
  String variety,
  Map<String, String> details,
) {
  if (!hasCodLabel(breed) && !hasCodLabel(variety)) return null;
  for (final key in ['color', 'pattern']) {
    if ((details[key]?.trim() ?? '').isEmpty) {
      return 'Enter the $key for this COD selection.';
    }
  }
  return null;
}
