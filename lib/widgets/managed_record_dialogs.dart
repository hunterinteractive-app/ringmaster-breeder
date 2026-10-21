import 'package:flutter/material.dart';
import 'adaptive_layout.dart';

String? managedDateError(String value, {bool required = false}) {
  if (value.isEmpty) return required ? 'Enter a date.' : null;
  final d = DateTime.tryParse(value);
  return d == null ||
          d.year < 1800 ||
          d.toIso8601String().substring(0, 10) != value ||
          value.compareTo(DateTime.now().toIso8601String().substring(0, 10)) > 0
      ? 'Use a valid past date (YYYY-MM-DD).'
      : null;
}

class ContactEditorDialog extends StatefulWidget {
  final Map<String, dynamic> initial;
  final List<Map<String, dynamic>> herds;
  final Future<void> Function(Map<String, dynamic>) writer;
  const ContactEditorDialog({
    super.key,
    this.initial = const {},
    required this.herds,
    required this.writer,
  });
  @override
  State<ContactEditorDialog> createState() => _ContactEditorDialogState();
}

class _ContactEditorDialogState extends State<ContactEditorDialog> {
  static const labels = {
    'name': 'Person name',
    'rabbitry': 'Rabbitry / caviary',
    'email': 'Email',
    'phone': 'Phone',
    'address': 'Street address',
    'city': 'City',
    'state': 'State / province',
    'zip': 'ZIP / postal code',
    'country': 'Country',
  };
  late final fields = {
    for (final k in labels.keys)
      k: TextEditingController(text: widget.initial[k]?.toString() ?? ''),
  };
  late String? herd =
      widget.initial['ring_id'] ??
      (widget.herds.isEmpty ? null : widget.herds.first['id']);
  bool saving = false;
  String? error;
  Map<String, dynamic>? pending;
  @override
  void dispose() {
    for (final f in fields.values) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (herd == null ||
        fields['name']!.text.trim().isEmpty &&
            fields['rabbitry']!.text.trim().isEmpty) {
      setState(
        () => error = 'Choose a herd and enter a person or rabbitry name.',
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      pending ??= {
        'ring_id': herd,
        for (final e in fields.entries) e.key: e.value.text.trim(),
      };
      await widget.writer(pending!);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error =
              'Unable to confirm the save. Retry this contact or cancel and refresh.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AdaptiveFormDialog(
    title: Text(
      widget.initial['id'] == null
          ? 'Add contact / rabbitry'
          : 'Edit contact / rabbitry',
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (error != null) Text(error!),
        DropdownButtonFormField<String>(
          initialValue: herd,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Herd'),
          items: [
            for (final h in widget.herds)
              DropdownMenuItem(
                value: h['id'] as String,
                child: Text(h['name']),
              ),
          ],
          onChanged: saving || pending != null || widget.initial['id'] != null
              ? null
              : (v) => setState(() => herd = v),
        ),
        for (final e in fields.entries)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: TextField(
              controller: e.value,
              enabled: !saving && pending == null,
              maxLength: e.key == 'address' ? 2000 : 500,
              maxLines: e.key == 'address' ? 2 : 1,
              decoration: InputDecoration(
                labelText: labels[e.key],
                counterText: '',
              ),
            ),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: saving ? null : save,
        child: Text(saving ? 'Saving…' : 'Save contact'),
      ),
    ],
  );
}

class ShowResultEditorDialog extends StatefulWidget {
  final Map<String, dynamic> initial;
  final List<Map<String, dynamic>> animals;
  final Future<void> Function(String?, Map<String, dynamic>) writer;
  const ShowResultEditorDialog({
    super.key,
    this.initial = const {},
    required this.animals,
    required this.writer,
  });
  @override
  State<ShowResultEditorDialog> createState() => _ShowResultEditorDialogState();
}

class _ShowResultEditorDialogState extends State<ShowResultEditorDialog> {
  static const labels = {
    'show_name': 'Show name',
    'show_date': 'Show date (YYYY-MM-DD)',
    'location': 'Location',
    'judge': 'Judge',
    'placement': 'Class placing',
    'awards': 'Awards (BOB, BOV, BIS…)',
    'number_in_class': 'Number in class',
    'number_of_exhibitors': 'Number of exhibitors',
    'total_shown': 'Total shown',
    'comments': 'Comments',
  };
  late final r = widget.initial['record'] as Map? ?? {};
  late final fields = {
    for (final k in labels.keys)
      k: TextEditingController(
        text: switch (k) {
          'show_name' => r['shows']?['name'] ?? '',
          'show_date' => r['shows']?['start_date'] ?? '',
          'location' => r['shows']?['location'] ?? '',
          'awards' => r['special_awards']?.toString() ?? '',
          _ => r[k]?.toString() ?? '',
        },
      ),
  };
  late String animal =
      widget.initial['animal_id'] ??
      (widget.animals.length == 1 ? widget.animals.first['id'] : '');
  late bool leg = r['is_leg'] == true, youth = r['is_youth'] == true;
  bool saving = false;
  String? error;
  Map<String, dynamic>? pending;
  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    final dateError = managedDateError(
      fields['show_date']!.text.trim(),
      required: widget.initial['id'] == null,
    );
    if (fields['show_name']!.text.trim().isEmpty ||
        dateError != null ||
        (widget.initial['id'] == null && animal.isEmpty)) {
      setState(
        () => error = dateError ?? 'Choose an animal and enter the show name.',
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      pending ??= {
        for (final e in fields.entries) e.key: e.value.text.trim(),
        'is_leg': leg,
        'is_youth': youth,
      };
      await widget.writer(animal.isEmpty ? null : animal, pending!);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error =
              'Unable to confirm the save. Retry this result or cancel and refresh.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AdaptiveFormDialog(
    title: Text(
      widget.initial['id'] == null ? 'Add show result' : 'Edit show result',
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (error != null) Text(error!),
        DropdownButtonFormField<String>(
          initialValue: animal,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Animal'),
          items: [
            const DropdownMenuItem(value: '', child: Text('Not linked')),
            for (final a in widget.animals)
              DropdownMenuItem(
                value: a['id'] as String,
                child: Text('${a['name'] ?? 'Unnamed'} · ${a['tattoo'] ?? ''}'),
              ),
          ],
          onChanged: saving || pending != null
              ? null
              : (v) => setState(() => animal = v ?? ''),
        ),
        for (final e in fields.entries)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: TextField(
              controller: e.value,
              enabled: !saving && pending == null,
              maxLength: e.key == 'comments' ? 4000 : 500,
              maxLines: e.key == 'comments' ? 3 : 1,
              decoration: InputDecoration(
                labelText: labels[e.key],
                counterText: '',
              ),
            ),
          ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('ARBA leg recorded'),
          value: leg,
          onChanged: saving || pending != null
              ? null
              : (v) => setState(() => leg = v ?? false),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Youth show'),
          value: youth,
          onChanged: saving || pending != null
              ? null
              : (v) => setState(() => youth = v ?? false),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: saving ? null : save,
        child: Text(saving ? 'Saving…' : 'Save show result'),
      ),
    ],
  );
}
