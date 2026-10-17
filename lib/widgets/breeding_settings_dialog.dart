import '../offline/offline_runtime.dart';
import 'package:flutter/material.dart';

Map<String, dynamic> breedingDefaults(String species) => {
  'species': species,
  'gestation_min': species == 'cavy' ? 59 : 28,
  'gestation_max': species == 'cavy' ? 72 : 32,
  'palpation_min': species == 'cavy' ? 28 : 14,
  'palpation_max': species == 'cavy' ? 30 : 14,
  'nesting_day': species == 'cavy' ? null : 26,
  'weaning_min': species == 'cavy' ? 3 : 4,
  'weaning_max': species == 'cavy' ? 4 : 8,
};
DateTime breedingDay(DateTime start, int days) =>
    DateTime(start.year, start.month, start.day + days);

class BreedingSettingsDialog extends StatefulWidget {
  final String ringId;
  final Map<String, Map<String, dynamic>> settings;
  final Future<void> Function(List<Map<String, dynamic>>)? writer;
  const BreedingSettingsDialog({
    super.key,
    required this.ringId,
    required this.settings,
    this.writer,
  });
  @override
  State<BreedingSettingsDialog> createState() => _BreedingSettingsDialogState();
}

class _BreedingSettingsDialogState extends State<BreedingSettingsDialog> {
  final form = GlobalKey<FormState>();
  late Map<String, Map<String, dynamic>> values;
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    values = {
      for (final s in ['rabbit', 'cavy'])
        s: {...breedingDefaults(s), ...?widget.settings[s]},
    };
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    for (final v in values.values) {
      for (final p in ['gestation', 'palpation', 'weaning']) {
        if (v['${p}_min'] > v['${p}_max']) {
          setState(
            () =>
                error = 'The end of each window must be on or after its start.',
          );
          return;
        }
      }
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final rows = values.values
          .map((v) => {...v, 'ring_id': widget.ringId})
          .toList();
      if (widget.writer != null) {
        await widget.writer!(rows);
      } else {
        await OfflineRuntime.client
            .from('breeding_settings')
            .upsert(rows, onConflict: 'ring_id,species');
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'Unable to save settings. Please try again.';
        });
      }
    }
  }

  Widget field(
    String species,
    String key,
    String label, {
    bool weeks = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextFormField(
      initialValue: values[species]![key]?.toString(),
      decoration: InputDecoration(labelText: label),
      keyboardType: TextInputType.number,
      onChanged: (v) => values[species]![key] = int.tryParse(v),
      validator: (v) {
        final n = int.tryParse(v ?? '');
        return n == null || n < 1 || n > (weeks ? 52 : 365)
            ? 'Enter 1–${weeks ? 52 : 365}'
            : null;
      },
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      title: const Text('Breeding settings'),
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
                    'Defaults for this Herd. Estimated windows update when settings change. Actual event dates are kept separately.',
                  ),
                  for (final s in ['rabbit', 'cavy']) ...[
                    const SizedBox(height: 20),
                    Text(
                      s == 'rabbit' ? 'Rabbits • Kits' : 'Cavies • Pups',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text('Days after breeding'),
                    field(s, 'gestation_min', 'Gestation start (days)'),
                    field(s, 'gestation_max', 'Gestation end (days)'),
                    field(s, 'palpation_min', 'Palpation start (day)'),
                    field(s, 'palpation_max', 'Palpation end (day)'),
                    if (s == 'rabbit')
                      field(s, 'nesting_day', 'Nesting box (day)'),
                    const SizedBox(height: 8),
                    const Text('Weeks after actual birth'),
                    field(
                      s,
                      'weaning_min',
                      'Weaning start (weeks)',
                      weeks: true,
                    ),
                    field(s, 'weaning_max', 'Weaning end (weeks)', weeks: true),
                  ],
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
          child: Text(saving ? 'Saving…' : 'Save settings'),
        ),
      ],
    ),
  );
}
