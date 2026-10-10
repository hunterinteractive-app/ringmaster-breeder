import '../widgets/catalog_field.dart';
import '../widgets/color_details_fields.dart';
import '../utils/color_details.dart';
import 'package:flutter/material.dart';
import '../widgets/dob_field.dart';
import '../widgets/sex_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/pedigree_entry.dart';
import '../utils/animal_labels.dart';
import '../widgets/ringmaster_page_shell.dart';

class PedigreeEntryScreen extends StatefulWidget {
  final String ringId;
  final List<Map<String, dynamic>>? initialAnimals;
  const PedigreeEntryScreen({
    super.key,
    required this.ringId,
    this.initialAnimals,
  });
  @override
  State<PedigreeEntryScreen> createState() => _PedigreeEntryScreenState();
}

class _PedigreeEntryScreenState extends State<PedigreeEntryScreen> {
  final entry = PedigreeEntry();
  SupabaseClient get db => Supabase.instance.client;
  final form = GlobalKey<FormState>();
  int slot = 0;
  String? draftId;
  bool busy = false, loading = true, dirty = false;
  String? error;
  List<Map<String, dynamic>> existing = [], drafts = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (widget.initialAnimals != null) {
        existing = widget.initialAnimals!;
        _addExisting();
        if (mounted) setState(() => loading = false);
        return;
      }
      existing = List<Map<String, dynamic>>.from(
        await db.from('animals').select().eq('ring_id', widget.ringId),
      );
      drafts = List<Map<String, dynamic>>.from(
        await db
            .from('pedigree_drafts')
            .select()
            .eq('ring_id', widget.ringId)
            .isFilter('saved_animal_id', null)
            .order('updated_at', ascending: false),
      );
      _addExisting();
    } catch (_) {
      error = 'Unable to load pedigree records. Please reopen this page.';
    }
    if (mounted) setState(() => loading = false);
  }

  void _addExisting() {
    for (final a in existing.where((a) => a['species'] == entry.species)) {
      final key = 'existing:${a['id']}';
      entry.nodes[key] = {
        ...a,
        'existing_id': a['id'],
        if (a['sire_id'] != null) 'sire': 'existing:${a['sire_id']}',
        if (a['dam_id'] != null) 'dam': 'existing:${a['dam_id']}',
      };
    }
  }

  String label(String? key) => key == null
      ? 'Unknown'
      : animalTitle(entry.nodes[key]?['name'], entry.nodes[key]?['tattoo']);
  void _move(int target) {
    if (!(form.currentState?.validate() ?? true)) return;
    setState(() {
      slot = target;
      error = null;
    });
  }

  Future<void> _save(bool finish) async {
    if (!(form.currentState?.validate() ?? true)) return;
    if (finish && !entry.identified(entry.root)) {
      setState(() {
        slot = 0;
        error = 'Enter the animal’s name or ear number.';
      });
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = entry.data();
      if (finish) {
        for (final node in (data['nodes'] as Map).values) {
          if (node['existing_id'] != null) continue;
          final message = codDetailsError(
            node['breed'] ?? '',
            node['variety'] ?? '',
            colorDetails(Map<String, dynamic>.from(node)),
          );
          if (message != null) throw StateError(message);
        }
      }
      if (draftId == null) {
        final row = await db
            .from('pedigree_drafts')
            .insert({'ring_id': widget.ringId, 'data': data})
            .select('id')
            .single();
        draftId = row['id'];
      } else {
        await db
            .from('pedigree_drafts')
            .update({
              'data': data,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', draftId!);
      }
      dirty = false;
      if (finish) {
        await db.rpc('save_pedigree_draft', params: {'p_draft': draftId});
        if (mounted) Navigator.pop(context, true);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Draft saved. Reopen Enter full pedigree to continue.',
            ),
          ),
        );
      }
    } on StateError catch (e) {
      if (mounted) setState(() => error = e.message.toString());
    } on PostgrestException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Unable to save. Your entries are still here; please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _preview() async {
    if (!(form.currentState?.validate() ?? true)) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pedigree preview'),
        content: SizedBox(
          width: 1000,
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final generation in [
                    [0],
                    [1, 2],
                    [3, 4, 5, 6],
                    [7, 8, 9, 10, 11, 12, 13, 14],
                  ])
                    SizedBox(
                      width: 225,
                      child: Column(
                        children: [
                          for (final i in generation)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      PedigreeEntry.slots[i],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(label(entry.at(i))),
                                    if (entry.at(i) != null)
                                      Text(
                                        [
                                          varietyLabel(
                                            entry.nodes[entry.at(i)] ?? {},
                                          ),
                                          entry.nodes[entry.at(i)]?['dob'],
                                        ].whereType<String>().join(' • '),
                                      ),
                                    if ((entry.nodes[entry.at(
                                              i,
                                            )]?['leg_details'] ??
                                            '')
                                        .toString()
                                        .isNotEmpty)
                                      SelectableText(
                                        entry.nodes[entry.at(
                                          i,
                                        )]!['leg_details'],
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final key = entry.at(slot);
    final node = key == null ? null : entry.nodes[key];
    final parent = slot == 0 ? null : entry.at((slot - 1) ~/ 2);
    final editable =
        slot == 0 ||
        (parent != null && entry.nodes[parent]?['existing_id'] == null);
    final readOnly = node?['existing_id'] != null;
    final shared =
        key != null &&
        List.generate(15, (i) => entry.at(i)).where((k) => k == key).length > 1;
    return RingMasterPageShell(
      title: 'Enter full pedigree',
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : AbsorbPointer(
              absorbing: busy,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    'Enter your animal, then its sire’s family and dam’s family. Tab moves between fields. Unknown ancestors can stay blank.',
                  ),
                  if (drafts.isNotEmpty && draftId == null) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Resume a saved draft',
                      ),
                      items: drafts.map((d) {
                        final data = d['data'] as Map;
                        final root =
                            (data['nodes'] as Map)[data['root']] as Map;
                        return DropdownMenuItem<String>(
                          value: d['id'],
                          child: Text(
                            animalTitle(root['name'], root['tattoo']),
                          ),
                        );
                      }).toList(),
                      onChanged: (v) => setState(() {
                        final d = drafts.firstWhere((d) => d['id'] == v);
                        entry.restore(Map<String, dynamic>.from(d['data']));
                        draftId = v;
                        slot = 0;
                        _addExisting();
                      }),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final i in PedigreeEntry.order)
                        ChoiceChip(
                          label: Text(
                            '${entry.at(i) != null && entry.identified(entry.at(i)!) ? '✓ ' : ''}${PedigreeEntry.slots[i]}',
                          ),
                          selected: slot == i,
                          onSelected: (_) => _move(i),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    PedigreeEntry.slots[slot],
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (shared)
                    const Text(
                      'Repeated ancestor — changes here apply everywhere this animal appears in this pedigree.',
                    ),
                  if (slot == 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: DropdownButtonFormField<String>(
                        initialValue: entry.species,
                        decoration: const InputDecoration(labelText: 'Species'),
                        items: const [
                          DropdownMenuItem(
                            value: 'rabbit',
                            child: Text('Rabbit'),
                          ),
                          DropdownMenuItem(value: 'cavy', child: Text('Cavy')),
                        ],
                        onChanged: entry.data()['nodes'].length > 1
                            ? null
                            : (v) => setState(() {
                                entry.species = v!;
                                entry.lastBreed = '';
                                entry.lastVariety = '';
                                entry.nodes[entry.root]!.remove('breed');
                                entry.nodes[entry.root]!.remove('variety');
                                entry.nodes[entry.root]!.remove(
                                  'color_details',
                                );
                                for (final n in entry.nodes.values.where(
                                  (n) => n['existing_id'] == null,
                                )) {
                                  n['sex'] = sexLabel(v, n['sex'] ?? 'M');
                                }
                                _addExisting();
                                dirty = true;
                              }),
                      ),
                    ),
                  if (slot > 0 && editable)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Autocomplete<String>(
                        key: ValueKey('lookup:$slot:$key'),
                        displayStringForOption: label,
                        optionsBuilder: (text) => entry.nodes.keys.where(
                          (k) =>
                              k != entry.root &&
                              k != key &&
                              entry.identified(k) &&
                              entry.nodes[k]?['sex'] ==
                                  entry.expectedSex(slot) &&
                              (entry.nodes[k]?['species'] == null ||
                                  entry.nodes[k]?['species'] ==
                                      entry.species) &&
                              !entry.reaches(k, parent!) &&
                              label(
                                k,
                              ).toLowerCase().contains(text.text.toLowerCase()),
                        ),
                        onSelected: (k) => setState(() {
                          entry.link(slot, k);
                          dirty = true;
                        }),
                        fieldViewBuilder:
                            (context, controller, focus, onSubmit) => TextField(
                              controller: controller,
                              focusNode: focus,
                              decoration: const InputDecoration(
                                labelText:
                                    'Find existing or reuse an entered ancestor',
                                hintText: 'Type a name or ear number',
                                prefixIcon: Icon(Icons.search),
                              ),
                            ),
                      ),
                    ),
                  if (slot > 0 && !editable && node == null)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Enter this position’s parent first. An existing animal’s ancestry is managed from its own record.',
                      ),
                    ),
                  if (slot == 0 || node != null || editable) ...[
                    if (readOnly)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Using an existing animal and its saved ancestry. Its record will not be overwritten.',
                        ),
                      ),
                    Form(
                      key: form,
                      child: LayoutBuilder(
                        builder: (context, size) => Wrap(
                          spacing: 12,
                          runSpacing: 14,
                          children: [
                            for (final field in [
                              'name',
                              'tattoo',
                              'breed',
                              'variety',
                              'sex',
                              'dob',
                              'weight',
                              'registration_number',
                              'grand_champion_number',
                              'legs',
                              'leg_details',
                            ])
                              SizedBox(
                                width: size.maxWidth < 600
                                    ? size.maxWidth
                                    : (size.maxWidth - 24) / 3,
                                child: _field(field, key, node, readOnly),
                              ),
                          ],
                        ),
                      ),
                    ),
                    ColorDetailsFields(
                      key: ValueKey(
                        'details:$slot:$key:${node?['breed']}:${node?['variety']}',
                      ),
                      breed: node == null
                          ? entry.lastBreed
                          : node['breed'] ?? '',
                      variety: node == null
                          ? entry.lastVariety
                          : node['variety'] ?? '',
                      value: colorDetails(node ?? {}),
                      readOnly: readOnly,
                      onChanged: (v) => setState(() {
                        final k = key ?? entry.ensure(slot);
                        entry.nodes[k]!['color_details'] = v;
                        dirty = true;
                      }),
                    ),
                    if (slot > 0 && editable && node != null)
                      TextButton(
                        onPressed: () => setState(() {
                          entry.unlink(slot);
                          dirty = true;
                        }),
                        child: const Text('Clear this position / mark unknown'),
                      ),
                  ],
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton(
                        onPressed: slot == 0
                            ? null
                            : () => _move(
                                PedigreeEntry.order[PedigreeEntry.order.indexOf(
                                      slot,
                                    ) -
                                    1],
                              ),
                        child: const Text('Previous'),
                      ),
                      OutlinedButton(
                        onPressed: PedigreeEntry.order.last == slot
                            ? null
                            : () => _move(
                                PedigreeEntry.order[PedigreeEntry.order.indexOf(
                                      slot,
                                    ) +
                                    1],
                              ),
                        child: const Text('Next ancestor'),
                      ),
                      OutlinedButton(
                        onPressed: _preview,
                        child: const Text('Preview pedigree'),
                      ),
                      OutlinedButton(
                        onPressed: () => _save(false),
                        child: const Text('Save draft'),
                      ),
                      ElevatedButton(
                        onPressed: () => _save(true),
                        child: Text(
                          busy ? 'Saving…' : 'Save animal and pedigree',
                        ),
                      ),
                    ],
                  ),
                  if (dirty)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Unsaved changes — save a draft before leaving.',
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _field(
    String field,
    String? key,
    Map<String, dynamic>? node,
    bool readOnly,
  ) {
    node ??= entry.catalogDefaults;
    const labels = {
      'name': 'Name',
      'tattoo': 'Ear number / tag',
      'breed': 'Breed',
      'variety': 'Variety',
      'sex': 'Sex',
      'dob': 'DOB (MM/DD/YYYY)',
      'weight': 'Weight (decimal lb)',
      'registration_number': 'Registration number',
      'grand_champion_number': 'GC number',
      'legs': 'Legs',
      'leg_details': 'Legs / show details',
    };
    void change(String value) {
      final k = key ?? entry.ensure(slot);
      entry.nodes[k]![field] = value;
      entry.rememberCatalog(k, field, value);
      dirty = true;
    }

    if ((field == 'breed' || field == 'variety') && !readOnly) {
      return CatalogField(
        key: ValueKey(
          '$slot:$key:$field:${entry.species}:${field == 'variety' ? (node['breed']) : ''}',
        ),
        species: entry.species,
        breed: field == 'variety' ? (node['breed']?.toString() ?? '') : null,
        value: node[field]?.toString() ?? '',
        onChanged: (v) {
          change(v);
          setState(() {
            final k = key ?? entry.at(slot);
            if (k != null) {
              entry.nodes[k]!.remove('color_details');
              if (field == 'breed') entry.nodes[k]!.remove('variety');
            }
          });
        },
      );
    }
    if (field == 'sex') {
      return SexField(
        key: ValueKey('$slot:$key:sex:${entry.species}'),
        species: entry.species,
        value: node['sex'] ?? entry.expectedSex(slot),
        onChanged: slot == 0 && !readOnly ? change : null,
      );
    }
    if (field == 'dob') {
      return DobField(
        key: ValueKey('$slot:$key:dob'),
        value: node['dob']?.toString() ?? '',
        readOnly: readOnly,
        onChanged: change,
      );
    }
    final value = node[field]?.toString() ?? '';
    return TextFormField(
      key: ValueKey('$slot:$key:$field'),
      initialValue: value,
      readOnly: readOnly,
      decoration: InputDecoration(
        labelText: labels[field],
        hintText: field == 'leg_details'
            ? 'Type or paste results, one per line.'
            : null,
      ),
      minLines: field == 'leg_details' ? 4 : 1,
      maxLines: field == 'leg_details' ? 8 : 1,
      maxLength: field == 'leg_details' ? 4000 : null,
      keyboardType: field == 'leg_details' ? TextInputType.multiline : null,
      textInputAction: field == 'leg_details'
          ? TextInputAction.newline
          : TextInputAction.next,
      onChanged: change,
      validator: (v) {
        if (readOnly || v == null || v.trim().isEmpty) return null;
        if (field == 'weight' &&
            (double.tryParse(v) == null ||
                !double.parse(v).isFinite ||
                double.parse(v) <= 0)) {
          return 'Enter a positive weight';
        }
        if (field == 'legs' && (int.tryParse(v) == null || int.parse(v) < 0)) {
          return 'Enter a whole number';
        }
        return null;
      },
    );
  }
}
