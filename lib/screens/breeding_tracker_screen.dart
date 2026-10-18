import '../widgets/adaptive_layout.dart';
import '../offline/offline_runtime.dart';
import '../services/pagination.dart';
import 'global_pedigree_history_screen.dart';
import '../utils/offspring_names.dart';
import '../widgets/catalog_field.dart';
import '../widgets/breeding_dashboard.dart';
import '../widgets/breeding_settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/ringmaster_page_shell.dart';

String breedingDate(dynamic value) => value == null
    ? 'Not recorded'
    : DateFormat('MM/dd/yyyy').format(DateTime.parse(value.toString()));
String breedingStage(Map<String, dynamic> row) {
  final t = (row['tracking'] as Map?) ?? {};
  if ((t['status'] ?? row['status']) == 'cancelled') return 'Cancelled';
  if ((t['status'] ?? row['status']) == 'completed') return 'Completed';
  if (t['wean_date'] != null) return 'Weaned';
  if (t['birth_date'] != null) return 'Nursing litter';
  return t['check_result'] == 'Positive'
      ? 'Confirmed pregnant'
      : 'Awaiting birth';
}

bool needsOffspring(Map<String, dynamic> row) {
  final t = (row['tracking'] as Map?) ?? {};
  return t['wean_date'] != null &&
      (t['weaned'] ?? 0) > 0 &&
      t['status'] != 'cancelled' &&
      ((row['offspring'] as List?) ?? []).isEmpty;
}

class BreedingTrackerScreen extends StatefulWidget {
  final String ringId;
  const BreedingTrackerScreen({super.key, required this.ringId});
  @override
  State<BreedingTrackerScreen> createState() => _BreedingTrackerScreenState();
}

class _BreedingTrackerScreenState extends State<BreedingTrackerScreen> {
  late Future<List<Map<String, dynamic>>> records;
  String filter = 'Active';
  Map<String, Map<String, dynamic>> settings = {};
  final client = OfflineRuntime.client;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() {
    setState(() => records = load());
  }

  Future<List<Map<String, dynamic>>> load() async {
    final savedSettings = await client
        .from('breeding_settings')
        .select()
        .eq('ring_id', widget.ringId);
    settings = {
      for (final row in savedSettings)
        row['species'] as String: Map<String, dynamic>.from(row),
    };
    final rows = await fetchAllPages(
      (from, to) => client
          .from('breeding_records')
          .select(
            '*, sire:animals!breeding_records_sire_id_fkey(*), dam:animals!breeding_records_dam_id_fkey!inner(*), tracking:breeding_tracking(*), offspring:breeding_offspring(*,animal:animals(name,tattoo,sex))',
          )
          .eq('dam.ring_id', widget.ringId)
          .order('breeding_date', ascending: false)
          .order('id')
          .range(from, to),
    );
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> edit(Map<String, dynamic> row) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LitterTrackingDialog(record: row),
    );
    if (saved != true || !mounted) return;
    refresh();
    try {
      final updated = (await records).firstWhere((r) => r['id'] == row['id']);
      if (mounted && needsOffspring(updated)) await offspring(updated);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Tracking saved. Refresh and choose Create offspring records to continue.',
            ),
          ),
        );
      }
    }
  }

  Future<void> offspring(Map<String, dynamic> row) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LitterOffspringDialog(record: row),
    );
    if (saved == true && mounted) refresh();
  }

  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    title: 'Breedings & litters',
    onRefresh: refresh,
    actions: [
      IconButton(
        tooltip: 'Imported litter & breeding history',
        icon: const Icon(Icons.history),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => GlobalPedigreeHistoryScreen(ringId: widget.ringId),
          ),
        ),
      ),
      IconButton(
        tooltip: 'Breeding settings',
        icon: const Icon(Icons.settings_outlined),
        onPressed: () async {
          try {
            await records;
          } catch (_) {
            return;
          }
          if (!context.mounted) return;
          final saved = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => BreedingSettingsDialog(
              ringId: widget.ringId,
              settings: settings,
            ),
          );
          if (saved == true && mounted) refresh();
        },
      ),
    ],
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: records,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Unable to load breedings.'),
                TextButton(onPressed: refresh, child: const Text('Try again')),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return BreedingDashboard(
          records: snapshot.data!,
          settings: settings,
          filter: filter,
          onFilter: (v) => setState(() => filter = v),
          onEdit: edit,
          onOffspring: offspring,
          onOpen: (id) async {
            await Navigator.pushNamed(context, '/animal-detail', arguments: id);
            if (mounted) refresh();
          },
        );
      },
    ),
  );
}

class LitterTrackingDialog extends StatefulWidget {
  final Map<String, dynamic> record;
  final Future<void> Function(Map<String, dynamic>)? writer;
  const LitterTrackingDialog({super.key, required this.record, this.writer});
  @override
  State<LitterTrackingDialog> createState() => _LitterTrackingDialogState();
}

class _LitterTrackingDialogState extends State<LitterTrackingDialog> {
  late Map<String, dynamic> data;
  final form = GlobalKey<FormState>();
  bool saving = false;
  String? error;
  bool get locked => (widget.record['offspring'] as List? ?? []).isNotEmpty;
  @override
  void initState() {
    super.initState();
    data = {
      'due_date': null,
      'check_result': 'Not checked',
      'status': widget.record['status'],
      'notes': '',
      ...Map<String, dynamic>.from(widget.record['tracking'] ?? {}),
    };
    if (locked && data['weaned_males'] == null) {
      final children = widget.record['offspring'] as List;
      data['weaned_males'] = children
          .where((c) => ['M', 'Buck', 'Boar'].contains(c['animal']?['sex']))
          .length;
      data['weaned_females'] = children.length - data['weaned_males'];
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    data['weaned'] =
        data['weaned_males'] == null || data['weaned_females'] == null
        ? null
        : data['weaned_males'] + data['weaned_females'];
    final birth = data['birth_date'];
    final wean = data['wean_date'];
    String? problem;
    if (birth != null &&
        (data['born_alive'] == null || data['born_dead'] == null)) {
      problem = 'Enter alive and stillborn counts (use 0 when none).';
    }
    if (birth == null &&
        (data['born_alive'] != null || data['born_dead'] != null)) {
      problem = 'Enter the birth date.';
    }
    if (wean != null && (birth == null || data['weaned'] == null)) {
      problem =
          'Enter birth details and both weaning sex counts (use 0 when none).';
    }
    if (wean == null &&
        (data['weaned_males'] != null || data['weaned_females'] != null)) {
      problem = 'Enter the weaning date.';
    }
    if (wean != null &&
        birth != null &&
        wean.toString().compareTo(birth.toString()) < 0) {
      problem = 'Weaning cannot be before birth.';
    }
    if ((data['weaned'] ?? 0) > (data['born_alive'] ?? 0)) {
      problem = 'Number weaned cannot exceed number born alive.';
    }
    if (data['check_result'] != 'Not checked' && data['check_date'] == null) {
      problem = 'Enter the palpation date.';
    }
    for (final key in ['check_date', 'birth_date', 'wean_date']) {
      if (data[key] != null &&
          data[key].toString().compareTo(widget.record['breeding_date']) < 0) {
        problem = 'Dates cannot be before the breeding date.';
      }
    }
    if (problem != null) {
      setState(() => error = problem);
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (widget.writer != null) {
        await widget.writer!(data);
      } else {
        await OfflineRuntime.client.rpc(
          'save_breeding_tracking',
          params: {
            'p_id': widget.record['id'],
            'p_data': data,
            'p_revision': widget.record['tracking']?['revision'] ?? 0,
          },
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e is PostgrestException
              ? e.message
              : 'Unable to save. Try again.';
        });
      }
    }
  }

  Widget date(
    String key,
    String label, {
    bool future = false,
    bool disabled = false,
  }) => Row(
    children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: disabled
              ? null
              : () async {
                  final now = DateTime.now();
                  final initial = DateTime.tryParse(data[key] ?? '') ?? now;
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: !future && initial.isAfter(now)
                        ? now
                        : initial,
                    firstDate: DateTime(1900),
                    lastDate: future ? DateTime(now.year + 5) : now,
                  );
                  if (picked != null && mounted) {
                    setState(
                      () => data[key] = DateFormat('yyyy-MM-dd').format(picked),
                    );
                  }
                },
          icon: const Icon(Icons.calendar_month),
          label: Text('$label: ${breedingDate(data[key])}'),
        ),
      ),
      if (data[key] != null && !disabled)
        IconButton(
          tooltip: 'Clear $label',
          onPressed: () => setState(() => data[key] = null),
          icon: const Icon(Icons.clear),
        ),
    ],
  );
  Widget count(String key, String label, {bool disabled = false}) =>
      AdaptivePadding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextFormField(
          initialValue: data[key]?.toString(),
          enabled: !disabled,
          decoration: InputDecoration(labelText: label),
          keyboardType: TextInputType.number,
          onChanged: (v) => setState(() => data[key] = int.tryParse(v)),
          validator: (v) =>
              v == null ||
                  v.isEmpty ||
                  (int.tryParse(v) != null &&
                      int.parse(v) >= 0 &&
                      int.parse(v) <= 100)
              ? null
              : 'Enter a whole number from 0 to 100',
        ),
      );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AdaptiveFormDialog(
      title: const Text('Gestation & litter tracking'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: AbsorbPointer(
            absorbing: saving,
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Gestation',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Text('Estimated windows use your breeding settings.'),
                  date('check_date', 'Palpation date'),
                  DropdownButtonFormField<String>(
                    initialValue: data['check_result'],
                    decoration: const InputDecoration(
                      labelText: 'Palpation result',
                    ),
                    items: [
                      for (final s in [
                        'Not checked',
                        'Positive',
                        'Negative',
                        'Uncertain',
                      ])
                        DropdownMenuItem(value: s, child: Text(s)),
                    ],
                    onChanged: (v) => data['check_result'] = v,
                  ),
                  const AdaptiveGap(height: 16),
                  const Text(
                    'Birth & weaning',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  date(
                    'birth_date',
                    widget.record['dam']['species'] == 'cavy'
                        ? 'Date born'
                        : 'Date kindled',
                    disabled: locked,
                  ),
                  count(
                    'born_alive',
                    widget.record['dam']['species'] == 'cavy'
                        ? 'Pups born alive'
                        : 'Kits born alive',
                  ),
                  count('born_dead', 'Stillborn'),
                  date('wean_date', 'Weaning date', disabled: locked),
                  count(
                    'weaned_males',
                    widget.record['dam']['species'] == 'cavy'
                        ? 'Number of boars'
                        : 'Number of bucks',
                    disabled: locked,
                  ),
                  count(
                    'weaned_females',
                    widget.record['dam']['species'] == 'cavy'
                        ? 'Number of sows'
                        : 'Number of does',
                    disabled: locked,
                  ),
                  if (locked)
                    const Text(
                      'Offspring records are already linked. Edit individual animals from your herd.',
                    ),
                  const AdaptiveGap(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: data['status'],
                    decoration: const InputDecoration(
                      labelText: 'Breeding status',
                    ),
                    items: [
                      for (final s in ['active', 'completed', 'cancelled'])
                        DropdownMenuItem(
                          value: s,
                          child: Text(s[0].toUpperCase() + s.substring(1)),
                        ),
                    ],
                    onChanged: (v) => data['status'] = v,
                  ),
                  const AdaptiveGap(height: 12),
                  TextFormField(
                    initialValue: data['notes'],
                    maxLength: 4000,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Tracking notes',
                    ),
                    onChanged: (v) => data['notes'] = v,
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
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
            saving
                ? 'Saving…'
                : needsOffspring({
                    ...widget.record,
                    'tracking': {
                      ...data,
                      'weaned':
                          (data['weaned_males'] ?? 0) +
                          (data['weaned_females'] ?? 0),
                    },
                  })
                ? 'Save tracking and create offspring records'
                : 'Save tracking',
          ),
        ),
      ],
    ),
  );
}

class LitterOffspringDialog extends StatefulWidget {
  final Map<String, dynamic> record;
  const LitterOffspringDialog({super.key, required this.record});
  @override
  State<LitterOffspringDialog> createState() => _LitterOffspringDialogState();
}

class _LitterOffspringDialogState extends State<LitterOffspringDialog> {
  late List<Map<String, dynamic>> young;
  final form = GlobalKey<FormState>();
  bool saving = false, generating = false;
  int generation = 0;
  bool get busy => saving || generating;
  String? error;
  @override
  void initState() {
    super.initState();
    final dam = widget.record['dam'];
    final sire = widget.record['sire'];
    young = List.generate(
      widget.record['tracking']['weaned'],
      (i) => {
        'name': '',
        'tattoo': '',
        'sex': widget.record['tracking']['weaned_males'] == null
            ? null
            : (i < widget.record['tracking']['weaned_males'] ? 'M' : 'F'),
        'breed': dam['breed'] == sire['breed'] ? dam['breed'] ?? '' : '',
        'variety': '',
      },
    );
  }

  Future<List<Map<String, dynamic>>> herdAnimals() async {
    final rows = <Map<String, dynamic>>[];
    for (var offset = 0; ; offset += 500) {
      final page = await OfflineRuntime.client
          .from('animals')
          .select('name,tattoo')
          .eq('ring_id', widget.record['dam']['ring_id'])
          .order('id')
          .range(offset, offset + 499);
      rows.addAll(page);
      if (page.length < 500) return rows;
    }
  }

  Future<void> generate() async {
    setState(() {
      generating = true;
      error = null;
    });
    try {
      final herd = await herdAnimals();
      if (!mounted) return;
      setState(() {
        young = generateOffspringNames(young, herd);
        generation++;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Unable to check existing tattoos. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => generating = false);
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    final ears = young
        .map((y) => y['tattoo'].toString().trim().toLowerCase())
        .toSet();
    if (ears.length != young.length) {
      setState(() => error = 'Each offspring needs a different ear number.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final existing = (await herdAnimals())
          .map((a) => normalizedTattoo(a['tattoo']))
          .toSet();
      final duplicates = young
          .where((a) => existing.contains(normalizedTattoo(a['tattoo'])))
          .map((a) => a['tattoo'])
          .join(', ');
      if (duplicates.isNotEmpty) {
        if (mounted) {
          setState(() {
            saving = false;
            error =
                'Already used in this herd: $duplicates. Choose different ear numbers.';
          });
        }
        return;
      }
      await OfflineRuntime.client.rpc(
        'create_litter_animals',
        params: {'p_id': widget.record['id'], 'p_young': young},
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e is PostgrestException
              ? (e.code == '23505'
                    ? 'An ear number is already used in this herd. Choose a different one and try again.'
                    : e.message)
              : 'Unable to create records. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cavy = widget.record['dam']['species'] == 'cavy';
    return PopScope(
      canPop: !busy,
      child: AdaptiveFormDialog(
        title: const Text('Create offspring records'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: AbsorbPointer(
              absorbing: busy,
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Create ${young.length} ${cavy ? 'pups' : 'kits'} in your active herd. Birth date and both parents are filled from this litter. Review breed and enter each variety; leave unknown details blank.',
                    ),
                    const AdaptiveGap(height: 16),
                    OutlinedButton.icon(
                      onPressed: busy ? null : generate,
                      icon: const Icon(Icons.auto_awesome),
                      label: Text(
                        generating ? 'Generating…' : 'Generate names & tattoos',
                      ),
                    ),
                    const Text(
                      'Fills empty fields only. Tattoos are checked against every animal in this herd. You can edit the suggestions.',
                    ),
                    for (var i = 0; i < young.length; i++)
                      Card(
                        child: AdaptivePadding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              Text('Offspring ${i + 1}'),
                              for (final key in ['name', 'tattoo'])
                                AdaptivePadding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: TextFormField(
                                    key: ValueKey(
                                      'offspring-$generation-$i-$key',
                                    ),
                                    initialValue: young[i][key],
                                    decoration: InputDecoration(
                                      labelText: {
                                        'name': 'Name (optional)',
                                        'tattoo': 'Ear number / tag',
                                        'breed': 'Breed',
                                        'variety': 'Variety',
                                      }[key],
                                    ),
                                    onChanged: (v) => young[i][key] = v.trim(),
                                    validator: (v) =>
                                        key == 'tattoo' &&
                                            (v ?? '').trim().isEmpty
                                        ? 'Enter an ear number'
                                        : null,
                                  ),
                                ),
                              const AdaptiveGap(height: 16),
                              CatalogField(
                                species: widget.record['dam']['species'],
                                value: young[i]['breed'] ?? '',
                                onChanged: (v) => setState(() {
                                  young[i]['breed'] = v;
                                  young[i]['variety'] = '';
                                }),
                              ),
                              const AdaptiveGap(height: 16),
                              CatalogField(
                                key: ValueKey(
                                  'variety-$i-${young[i]['breed']}',
                                ),
                                species: widget.record['dam']['species'],
                                breed: young[i]['breed'] ?? '',
                                value: young[i]['variety'] ?? '',
                                onChanged: (v) => young[i]['variety'] = v,
                              ),
                              const AdaptiveGap(height: 16),
                              DropdownButtonFormField<String>(
                                initialValue: young[i]['sex'],
                                validator: (v) =>
                                    v == null ? 'Choose the sex' : null,
                                decoration: const InputDecoration(
                                  labelText: 'Sex',
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: 'M',
                                    child: Text(cavy ? 'Boar' : 'Buck'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'F',
                                    child: Text(cavy ? 'Sow' : 'Doe'),
                                  ),
                                ],
                                onChanged: (v) => young[i]['sex'] = v,
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (error != null)
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(
              saving ? 'Creating…' : 'Create ${young.length} animals',
            ),
          ),
        ],
      ),
    );
  }
}
