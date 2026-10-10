import 'package:flutter/material.dart';
import '../utils/animal_labels.dart';
import '../utils/color_details.dart';
import 'catalog_field.dart';
import 'color_details_fields.dart';
import 'dob_field.dart';

class ParentPicker extends StatefulWidget {
  final String label, species, sex, breed;
  final Future<List<Map<String, dynamic>>> Function() loadParents;
  final ValueChanged<Map<String, dynamic>?> onChanged;
  const ParentPicker({
    super.key,
    required this.label,
    required this.species,
    required this.sex,
    required this.breed,
    required this.loadParents,
    required this.onChanged,
  });
  @override
  State<ParentPicker> createState() => _ParentPickerState();
}

class _ParentPickerState extends State<ParentPicker> {
  late Future<List<Map<String, dynamic>>> parents;
  Map<String, dynamic>? selected;
  bool unknown = false;
  @override
  void initState() {
    super.initState();
    parents = widget.loadParents();
  }

  void choose(Map<String, dynamic>? value) {
    setState(() {
      selected = value;
      unknown = false;
    });
    widget.onChanged(value);
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<Map<String, dynamic>>>(
    future: parents,
    builder: (context, snapshot) {
      final rows = snapshot.data ?? [];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            title: Text('${widget.label} unknown'),
            value: unknown,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (v) {
              setState(() {
                unknown = v!;
                selected = null;
              });
              widget.onChanged(null);
            },
          ),
          if (!unknown) ...[
            if (snapshot.hasError)
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Could not load existing parents. Please retry before adding one.',
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => parents = widget.loadParents()),
                    child: const Text('Retry'),
                  ),
                ],
              )
            else if (!snapshot.hasData)
              const LinearProgressIndicator()
            else ...[
              DropdownButtonFormField<String>(
                key: ValueKey(
                  selected == null ? null : selected!['existing_id'] ?? 'new',
                ),
                initialValue: selected == null
                    ? null
                    : selected!['existing_id'] ?? 'new',
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: widget.label,
                  helperText: 'Includes inactive and pedigree-only animals.',
                ),
                items: [
                  for (final row in rows)
                    DropdownMenuItem<String>(
                      value: row['id'],
                      child: Text(
                        animalTitle(row['name'], row['tattoo']),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (selected != null && selected!['existing_id'] == null)
                    DropdownMenuItem(
                      value: 'new',
                      child: Text(
                        '${animalTitle(selected!['name'], selected!['tattoo'])} (new)',
                      ),
                    ),
                ],
                onChanged: (id) {
                  if (id != 'new') {
                    choose({
                      ...rows.firstWhere((r) => r['id'] == id),
                      'existing_id': id,
                    });
                  }
                },
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text('Add ${widget.label.toLowerCase()}'),
                    onPressed: () async {
                      final result = await showDialog<Map<String, dynamic>>(
                        context: context,
                        builder: (_) => QuickParentDialog(
                          label: widget.label,
                          species: widget.species,
                          sex: widget.sex,
                          breed: widget.breed,
                          existing: rows,
                        ),
                      );
                      if (mounted && result != null) choose(result);
                    },
                  ),
                  if (selected != null && selected!['existing_id'] == null)
                    TextButton(
                      child: const Text('Edit details'),
                      onPressed: () async {
                        final result = await showDialog<Map<String, dynamic>>(
                          context: context,
                          builder: (_) => QuickParentDialog(
                            label: widget.label,
                            species: widget.species,
                            sex: widget.sex,
                            breed: widget.breed,
                            existing: rows,
                            initial: selected,
                          ),
                        );
                        if (mounted && result != null) choose(result);
                      },
                    ),
                  if (selected != null)
                    TextButton(
                      onPressed: () => choose(null),
                      child: const Text('Clear'),
                    ),
                ],
              ),
            ],
          ],
        ],
      );
    },
  );
}

class QuickParentDialog extends StatefulWidget {
  final String label, species, sex, breed;
  final List<Map<String, dynamic>> existing;
  final Map<String, dynamic>? initial;
  final Future<List<Map<String, dynamic>>> Function(String, String?)?
  loadOptions;
  const QuickParentDialog({
    super.key,
    required this.label,
    required this.species,
    required this.sex,
    required this.breed,
    required this.existing,
    this.initial,
    this.loadOptions,
  });
  @override
  State<QuickParentDialog> createState() => _QuickParentDialogState();
}

class _QuickParentDialogState extends State<QuickParentDialog> {
  late final Map<String, dynamic> data;
  String? error;
  @override
  void initState() {
    super.initState();
    data = {...?widget.initial};
    data.putIfAbsent('breed', () => widget.breed);
    data['sex'] = widget.sex;
  }

  void submit() {
    final name = (data['name'] as String? ?? '').trim();
    final tattoo = (data['tattoo'] as String? ?? '').trim();
    final message = name.isEmpty && tattoo.isEmpty
        ? 'Enter a name or ear number.'
        : dobError(data['dob'] ?? '') ??
              codDetailsError(
                data['breed'] ?? '',
                data['variety'] ?? '',
                colorDetails(data),
              );
    final weight = (data['weight'] ?? '').toString().trim();
    if (message != null ||
        (weight.isNotEmpty &&
            (double.tryParse(weight) == null ||
                !double.parse(weight).isFinite ||
                double.parse(weight) <= 0))) {
      setState(() => error = message ?? 'Weight must be a positive number.');
      return;
    }
    final matches = widget.existing
        .where(
          (a) =>
              tattoo.isNotEmpty &&
              (a['tattoo'] ?? '').toString().trim().toLowerCase() ==
                  tattoo.toLowerCase(),
        )
        .toList();
    if (matches.isNotEmpty) {
      setState(
        () => error =
            'That ear number already exists. Select the existing parent below.',
      );
      return;
    }
    Navigator.pop(context, {...data, 'name': name, 'tattoo': tattoo});
  }

  @override
  Widget build(BuildContext context) {
    final matches = widget.existing.where(
      (a) =>
          (data['tattoo'] ?? '').toString().trim().isNotEmpty &&
          (a['tattoo'] ?? '').toString().trim().toLowerCase() ==
              data['tattoo'].toString().trim().toLowerCase(),
    );
    return AlertDialog(
      title: Text('Add ${widget.label.toLowerCase()}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${widget.species == 'rabbit' ? 'Rabbit' : 'Cavy'} • ${widget.sex}',
              ),
              const Text(
                'Saved with this animal as a pedigree-only parent, outside your active herd.',
              ),
              for (final field in {
                'name': 'Name',
                'tattoo': 'Ear number / tag',
              }.entries)
                TextFormField(
                  initialValue: data[field.key],
                  decoration: InputDecoration(labelText: field.value),
                  onChanged: (v) => setState(() {
                    data[field.key] = v;
                    error = null;
                  }),
                ),
              for (final row in matches)
                TextButton(
                  onPressed: () => Navigator.pop(context, {
                    ...row,
                    'existing_id': row['id'],
                  }),
                  child: Text(
                    'Use existing ${animalTitle(row['name'], row['tattoo'])}',
                  ),
                ),
              CatalogField(
                species: widget.species,
                value: data['breed'] ?? '',
                loadOptions: widget.loadOptions,
                onChanged: (v) => setState(() {
                  data['breed'] = v;
                  data['variety'] = '';
                  data['color_details'] = <String, String>{};
                }),
              ),
              CatalogField(
                key: ValueKey(data['breed']),
                species: widget.species,
                breed: data['breed'] ?? '',
                value: data['variety'] ?? '',
                loadOptions: widget.loadOptions,
                onChanged: (v) => setState(() {
                  data['variety'] = v;
                  data['color_details'] = <String, String>{};
                }),
              ),
              ColorDetailsFields(
                key: ValueKey('${data['breed']}:${data['variety']}'),
                breed: data['breed'] ?? '',
                variety: data['variety'] ?? '',
                value: colorDetails(data),
                onChanged: (v) => setState(() => data['color_details'] = v),
              ),
              DobField(
                value: data['dob'] ?? '',
                onChanged: (v) => data['dob'] = v,
              ),
              for (final field in {
                'registration_number': 'Registration number',
                'grand_champion_number': 'Grand champion number',
                'weight': 'Weight (decimal lb)',
              }.entries)
                TextFormField(
                  initialValue: data[field.key]?.toString(),
                  decoration: InputDecoration(labelText: field.value),
                  onChanged: (v) => data[field.key] = v.trim(),
                ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: submit,
          child: Text('Use ${widget.label.toLowerCase()}'),
        ),
      ],
    );
  }
}
