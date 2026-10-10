import 'package:flutter/material.dart';
import '../utils/color_details.dart';

class ColorDetailsFields extends StatelessWidget {
  final String breed, variety;
  final Map<String, String> value;
  final ValueChanged<Map<String, String>> onChanged;
  final bool readOnly;
  const ColorDetailsFields({
    super.key,
    required this.breed,
    required this.variety,
    required this.value,
    required this.onChanged,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final cod = hasCodLabel(breed) || hasCodLabel(variety);
    final fields = Column(
      children: [
        if (cod)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text(
              'COD: enter the animal’s color and pattern. These descriptions do not change its COD status.',
            ),
          ),
        for (final field in const {
          'color': 'Color',
          'pattern': 'Pattern',
          'base_color': 'Base color',
          'tipping': 'Tipping',
          'eye_color': 'Eye color',
        }.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextFormField(
              key: ValueKey(field.key),
              initialValue: value[field.key] ?? '',
              readOnly: readOnly,
              maxLength: 100,
              decoration: InputDecoration(
                labelText:
                    '${field.value}${cod && ['color', 'pattern'].contains(field.key) ? ' (required)' : ' (optional)'}',
                helperText: field.key == 'pattern'
                    ? 'Describe the pattern, or enter Solid if applicable.'
                    : null,
              ),
              onChanged: (text) =>
                  onChanged({...value, field.key: text.trim()}),
            ),
          ),
        if (value.values.any((v) => v.isNotEmpty))
          Text(
            'Pedigree label: ${varietyLabel({'variety': variety, 'color_details': value})}',
          ),
      ],
    );
    if (cod) return fields;
    return ExpansionTile(
      title: const Text('Additional color details'),
      subtitle: const Text(
        'Keep the variety wording; add details only when needed.',
      ),
      initiallyExpanded: value.values.any((v) => v.isNotEmpty),
      children: [fields],
    );
  }
}
