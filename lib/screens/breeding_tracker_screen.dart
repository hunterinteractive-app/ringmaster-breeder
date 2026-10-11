import '../widgets/breeding_settings_dialog.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/animal_labels.dart';
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
  final client = Supabase.instance.client;
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
    final rows = await client
        .from('breeding_records')
        .select(
          '*, sire:animals!breeding_records_sire_id_fkey(*), dam:animals!breeding_records_dam_id_fkey!inner(*), tracking:breeding_tracking(*), offspring:breeding_offspring(*,animal:animals(name,tattoo,sex))',
        )
        .eq('dam.ring_id', widget.ringId)
        .order('breeding_date', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> edit(Map<String, dynamic> row) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LitterTrackingDialog(record: row),
    );
    if (saved == true && mounted) refresh();
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
    actions: [
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
      IconButton(
        onPressed: refresh,
        icon: const Icon(Icons.refresh),
        tooltip: 'Refresh',
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
        final rows = snapshot.data!
            .where(
              (r) =>
                  filter == 'All' ||
                  (filter == 'Active'
                      ? r['status'] == 'active'
                      : r['status'] != 'active'),
            )
            .toList();
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final f in ['Active', 'History', 'All'])
                  ChoiceChip(
                    label: Text(f),
                    selected: filter == f,
                    onSelected: (_) => setState(() => filter = f),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No breedings here yet. Use Actions → Record breeding in your Ring to start.',
                ),
              ),
            for (final r in rows) card(r),
          ],
        );
      },
    ),
  );
  Widget card(Map<String, dynamic> r) {
    final t = Map<String, dynamic>.from(r['tracking'] ?? {});
    final dam = r['dam'] as Map;
    final sire = r['sire'] as Map;
    final config = settings[dam['species']] ?? breedingDefaults(dam['species']);
    final youngName = dam['species'] == 'cavy' ? 'pups' : 'kits';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime.parse(r['breeding_date']);
    final elapsed = DateTime.utc(
      today.year,
      today.month,
      today.day,
    ).difference(DateTime.utc(start.year, start.month, start.day)).inDays;
    String window(DateTime base, int low, int high) {
      final first = breedingDate(breedingDay(base, low).toIso8601String());
      return low == high
          ? first
          : '$first – ${breedingDate(breedingDay(base, high).toIso8601String())}';
    }

    final children = (r['offspring'] as List? ?? []);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              animalTitle(dam['name'], dam['tattoo']),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text('Sire: ${animalTitle(sire['name'], sire['tattoo'])}'),
            Text(
              '${dam['breed'] ?? ''} • Bred ${breedingDate(r['breeding_date'])}',
            ),
            const SizedBox(height: 8),
            Chip(label: Text(breedingStage(r))),
            if (t['birth_date'] == null && r['status'] == 'active') ...[
              Text(
                elapsed < 0
                    ? 'Breeding scheduled in ${-elapsed} days'
                    : 'Day $elapsed since breeding',
              ),
              Text(
                'Expected birth: ${window(start, config['gestation_min'], config['gestation_max'])}',
              ),
              Text(
                'Palpation: ${window(start, config['palpation_min'], config['palpation_max'])}',
              ),
              if (config['nesting_day'] != null)
                Text(
                  'Nesting box: ${window(start, config['nesting_day'], config['nesting_day'])}',
                ),
              if (t['due_date'] != null)
                Text('Custom due date: ${breedingDate(t['due_date'])}'),
            ],
            Text(
              'Pregnancy check: ${t['check_result'] ?? 'Not checked'}${t['check_date'] == null ? '' : ' • ${breedingDate(t['check_date'])}'}',
            ),
            if (t['birth_date'] != null)
              Text(
                '${dam['species'] == 'cavy' ? 'Born' : 'Kindled'} ${breedingDate(t['birth_date'])} • ${t['born_alive']} alive • ${t['born_dead']} stillborn',
              ),
            if (t['birth_date'] != null && t['wean_date'] == null)
              Text(
                'Expected weaning: ${window(DateTime.parse(t['birth_date']), config['weaning_min'] * 7, config['weaning_max'] * 7)}',
              ),
            if (t['wean_date'] != null)
              Text(
                'Weaned ${breedingDate(t['wean_date'])} • ${t['weaned']} $youngName',
              ),
            if ((r['notes'] ?? '').toString().isNotEmpty)
              Text('Breeding notes: ${r['notes']}'),
            if ((t['notes'] ?? '').toString().isNotEmpty) Text(t['notes']),
            Wrap(
              spacing: 12,
              children: [
                TextButton.icon(
                  onPressed: () => edit(r),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Update tracking'),
                ),
                if ((t['weaned'] ?? 0) > 0 &&
                    children.isEmpty &&
                    r['status'] != 'cancelled')
                  TextButton.icon(
                    onPressed: () => offspring(r),
                    icon: const Icon(Icons.add),
                    label: const Text('Create offspring records'),
                  ),
              ],
            ),
            if (children.isNotEmpty) ...[
              Text(
                '${children.where((c) => animalIsMale(c['animal']?['sex'] ?? '')).length} ${dam['species'] == 'cavy' ? 'boars' : 'bucks'} • ${children.where((c) => !animalIsMale(c['animal']?['sex'] ?? '')).length} ${dam['species'] == 'cavy' ? 'sows' : 'does'}',
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final child in children)
                    ActionChip(
                      label: Text(
                        animalTitle(
                          child['animal']?['name'],
                          child['animal']?['tattoo'],
                        ),
                      ),
                      onPressed: () async {
                        await Navigator.pushNamed(
                          context,
                          '/animal-detail',
                          arguments: child['animal_id'],
                        );
                        if (mounted) refresh();
                      },
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
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
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
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
      problem = 'Enter birth details and the number weaned.';
    }
    if (wean == null && data['weaned'] != null) {
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
      problem = 'Enter the pregnancy check date.';
    }
    for (final key in ['due_date', 'check_date', 'birth_date', 'wean_date']) {
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
        await Supabase.instance.client.rpc(
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
  Widget count(String key, String label, {bool disabled = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextFormField(
      initialValue: data[key]?.toString(),
      enabled: !disabled,
      decoration: InputDecoration(labelText: label),
      keyboardType: TextInputType.number,
      onChanged: (v) => data[key] = int.tryParse(v),
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
    child: AlertDialog(
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
                  const Text(
                    'Estimated windows use your Ring’s breeding settings. You may also record a custom due date.',
                  ),
                  date('due_date', 'Custom due date (optional)', future: true),
                  date('check_date', 'Pregnancy check / palpation'),
                  DropdownButtonFormField<String>(
                    initialValue: data['check_result'],
                    decoration: const InputDecoration(
                      labelText: 'Check result',
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
                  const SizedBox(height: 16),
                  const Text(
                    'Birth & weaning',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  date(
                    'birth_date',
                    widget.record['dam']['species'] == 'cavy'
                        ? 'Birth date'
                        : 'Kindling date',
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
                  count('weaned', 'Number weaned', disabled: locked),
                  if (locked)
                    const Text(
                      'Offspring records are already linked. Edit individual animals from your herd.',
                    ),
                  const SizedBox(height: 12),
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
                  const SizedBox(height: 12),
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
          child: Text(saving ? 'Saving…' : 'Save tracking'),
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
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final dam = widget.record['dam'];
    final sire = widget.record['sire'];
    young = List.generate(
      widget.record['tracking']['weaned'],
      (_) => {
        'name': '',
        'tattoo': '',
        'sex': null,
        'breed': dam['breed'] == sire['breed'] ? dam['breed'] ?? '' : '',
        'variety': '',
      },
    );
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
      await Supabase.instance.client.rpc(
        'create_litter_animals',
        params: {'p_id': widget.record['id'], 'p_young': young},
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e is PostgrestException
              ? e.message
              : 'Unable to create records. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cavy = widget.record['dam']['species'] == 'cavy';
    return PopScope(
      canPop: !saving,
      child: AlertDialog(
        title: const Text('Create offspring records'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: AbsorbPointer(
              absorbing: saving,
              child: Form(
                key: form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Create ${young.length} ${cavy ? 'pups' : 'kits'} in your active herd. Birth date and both parents are filled from this litter. Review breed and enter each variety; leave unknown details blank.',
                    ),
                    for (var i = 0; i < young.length; i++)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            children: [
                              Text('Offspring ${i + 1}'),
                              for (final key in [
                                'name',
                                'tattoo',
                                'breed',
                                'variety',
                              ])
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: TextFormField(
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
            onPressed: saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: saving ? null : save,
            child: Text(
              saving ? 'Creating…' : 'Create ${young.length} animals',
            ),
          ),
        ],
      ),
    );
  }
}
