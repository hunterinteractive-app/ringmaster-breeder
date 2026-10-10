import 'parent_picker.dart';
import '../utils/color_details.dart';
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
  bool includeInactive = false;
  final extraParents = <Map<String, dynamic>>[];
  List<Map<String, dynamic>>? loadedParents;
  String? get ringId => widget.animals.firstOrNull?['ring_id'];
  List<Map<String, dynamic>> get allParents => [
    ...(loadedParents ?? widget.animals),
    ...extraParents,
  ];
  String detail(Map<String, dynamic> a) => [
    a['breed'],
    varietyLabel(a),
  ].whereType<String>().where((v) => v.trim().isNotEmpty).join(' • ');
  Widget parentLabel(Map<String, dynamic> a) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        animalTitle(a['name'], a['tattoo']),
        overflow: TextOverflow.ellipsis,
      ),
      Text(
        detail(a),
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
    ],
  );
  Future<void> loadAll() async {
    if (loadedParents != null) return;
    if (ringId == null) throw StateError('No Ring selected');
    loadedParents = List<Map<String, dynamic>>.from(
      await Supabase.instance.client
          .from('animals')
          .select()
          .eq('ring_id', ringId!),
    );
  }

  Future<void> addParent(bool male) async {
    try {
      await loadAll();
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Unable to load parents. Please try again.');
      }
      return;
    }
    if (!mounted) return;
    final String? species = !male
        ? (sire?['species'] as String?)
        : await showDialog<String>(
            context: context,
            builder: (ctx) => SimpleDialog(
              title: const Text('Parent species'),
              children: [
                for (final item in ['rabbit', 'cavy'])
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, item),
                    child: Text(item == 'rabbit' ? 'Rabbit' : 'Cavy'),
                  ),
              ],
            ),
          );
    if (species == null || !mounted) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => QuickParentDialog(
        label: male ? 'Sire' : 'Dam',
        species: species,
        sex: sexLabel(species, male ? 'M' : 'F'),
        breed: sire?['breed'] ?? '',
        saveHint:
            'Saved with this breeding as a pedigree-only parent, outside your active herd.',
        existing: allParents
            .where(
              (a) =>
                  a['species'] == species &&
                  animalIsMale(a['sex'] ?? '') == male,
            )
            .toList(),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      includeInactive = true;
      final id = result['existing_id'] ?? 'new-parent-${extraParents.length}';
      if (result['existing_id'] == null) {
        extraParents.add({
          ...result,
          'id': id,
          'species': species,
          'ring_id': ringId,
          'status': 'active',
          'pedigree_only': true,
        });
      }
      if (male) {
        sireId = id;
        dams.clear();
      } else {
        dams.add(id);
      }
    });
  }

  final dams = <String>{};
  final notes = TextEditingController();
  DateTime date = DateTime.now();
  bool saving = false;
  String? error;
  List<Map<String, dynamic>> get active => allParents
      .where(
        (a) =>
            includeInactive ||
            (a['status'] == 'active' && a['pedigree_only'] != true),
      )
      .toList();
  List<Map<String, dynamic>> get sires =>
      active.where((a) => animalIsMale(a['sex'] ?? '')).toList();
  Map<String, dynamic>? get sire =>
      sires.where((a) => a['id'] == sireId).firstOrNull;
  List<Map<String, dynamic>> get eligibleDams =>
      (active
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
          .toList()
        ..sort((a, b) {
          final breed = (sire?['breed'] ?? '').toString().trim().toLowerCase();
          final am =
              (a['breed'] ?? '').toString().trim().toLowerCase() == breed;
          final bm =
              (b['breed'] ?? '').toString().trim().toLowerCase() == breed;
          if (am != bm) return am ? -1 : 1;
          return animalTitle(a['name'], a['tattoo']).toLowerCase().compareTo(
            animalTitle(b['name'], b['tattoo']).toLowerCase(),
          );
        }));
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
        await Supabase.instance.client.rpc(
          'record_breeding_with_parents',
          params: {
            'p_ring': ringId,
            'p_records': rows,
            'p_parents': extraParents
                .where((p) => p['id'] == sireId || dams.contains(p['id']))
                .toList(),
          },
        );
      }
      if (mounted) Navigator.pop(context, rows.length);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e is PostgrestException && e.code == '23505'
              ? 'A breeding for this sire, dam and date already exists. No new records were added.'
              : 'Unable to save. Check the parents and try again.';
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
                  key: ValueKey(sireId),
                  initialValue: sireId,
                  itemHeight: 72,
                  isDense: false,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Sire (Buck / Boar)',
                  ),
                  items: sires
                      .map(
                        (a) => DropdownMenuItem<String>(
                          value: a['id'],
                          child: parentLabel(a),
                        ),
                      )
                      .toList(),
                  onChanged: (id) => setState(() {
                    sireId = id;
                    dams.clear();
                    error = null;
                  }),
                ),
                TextButton.icon(
                  onPressed: () => addParent(true),
                  icon: const Icon(Icons.add),
                  label: const Text('Add borrowed / outside sire'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Include inactive and pedigree-only parents',
                  ),
                  value: includeInactive,
                  onChanged: (v) async {
                    try {
                      if (v == true) await loadAll();
                      if (!mounted) return;
                      setState(() {
                        includeInactive = v!;
                        sireId = null;
                        dams.clear();
                      });
                    } catch (_) {
                      if (mounted) {
                        setState(
                          () => error =
                              'Unable to load inactive parents. Please try again.',
                        );
                      }
                    }
                  },
                ),
                if (sires.isEmpty)
                  const Text(
                    'Choose an existing parent or add a borrowed / outside sire.',
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
                  const Text('Matching breed first, followed by other breeds.'),
                  for (final a in eligibleDams)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(animalTitle(a['name'], a['tattoo'])),
                      subtitle: Text(detail(a)),
                      value: dams.contains(a['id']),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          dams.add(a['id']);
                        } else {
                          dams.remove(a['id']);
                        }
                      }),
                    ),
                  TextButton.icon(
                    onPressed: () => addParent(false),
                    icon: const Icon(Icons.add),
                    label: const Text('Add borrowed / outside dam'),
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
