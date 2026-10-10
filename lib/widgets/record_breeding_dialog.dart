import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/animal_labels.dart';

typedef BreedingWriter =
    Future<void> Function(List<Map<String, dynamic>> records);

class RecordBreedingDialog extends StatefulWidget {
  final List<Map<String, dynamic>> animals;
  final BreedingWriter? writer;
  const RecordBreedingDialog({super.key, required this.animals, this.writer});
  @override
  State<RecordBreedingDialog> createState() => _RecordBreedingDialogState();
}

class _RecordBreedingDialogState extends State<RecordBreedingDialog> {
  String? sireId;
  final dams = <String>{};
  final notes = TextEditingController();
  DateTime date = DateTime.now();
  bool saving = false;
  String? error;
  List<Map<String, dynamic>> get active => widget.animals
      .where((a) => a['status'] == 'active' && a['pedigree_only'] != true)
      .toList();
  List<Map<String, dynamic>> get sires =>
      active.where((a) => animalIsMale(a['sex'] ?? '')).toList();
  Map<String, dynamic>? get sire =>
      sires.where((a) => a['id'] == sireId).firstOrNull;
  List<Map<String, dynamic>> get eligibleDams => active
      .where(
        (a) =>
            [
              'f',
              'female',
              'doe',
              'sow',
            ].contains((a['sex'] ?? '').toString().toLowerCase()) &&
            a['species'] == sire?['species'] &&
            a['ring_id'] == sire?['ring_id'],
      )
      .toList();
  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    if (sire == null || dams.isEmpty) {
      setState(() => error = 'Choose a sire and at least one dam.');
      return;
    }
    final rows = [
      for (final id in dams)
        {
          'sire_id': sireId,
          'dam_id': id,
          'breeding_date': DateFormat('yyyy-MM-dd').format(date),
          'notes': notes.text.trim(),
        },
    ];
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (widget.writer != null) {
        await widget.writer!(rows);
      } else {
        await Supabase.instance.client.from('breeding_records').insert(rows);
      }
      if (mounted) Navigator.pop(context, rows.length);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e is PostgrestException && e.code == '23505'
              ? 'A breeding for this sire, dam and date already exists. No new records were added.'
              : 'Unable to save. Check that both parents are still active and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      title: const Text('Record breeding'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: AbsorbPointer(
            absorbing: saving,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Choose one sire and one or more dams. A separate breeding record will be saved for each dam.',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: sireId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Sire (Buck / Boar)',
                  ),
                  items: sires
                      .map(
                        (a) => DropdownMenuItem<String>(
                          value: a['id'],
                          child: Text(
                            '${animalTitle(a['name'], a['tattoo'])} — ${sexLabel(a['species'], a['sex'])}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (id) => setState(() {
                    sireId = id;
                    dams.clear();
                    error = null;
                  }),
                ),
                if (sires.isEmpty)
                  const Text(
                    'Add an active buck or boar to record a breeding.',
                  ),
                if (sire != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    sire!['species'] == 'cavy' ? 'Dams (Sows)' : 'Dams (Does)',
                  ),
                  if (eligibleDams.isEmpty)
                    const Text(
                      'No active dams of the same species are available.',
                    ),
                  for (final a in eligibleDams)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(animalTitle(a['name'], a['tattoo'])),
                      value: dams.contains(a['id']),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          dams.add(a['id']);
                        } else {
                          dams.remove(a['id']);
                        }
                      }),
                    ),
                ],
                TextButton.icon(
                  icon: const Icon(Icons.calendar_month),
                  label: Text(
                    'Breeding date: ${DateFormat('MM-dd-yy').format(date)}',
                  ),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(1900),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null && mounted) {
                      setState(() => date = picked);
                    }
                  },
                ),
                TextField(
                  controller: notes,
                  maxLines: 3,
                  maxLength: 4000,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                  ),
                ),
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
          child: Text(saving ? 'Saving…' : 'Save breeding'),
        ),
      ],
    ),
  );
}
