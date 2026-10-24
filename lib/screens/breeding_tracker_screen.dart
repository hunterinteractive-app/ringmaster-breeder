import '../widgets/link_litter_offspring_dialog.dart';
import 'rabbit_register_history_screen.dart';
import '../widgets/adaptive_layout.dart';
import '../offline/offline_runtime.dart';
import '../services/pagination.dart';
import '../services/grow_out_service.dart';
import '../widgets/grow_out_dashboard.dart';
import 'production_measurements_screen.dart';
import 'global_pedigree_history_screen.dart';
import '../utils/offspring_names.dart';
import '../utils/litter_lifecycle.dart';
export '../utils/litter_lifecycle.dart' show breedingStage, needsOffspring;
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

class BreedingTrackerScreen extends StatefulWidget {
  final String ringId;
  final bool growOut;
  const BreedingTrackerScreen({
    super.key,
    required this.ringId,
    this.growOut = false,
  });
  @override
  State<BreedingTrackerScreen> createState() => _BreedingTrackerScreenState();
}

class _BreedingData {
  final List<Map<String, dynamic>> rows, measurements;
  final Map<String, Map<String, dynamic>> settings;
  _BreedingData(this.rows, this.settings, this.measurements);
}

class _BreedingTrackerScreenState extends State<BreedingTrackerScreen> {
  late Future<_BreedingData> records;
  String filter = 'Active';
  final client = OfflineRuntime.client;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() {
    setState(() {
      records = load();
    });
  }

  Future<_BreedingData> load() async {
    final savedSettings = await client
        .from('breeding_settings')
        .select()
        .eq('ring_id', widget.ringId);
    final settings = <String, Map<String, dynamic>>{
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
    final measurements = widget.growOut
        ? await loadGrowOutMeasurements(rows)
        : <Map<String, dynamic>>[];
    return _BreedingData(rows, settings, measurements);
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
      final updated = (await records).rows.firstWhere(
        (r) => r['id'] == row['id'],
      );
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

  Future<void> measurements(Map<String, dynamic> row) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            ProductionMeasurementsScreen(recordId: row['id'], growOut: true),
      ),
    );
    if (mounted) refresh();
  }

  Future<void> offspring(Map<String, dynamic> row) async {
    if (row['import_source'] != null) {
      final t = row['tracking'] as Map? ?? {};
      final canCreate =
          row['sire'] != null &&
          t['birth_date'] != null &&
          t['wean_date'] != null &&
          (t['weaned'] ?? 0) > (row['offspring'] as List? ?? []).length;
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Manage imported litter offspring'),
          content: const Text(
            'Link rabbits that were already imported before creating any missing offspring. New records require the sire, birth date, weaning date and weaned count.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'link'),
              child: const Text('Link existing rabbits'),
            ),
            FilledButton(
              onPressed: canCreate ? () => Navigator.pop(ctx, 'new') : null,
              child: const Text('Create missing offspring'),
            ),
          ],
        ),
      );
      if (choice == null || !mounted) return;
      if (choice == 'link') {
        try {
          final candidates = await fetchAllPages(
            (from, to) => client
                .from('animals')
                .select('id,name,tattoo,sex,dob,sire_id')
                .eq('ring_id', row['dam']['ring_id'])
                .eq('dam_id', row['dam_id'])
                .order('id')
                .range(from, to),
          );
          final matching = candidates
              .where(
                (a) =>
                    (row['sire_id'] == null ||
                        a['sire_id'] == row['sire_id']) &&
                    (t['birth_date'] == null ||
                        a['dob'] == null ||
                        a['dob'] == t['birth_date']),
              )
              .toList();
          if (!mounted) return;
          final saved = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => LinkLitterOffspringDialog(
              animals: matching,
              linked: {
                for (final a in row['offspring'] as List? ?? [])
                  a['animal_id'] as String,
              },
              limit: t['weaned'] as int?,
              writer: (ids) async {
                await client.rpc(
                  'link_litter_offspring',
                  params: {'p_id': row['id'], 'p_animals': ids},
                );
              },
            ),
          );
          if (saved == true && mounted) refresh();
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Unable to load offspring. Reconnect and retry.'),
              ),
            );
          }
        }
        return;
      }
    }
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LitterOffspringDialog(record: row),
    );
    if (saved == true && mounted) refresh();
  }

  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    title: widget.growOut ? 'Grow-out dashboard' : 'Breedings & litters',
    onRefresh: refresh,
    actions: [
      IconButton(
        tooltip: widget.growOut ? 'Breedings & litters' : 'Grow-out dashboard',
        icon: Icon(widget.growOut ? Icons.child_care : Icons.grass_outlined),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => BreedingTrackerScreen(
                ringId: widget.ringId,
                growOut: !widget.growOut,
              ),
            ),
          );
          if (mounted) refresh();
        },
      ),
      IconButton(
        tooltip: 'Rabbit Register litter history',
        icon: const Icon(Icons.inventory_2_outlined),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RabbitRegisterHistoryScreen(ringId: widget.ringId),
          ),
        ),
      ),
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
          late final _BreedingData loaded;
          try {
            loaded = await records;
          } catch (_) {
            return;
          }
          if (!context.mounted) return;
          final saved = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => BreedingSettingsDialog(
              ringId: widget.ringId,
              settings: loaded.settings,
            ),
          );
          if (saved == true && mounted) refresh();
        },
      ),
    ],
    body: FutureBuilder<_BreedingData>(
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
        if (widget.growOut) {
          return GrowOutDashboard(
            records: snapshot.data!.rows,
            measurements: snapshot.data!.measurements,
            onMeasurements: measurements,
            onOffspring: offspring,
            onEdit: edit,
          );
        }
        return BreedingDashboard(
          records: snapshot.data!.rows,
          settings: snapshot.data!.settings,
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
      'actual_breeding_date': widget.record['breeding_date'],
      'custom_fields': <String, dynamic>{},
      'due_date': null,
      'check_result': 'Not checked',
      'status': widget.record['status'],
      'weaning_destination': 'individual',
      'notes': '',
      ...Map<String, dynamic>.from(widget.record['tracking'] ?? {}),
    };
    if (locked &&
        data['weaned_males'] == null &&
        (widget.record['offspring'] as List).length == data['weaned']) {
      final children = widget.record['offspring'] as List;
      data['weaned_males'] = children
          .where((c) => ['M', 'Buck', 'Boar'].contains(c['animal']?['sex']))
          .length;
      data['weaned_females'] = children.length - data['weaned_males'];
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    final imported = widget.record['import_source'] != null;
    if (!imported ||
        data['weaned_males'] != null ||
        data['weaned_females'] != null) {
      data['weaned'] =
          data['weaned_males'] == null || data['weaned_females'] == null
          ? null
          : data['weaned_males'] + data['weaned_females'];
    }
    final birth = data['birth_date'];
    final wean = data['wean_date'];
    String? problem;
    if (data['weaning_destination'] == 'grow_out' &&
        (birth == null || wean == null || (data['weaned'] ?? 0) == 0)) {
      problem = 'Record birth, weaning date and a positive count for grow out.';
    }
    if ((data['weaned_males'] == null) != (data['weaned_females'] == null)) {
      problem = 'Enter both sex counts, or leave both unknown.';
    }
    if (!imported &&
        birth != null &&
        (data['born_alive'] == null || data['born_dead'] == null)) {
      problem = 'Enter alive and stillborn counts (use 0 when none).';
    }
    if (!imported &&
        birth == null &&
        (data['born_alive'] != null || data['born_dead'] != null)) {
      problem = 'Enter the birth date.';
    }
    if (!imported &&
        wean != null &&
        (birth == null || data['weaned'] == null)) {
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
    if (data['weaned'] != null &&
        (data['born_alive'] ?? data['born_total']) != null &&
        data['weaned'] >
            (data['born_alive'] ?? data['born_total']) + (data['added'] ?? 0)) {
      problem = (data['added'] ?? 0) == 0
          ? 'Number weaned cannot exceed number born alive.'
          : 'Number weaned cannot exceed born plus added.';
    }
    if (!imported &&
        data['check_result'] != 'Not checked' &&
        data['check_date'] == null) {
      problem = 'Enter the palpation date.';
    }
    for (final key in ['check_date', 'birth_date', 'wean_date']) {
      if (data[key] != null &&
          data['actual_breeding_date'] != null &&
          data[key].toString().compareTo(data['actual_breeding_date']) < 0) {
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
  Widget flag(String key, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: DropdownButtonFormField<String>(
      initialValue: data[key] == null
          ? 'unknown'
          : data[key] == true
          ? 'yes'
          : 'no',
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: const [
        DropdownMenuItem(value: 'unknown', child: Text('Not recorded')),
        DropdownMenuItem(value: 'yes', child: Text('Yes')),
        DropdownMenuItem(value: 'no', child: Text('No')),
      ],
      onChanged: (v) =>
          setState(() => data[key] = v == 'unknown' ? null : v == 'yes'),
    ),
  );
  Widget textValue(String key, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: TextFormField(
      initialValue: data[key]?.toString() ?? '',
      decoration: InputDecoration(labelText: label),
      maxLength: 100,
      onChanged: (v) => data[key] = v,
    ),
  );
  Widget extraDetails() => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: const Text('Additional litter details'),
    maintainState: true,
    children: [
      date('paired_date', 'Paired'),
      date('split_date', 'Separated / split'),
      date('scheduled_breeding_date', 'Scheduled rebreeding', future: true),
      flag('rebreeding_enabled', 'Rebreeding enabled'),
      flag('rebreeding_overridden', 'Rebreeding schedule overridden'),
      textValue('cage', 'Litter cage / housing'),
      textValue('breed_label', 'Litter breed'),
      const Text(
        'Litter totals',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      const Text(
        'Keep source totals separate from born-alive, stillborn and weaning counts. Added animals can increase the number weaned.',
      ),
      count('born_total', 'Total born'),
      count('recorded_deaths', 'Total deaths'),
      count('added', 'Added / fostered in'),
      count('raised', 'Raised'),
      count('bucks', 'Bucks in litter'),
      count('does', 'Does in litter'),
      count('kept', 'Kept'),
      count('sold', 'Sold'),
      count('show_quality', 'Show quality'),
      for (final e in (data['custom_fields'] as Map? ?? {}).entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: TextFormField(
            initialValue: e.value.toString(),
            decoration: InputDecoration(labelText: e.key.toString()),
            onChanged: (v) => data['custom_fields'] = {
              ...data['custom_fields'] as Map,
              e.key: v,
            },
          ),
        ),
      const SizedBox(height: 12),
    ],
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
                  date(
                    'actual_breeding_date',
                    'Date bred',
                    future: data['breeding_occurred'] == false,
                  ),
                  flag('breeding_occurred', 'Breeding occurred'),
                  date('check_date', 'Palpation date'),
                  if (data['palpation_source'] != null)
                    Text(
                      'Previous palpation result: ${data['palpation_source']}',
                    ),
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
                  if (widget.record['dam']['species'] != 'cavy') ...[
                    flag('nest_installed', 'Nest box installed'),
                    flag('nest_removed', 'Nest box removed'),
                  ],
                  const Text(
                    'Birth & weaning',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  date(
                    'birth_date',
                    widget.record['dam']['species'] == 'cavy'
                        ? 'Date born'
                        : 'Date kindled',
                    disabled:
                        locked &&
                        widget.record['tracking']?['birth_date'] != null,
                  ),
                  count(
                    'born_alive',
                    widget.record['dam']['species'] == 'cavy'
                        ? 'Pups born alive'
                        : 'Kits born alive',
                  ),
                  count('born_dead', 'Stillborn'),
                  date(
                    'wean_date',
                    'Weaning date',
                    disabled:
                        locked &&
                        widget.record['tracking']?['wean_date'] != null,
                  ),
                  count(
                    'weaned_males',
                    widget.record['dam']['species'] == 'cavy'
                        ? 'Number of boars'
                        : 'Number of bucks',
                    disabled:
                        locked &&
                        widget.record['tracking']?['weaned_males'] != null,
                  ),
                  count(
                    'weaned_females',
                    widget.record['dam']['species'] == 'cavy'
                        ? 'Number of sows'
                        : 'Number of does',
                    disabled:
                        locked &&
                        widget.record['tracking']?['weaned_females'] != null,
                  ),
                  const AdaptiveGap(height: 12),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('weaning-destination'),
                    initialValue: data['weaning_destination'],
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'After weaning',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'individual',
                        child: Text('Individual records'),
                      ),
                      DropdownMenuItem(
                        value: 'grow_out',
                        child: Text('Grow out'),
                      ),
                    ],
                    onChanged: (v) => setState(() {
                      data['weaning_destination'] = v;
                      if (v == 'grow_out' &&
                          data['status'] == 'completed' &&
                          litterUnrecordedCount({
                                ...widget.record,
                                'tracking': data,
                              }) >
                              0) {
                        data['status'] = 'active';
                      }
                    }),
                  ),
                  Text(
                    data['weaning_destination'] == 'grow_out'
                        ? 'Keep unrecorded youngsters together as a grow-out litter. You can give selected animals their own records later.'
                        : 'Create a separate herd record for each weaned animal.',
                  ),
                  if (locked)
                    const Text(
                      'Existing dates and totals stay locked after linking offspring. You can fill missing historical details.',
                    ),
                  const AdaptiveGap(height: 12),
                  extraDetails(),
                  const AdaptiveGap(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey('breeding-status-${data['status']}'),
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
                    minLines: BreederLayout.fieldLines(context, 2),
                    maxLines: BreederLayout.fieldLines(context, 4),
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      counterText: BreederLayout.shortViewport(context)
                          ? ''
                          : null,
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
  final Future<void> Function(List<Map<String, dynamic>>)? writer;
  final Future<List<Map<String, dynamic>>> Function()? herdReader;
  const LitterOffspringDialog({
    super.key,
    required this.record,
    this.writer,
    this.herdReader,
  });
  @override
  State<LitterOffspringDialog> createState() => _LitterOffspringDialogState();
}

class _LitterOffspringDialogState extends State<LitterOffspringDialog> {
  late List<Map<String, dynamic>> young;
  late List<bool> selected;
  bool get growOut =>
      widget.record['tracking']['weaning_destination'] == 'grow_out';
  List<Map<String, dynamic>> get chosen => [
    for (var i = 0; i < young.length; i++)
      if (selected[i]) young[i],
  ];
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
    selected = List.filled(litterUnrecordedCount(widget.record), !growOut);
    young = List.generate(
      (widget.record['tracking']['weaned'] as int) -
          (widget.record['offspring'] as List? ?? []).length,
      (i) => {
        'name': '',
        'tattoo': '',
        'sex': widget.record['tracking']['weaned_males'] == null
            ? null
            : (i <
                      (widget.record['tracking']['weaned_males'] as int) -
                          (widget.record['offspring'] as List? ?? [])
                              .where(
                                (a) => [
                                  'M',
                                  'Buck',
                                  'Boar',
                                ].contains(a['animal']?['sex']),
                              )
                              .length
                  ? 'M'
                  : 'F'),
        'breed': dam['breed'] == sire?['breed'] ? dam['breed'] ?? '' : '',
        'variety': '',
      },
    );
  }

  Future<List<Map<String, dynamic>>> herdAnimals() async {
    if (widget.herdReader != null) return widget.herdReader!();
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
        final generated = generateOffspringNames(chosen, herd);
        var index = 0;
        for (var i = 0; i < young.length; i++) {
          if (selected[i]) young[i] = generated[index++];
        }
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
    final offspring = chosen;
    if (offspring.isEmpty) {
      setState(() => error = 'Select at least one animal for its own record.');
      return;
    }
    if (!form.currentState!.validate()) return;
    final ears = offspring
        .map((y) => y['tattoo'].toString().trim().toLowerCase())
        .toSet();
    if (ears.length != offspring.length) {
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
      final duplicates = offspring
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
      if (widget.writer != null) {
        await widget.writer!(offspring);
      } else {
        await OfflineRuntime.client.rpc(
          'create_litter_animals',
          params: {'p_id': widget.record['id'], 'p_young': offspring},
        );
      }
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
                      growOut
                          ? 'Choose youngsters for individual records. ${young.length - chosen.length} will remain in grow out. Birth date and parents are filled from this litter.'
                          : 'Create ${young.length} ${cavy ? 'pups' : 'kits'} in your active herd. Birth date and both parents are filled from this litter. Review breed and enter each variety; leave unknown details blank.',
                    ),
                    const AdaptiveGap(height: 16),
                    OutlinedButton.icon(
                      onPressed: busy || chosen.isEmpty ? null : generate,
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
                              if (growOut)
                                CheckboxListTile(
                                  key: ValueKey('offspring-select-$i'),
                                  contentPadding: EdgeInsets.zero,
                                  title: Text('Offspring ${i + 1}'),
                                  subtitle: const Text(
                                    'Create individual record',
                                  ),
                                  value: selected[i],
                                  onChanged: (v) =>
                                      setState(() => selected[i] = v ?? false),
                                )
                              else
                                Text('Offspring ${i + 1}'),
                              if (selected[i]) ...[
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
                                      onChanged: (v) =>
                                          young[i][key] = v.trim(),
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
              saving
                  ? 'Creating…'
                  : 'Create ${chosen.length} ${chosen.length == 1 ? 'animal' : 'animals'}',
            ),
          ),
        ],
      ),
    );
  }
}
