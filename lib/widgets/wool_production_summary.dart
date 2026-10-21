import 'package:flutter/material.dart';
import '../offline/offline_runtime.dart';
import '../utils/production_measurements.dart';
import 'adaptive_layout.dart';

class WoolProductionSummary extends StatefulWidget {
  final String animalId;
  final List<Map<String, dynamic>> records;
  final Future<Map<String, dynamic>> Function()? loader;
  final ValueChanged<Map<String, dynamic>>? onSettings;
  final Future<void> Function(Map<String, dynamic>, int)? writer;
  const WoolProductionSummary({
    super.key,
    required this.animalId,
    required this.records,
    this.loader,
    this.writer,
    this.onSettings,
  });
  @override
  State<WoolProductionSummary> createState() => _WoolProductionSummaryState();
}

class _WoolProductionSummaryState extends State<WoolProductionSummary> {
  Map<String, dynamic> settings = Map.of(defaultWoolSettings);
  int revision = 0;
  bool loaded = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      Map<String, dynamic>? value;
      if (widget.loader != null) {
        value = await widget.loader!();
      } else {
        final a = await OfflineRuntime.client
            .from('animals')
            .select('ring_id')
            .eq('id', widget.animalId)
            .single();
        value = await OfflineRuntime.client
            .from('wool_settings')
            .select()
            .eq('ring_id', a['ring_id'])
            .maybeSingle();
      }
      if (mounted) {
        setState(() {
          settings = {...defaultWoolSettings, ...?value};
          revision = value?['revision'] ?? 0;
          loaded = true;
          error = null;
        });
      }
      widget.onSettings?.call(settings);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Unable to load wool settings. Reconnect and retry.',
        );
      }
    }
  }

  Future<void> edit() async {
    final chosen = Map<String, dynamic>.from(settings);
    final factors = Map<String, dynamic>.from(settings['factors']);
    final controllers = {
      for (final e in factors.entries)
        e.key: TextEditingController(text: e.value.toString()),
    };
    var saving = false;
    String? problem;
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AdaptiveFormDialog(
          title: const Text('Wool settings for this herd'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'The XML does not include Evans’ wool settings. Review these scale factors before comparing adjusted yields.',
              ),
              const SizedBox(height: 16),
              for (final e in {
                'unit': woolUnits,
                'metric': woolMetrics,
                'period': woolPeriods,
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: DropdownButtonFormField<String>(
                    initialValue: chosen[e.key],
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: switch (e.key) {
                        'unit' => 'Wool weight units',
                        'metric' => 'Production summary',
                        _ => 'Summary period',
                      },
                    ),
                    items: [
                      for (final choice in e.value.entries)
                        DropdownMenuItem(
                          value: choice.key,
                          child: Text(choice.value),
                        ),
                    ],
                    onChanged: saving ? null : (v) => chosen[e.key] = v,
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include wool summary on pedigrees'),
                subtitle: const Text(
                  'Uses the selected yield and latest reporting period.',
                ),
                value: chosen['show_on_pedigree'] == true,
                onChanged: saving
                    ? null
                    : (v) => set(() => chosen['show_on_pedigree'] = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Add harvest body weights to Weight History'),
                subtitle: const Text(
                  'Applies to active or archived rabbits when saving a dated harvest with a positive body weight. Sold and deceased rabbits retain it in wool history.',
                ),
                value: chosen['update_body_weight'] == true,
                onChanged: saving
                    ? null
                    : (v) => set(() => chosen['update_body_weight'] = v),
              ),
              const Text(
                'Adjusted gross scale factors',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              for (final e in controllers.entries)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: TextField(
                    controller: e.value,
                    enabled: !saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText:
                          '${woolFields[e.key]!.label.replaceAll(' (g)', '')} (%)',
                    ),
                  ),
                ),
              if (problem != null)
                Text(
                  problem!,
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      for (final e in controllers.entries) {
                        final n = double.tryParse(e.value.text);
                        if (n == null || !n.isFinite || n < 0 || n > 100) {
                          set(
                            () => problem =
                                'Scale factors must be from 0 to 100.',
                          );
                          return;
                        }
                        factors[e.key] = n;
                      }
                      chosen['factors'] = factors;
                      set(() => saving = true);
                      try {
                        if (widget.writer != null) {
                          await widget.writer!(chosen, revision);
                        } else {
                          await OfflineRuntime.client.rpc(
                            'save_wool_settings',
                            params: {
                              'p_animal': widget.animalId,
                              'p_data': chosen,
                              'p_revision': revision,
                            },
                          );
                        }
                        if (mounted) setState(() => settings = chosen);
                        widget.onSettings?.call(chosen);
                        if (ctx.mounted) Navigator.pop(ctx);
                        await load();
                      } catch (_) {
                        if (ctx.mounted) {
                          set(() {
                            saving = false;
                            problem =
                                'Unable to save. Refresh settings before retrying.';
                          });
                        }
                      }
                    },
              child: Text(saving ? 'Saving…' : 'Save settings'),
            ),
          ],
        ),
      ),
    );
    await Navigator.of(context).push(route);
    await route.completed;
    for (final c in controllers.values) {
      c.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) return TextButton(onPressed: load, child: Text(error!));
    if (!loaded) return const LinearProgressIndicator();
    final totals = woolSummary(widget.records, settings);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Wool production summary',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('yield-${settings['metric']}'),
                    initialValue: settings['metric'],
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Yield'),
                    items: [
                      for (final e in woolMetrics.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) =>
                        setState(() => settings = {...settings, 'metric': v}),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('period-${settings['period']}'),
                    initialValue: settings['period'],
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Period'),
                    items: [
                      for (final e in woolPeriods.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) =>
                        setState(() => settings = {...settings, 'period': v}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (totals.isEmpty)
              const Text('No dated harvest yields for this summary.'),
            for (final e in totals.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  children: [
                    Text(e.key),
                    Text(woolWeightText(e.value, settings['unit'])),
                  ],
                ),
              ),
            const Text(
              'Undated records and evaluations without harvest weights remain in history and are excluded from production totals.',
            ),
            TextButton.icon(
              onPressed: edit,
              icon: const Icon(Icons.settings_outlined),
              label: const Text('Wool settings'),
            ),
          ],
        ),
      ),
    );
  }
}
