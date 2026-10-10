import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/animal_labels.dart';

typedef BulkRecordWriter =
    Future<void> Function(String table, List<Map<String, dynamic>> rows);

class BulkRecordsDialog extends StatefulWidget {
  final List<Map<String, dynamic>> animals;
  final bool weights;
  final BulkRecordWriter? writer;
  const BulkRecordsDialog({
    super.key,
    required this.animals,
    required this.weights,
    this.writer,
  });
  @override
  State<BulkRecordsDialog> createState() => _BulkRecordsDialogState();
}

class _BulkRecordsDialogState extends State<BulkRecordsDialog> {
  final selected = <String>{};
  final values = <String, TextEditingController>{};
  final title = TextEditingController(),
      medication = TextEditingController(),
      dosage = TextEditingController(),
      vet = TextEditingController(),
      notes = TextEditingController();
  DateTime date = DateTime.now();
  DateTime? expires, readminister;
  String type = 'health';
  bool saving = false;
  String? error;
  late final animals = widget.animals
      .where((a) => !animalIsLocked(a['status'] ?? 'active'))
      .toList();
  @override
  void dispose() {
    for (final c in [...values.values, title, medication, dosage, vet, notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> pickDate(
    DateTime? initial,
    void Function(DateTime) apply,
  ) async {
    final result = await showDatePicker(
      context: context,
      initialDate: initial ?? date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (result != null && mounted) setState(() => apply(result));
  }

  Future<void> save() async {
    if (saving) return;
    setState(() => error = null);
    if (selected.isEmpty) {
      setState(() => error = 'Choose at least one animal.');
      return;
    }
    if (!widget.weights && title.text.trim().isEmpty) {
      setState(() => error = 'Enter a record title.');
      return;
    }
    final rows = <Map<String, dynamic>>[];
    for (final id in selected) {
      if (widget.weights) {
        final weight = double.tryParse(values[id]?.text.trim() ?? '');
        if (weight == null || !weight.isFinite || weight <= 0) {
          setState(
            () => error = 'Enter a positive weight for every selected animal.',
          );
          return;
        }
        rows.add({
          'animal_id': id,
          'weight': weight,
          'recorded_at': date.toUtc().toIso8601String(),
        });
      } else {
        rows.add({
          'animal_id': id,
          'record_type': type,
          'title': title.text.trim(),
          'medication': medication.text.trim(),
          'dosage': dosage.text.trim(),
          'veterinarian': vet.text.trim(),
          'description': notes.text.trim(),
          'administered_date': DateFormat('yyyy-MM-dd').format(date),
          'expires_date': expires == null
              ? null
              : DateFormat('yyyy-MM-dd').format(expires!),
          'readminister_date': readminister == null
              ? null
              : DateFormat('yyyy-MM-dd').format(readminister!),
          'retention': 'never',
        });
      }
    }
    setState(() => saving = true);
    try {
      final table = widget.weights ? 'animal_weights' : 'animal_health_records';
      if (widget.writer != null) {
        await widget.writer!(table, rows);
      } else {
        await Supabase.instance.client.from(table).insert(rows);
      }
      if (mounted) Navigator.pop(context, rows.length);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'Unable to save the records. Please try again.';
        });
      }
    }
  }

  Widget field(
    TextEditingController controller,
    String label, {
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      maxLines: lines,
      decoration: InputDecoration(labelText: label),
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      title: Text(
        widget.weights
            ? 'Bulk add weights'
            : 'Bulk add health / vaccine records',
      ),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: AbsorbPointer(
            absorbing: saving,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Choose animals from your current filtered view. Sold and deceased animals are excluded.',
                ),
                TextButton(
                  onPressed: () => pickDate(
                    date,
                    (d) => date = DateTime(
                      d.year,
                      d.month,
                      d.day,
                      date.hour,
                      date.minute,
                    ),
                  ),
                  child: Text('Date: ${DateFormat('MM-dd-yy').format(date)}'),
                ),
                if (widget.weights)
                  TextButton(
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(date),
                      );
                      if (t != null && mounted) {
                        setState(
                          () => date = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            t.hour,
                            t.minute,
                          ),
                        );
                      }
                    },
                    child: Text(
                      'Local time: ${DateFormat('HH:mm').format(date)}',
                    ),
                  ),
                if (!widget.weights) ...[
                  const Text(
                    'The same record will be added to each selected animal.',
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Record type'),
                    items: const [
                      DropdownMenuItem(value: 'health', child: Text('Health')),
                      DropdownMenuItem(
                        value: 'vaccine',
                        child: Text('Vaccine'),
                      ),
                    ],
                    onChanged: (v) => setState(() => type = v!),
                  ),
                  const SizedBox(height: 12),
                  field(title, 'Title'),
                  field(medication, 'Medication'),
                  field(dosage, 'Dosage'),
                  field(vet, 'Veterinarian'),
                  field(notes, 'Notes', lines: 3),
                  TextButton(
                    onPressed: () => pickDate(expires, (d) => expires = d),
                    child: Text(
                      'Expires: ${expires == null ? 'Not set' : DateFormat('MM-dd-yy').format(expires!)}',
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        pickDate(readminister, (d) => readminister = d),
                    child: Text(
                      'Re-administer: ${readminister == null ? 'Not set' : DateFormat('MM-dd-yy').format(readminister!)}',
                    ),
                  ),
                ],
                CheckboxListTile(
                  title: const Text('Select all eligible animals'),
                  value:
                      animals.isNotEmpty && selected.length == animals.length,
                  onChanged: (v) => setState(() {
                    selected.clear();
                    if (v == true) {
                      selected.addAll(animals.map((a) => a['id'] as String));
                    }
                  }),
                ),
                if (animals.isEmpty)
                  const Text('No eligible animals in this view.'),
                for (final a in animals) ...[
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(animalTitle(a['name'], a['tattoo'])),
                    value: selected.contains(a['id']),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        selected.add(a['id']);
                      } else {
                        selected.remove(a['id']);
                      }
                    }),
                  ),
                  if (widget.weights && selected.contains(a['id']))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        controller: values.putIfAbsent(
                          a['id'],
                          () => TextEditingController(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText:
                              '${animalTitle(a['name'], a['tattoo'])} weight (lb)',
                        ),
                      ),
                    ),
                ],
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : save,
          child: Text(
            saving ? 'Saving…' : 'Save for ${selected.length} animals',
          ),
        ),
      ],
    ),
  );
}
