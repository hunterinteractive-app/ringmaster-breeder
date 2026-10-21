import 'package:flutter/material.dart';
import '../offline/offline_runtime.dart';
import '../services/sales_service.dart';
import '../utils/production_measurements.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/wool_production_summary.dart';
import '../widgets/ringmaster_page_shell.dart';

/// Dated feed/live-weight readings and wool harvest/evaluation records.
class ProductionMeasurementsScreen extends StatefulWidget {
  final String recordId;
  final bool wool, animalFeed;
  final Future<List<Map<String, dynamic>>> Function()? loader;
  final Future<void> Function(Map<String, dynamic>)? writer;
  const ProductionMeasurementsScreen({
    super.key,
    required this.recordId,
    this.wool = false,
    this.animalFeed = false,
    this.loader,
    this.writer,
  });
  @override
  State<ProductionMeasurementsScreen> createState() =>
      _ProductionMeasurementsScreenState();
}

class _ProductionMeasurementsScreenState
    extends State<ProductionMeasurementsScreen> {
  late Future<List<Map<String, dynamic>>> records;
  bool removed = false;
  Map<String, dynamic> woolSettings = Map.of(defaultWoolSettings);
  String get kind => widget.wool
      ? 'wool'
      : widget.animalFeed
      ? 'animal_feed'
      : 'litter';
  String get table => widget.wool
      ? 'animal_wool_records'
      : widget.animalFeed
      ? 'animal_feed_weights'
      : 'litter_weights';
  String get field =>
      widget.wool || widget.animalFeed ? 'animal_id' : 'breeding_id';
  String get title => widget.wool
      ? 'Wool harvest history'
      : widget.animalFeed
      ? 'Feed & weight history'
      : 'Litter weights & feed';
  @override
  void initState() {
    super.initState();
    records = load();
  }

  Future<List<Map<String, dynamic>>> load() async {
    if (widget.loader != null) return widget.loader!();
    final rows = <Map<String, dynamic>>[];
    for (var from = 0; ; from += 500) {
      final page = await OfflineRuntime.client
          .from(table)
          .select(
            widget.animalFeed || widget.wool
                ? '*,native_weight:animal_weights(weight,recorded_at)'
                : '*',
          )
          .eq(field, widget.recordId)
          .order('recorded_date', ascending: false)
          .order('id')
          .range(from, from + 499);
      rows.addAll(
        List<Map<String, dynamic>>.from(page).map(
          (r) => {
            ...r,
            if (r['native_weight'] is Map && widget.animalFeed)
              'weight': r['native_weight']['weight'],
            if (r['native_weight'] is Map && widget.wool)
              'measurements': {
                ...Map<String, dynamic>.from(r['measurements'] ?? {}),
                'BODYWT': (r['native_weight']['weight'] as num) * 453.592,
              },
          },
        ),
      );
      if (page.length < 500) return rows;
    }
  }

  void refresh() => setState(() => records = load());
  Future<void> write(Map<String, dynamic> row, int revision) async {
    if (widget.writer != null) {
      await widget.writer!(row);
      return;
    }
    await OfflineRuntime.client.rpc(
      'save_production_measurement',
      params: {
        'p_kind': kind,
        'p_id': row['id'],
        'p_parent': widget.recordId,
        'p_data': row,
        'p_revision': revision,
      },
    );
  }

  Future<void> toggleRemoved(Map<String, dynamic> row) async {
    try {
      await write({
        ...row,
        'voided': row['voided'] != true,
      }, row['revision'] ?? 1);
      refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to update this record. Refresh and retry.'),
          ),
        );
      }
    }
  }

  Future<void> add([Map<String, dynamic>? existing]) async {
    var entryUnit = woolSettings['unit'] as String;
    var unitVersion = 0;
    final originalDetails = canonicalWool(
      existing?['measurements'] as Map? ?? {},
    );
    final judging = woolJudging(originalDetails);
    final date = TextEditingController(
      text: existing == null
          ? DateTime.now().toIso8601String().substring(0, 10)
          : existing['recorded_date']?.toString() ?? '',
    );
    final weight = TextEditingController(
      text: widget.wool
          ? woolEntryText(existing?['fleece_grams'], entryUnit)
          : existing?['weight']?.toString() ?? '',
    );
    final feed = TextEditingController(
      text: existing?['feed_weight']?.toString() ?? '',
    );
    final notes = TextEditingController(text: existing?['notes'] ?? '');
    final color = TextEditingController(
      text: originalDetails['COLOR']?.toString() ?? '',
    );
    final measurements = {
      for (final k in woolFields.keys)
        k: TextEditingController(
          text: woolWeightKeys.contains(k)
              ? woolEntryText(originalDetails[k], entryUnit)
              : originalDetails[k]?.toString() ?? '',
        ),
    };
    final evaluation = {
      for (final k in woolJudgingFields.keys)
        k: TextEditingController(text: judging[k] ?? ''),
    };
    final id = existing?['id'] as String? ?? SalesService.newId();
    final bodyLocked =
        (widget.animalFeed || widget.wool) &&
        existing?['native_weight_id'] != null;
    Map<String, dynamic>? pending;
    var saving = false;
    String? error;
    final dialog = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          Widget input(
            TextEditingController controller,
            String label, {
            bool numeric = false,
            bool enabled = true,
            int lines = 1,
          }) => Padding(
            padding: const EdgeInsets.only(top: 16),
            child: TextField(
              controller: controller,
              enabled: !saving && pending == null && enabled,
              keyboardType: numeric
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : null,
              maxLines: lines,
              onChanged: (_) => set(() {}),
              decoration: InputDecoration(labelText: label),
            ),
          );
          Widget group(String label, List<Widget> children) => ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(label),
            maintainState: true,
            children: children,
          );
          return PopScope(
            canPop: !saving,
            child: AdaptiveFormDialog(
              title: Text(
                existing == null
                    ? widget.wool
                          ? 'Record wool harvest / evaluation'
                          : 'Record feed & weight'
                    : 'Edit measurement',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.wool && woolSettings['update_body_weight'] == true)
                    const Text(
                      'A dated, positive body weight will also be added to Weight History for active or archived rabbits. Sold and deceased rabbits keep it in wool history.',
                    ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                    ),
                  input(date, 'Date (YYYY-MM-DD)', enabled: !bodyLocked),
                  if (widget.wool)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Leave the harvest date blank for an evaluation without a known harvest date.',
                      ),
                    ),
                  if (widget.wool)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('wool-entry-unit-$unitVersion'),
                        initialValue: entryUnit,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Wool weight units',
                        ),
                        items: [
                          for (final e in woolUnits.entries)
                            DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                        ],
                        onChanged: saving || pending != null
                            ? null
                            : (v) {
                                try {
                                  final values = {
                                    for (final e in measurements.entries.where(
                                      (e) => woolWeightKeys.contains(e.key),
                                    ))
                                      e.key: woolEntryGrams(
                                        e.value.text,
                                        entryUnit,
                                      ),
                                  };
                                  final fleece = woolEntryGrams(
                                    weight.text,
                                    entryUnit,
                                  );
                                  set(() {
                                    unitVersion++;
                                    entryUnit = v!;
                                    weight.text = woolEntryText(
                                      fleece,
                                      entryUnit,
                                    );
                                    for (final e in values.entries) {
                                      measurements[e.key]!.text = woolEntryText(
                                        e.value,
                                        entryUnit,
                                      );
                                    }
                                    error = null;
                                  });
                                } on FormatException catch (e) {
                                  set(() {
                                    unitVersion++;
                                    error = e.message;
                                  });
                                }
                              },
                      ),
                    ),
                  input(
                    weight,
                    widget.wool
                        ? 'Total fleece weight (${entryUnit == 'lb_oz' ? 'lb & oz' : entryUnit}) · optional'
                        : widget.animalFeed
                        ? 'Animal weight (lb) · optional'
                        : 'Total litter weight (lb) · optional',
                    numeric: !widget.wool || entryUnit != 'lb_oz',
                    enabled: !bodyLocked || widget.wool,
                  ),
                  if (widget.wool && entryUnit == 'lb_oz')
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Enter pounds and ounces, for example 1 lb 4 oz.',
                      ),
                    ),
                  if (bodyLocked)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        widget.wool
                            ? 'This body weight and date are linked to Weight History. Other harvest and evaluation details remain editable here.'
                            : 'This body weight is linked to Weight History. Correct the latest body weight there; feed remains editable here.',
                      ),
                    ),
                  if (!widget.wool) ...[
                    input(
                      feed,
                      widget.animalFeed
                          ? 'Cumulative feed (lb) · optional'
                          : 'Cumulative feed to dam (lb) · optional',
                      numeric: true,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Feed / live weight: ${feedWeightRatio(feed.text, weight.text) == null ? 'Needs feed and a positive live weight' : '${measurementText(feedWeightRatio(feed.text, weight.text))}:1'}',
                    ),
                    const Text(
                      'Uses cumulative feed divided by live weight on this date. Feed entries are not added together.',
                    ),
                  ],
                  if (widget.wool) ...[
                    input(color, 'Wool color'),
                    for (final label in ['Harvest', 'Fiber quality'])
                      group(label, [
                        for (final e in woolFields.entries.where(
                          (e) => e.value.group == label,
                        ))
                          input(
                            measurements[e.key]!,
                            woolWeightKeys.contains(e.key)
                                ? e.value.label.replaceAll(
                                    '(g)',
                                    '(${entryUnit == 'lb_oz' ? 'lb & oz' : entryUnit})',
                                  )
                                : e.value.label,
                            numeric:
                                !woolWeightKeys.contains(e.key) ||
                                entryUnit != 'lb_oz',
                            enabled: e.key != 'BODYWT' || !bodyLocked,
                          ),
                        const SizedBox(height: 12),
                      ]),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Total graded wool: ${woolWeightText(gradedWoolTotal({for (final e in measurements.entries.where((e) => woolWeightKeys.contains(e.key))) e.key: _previewGrams(e.value.text, entryUnit)}), entryUnit)}',
                      ),
                    ),
                    group('Judging & evaluation', [
                      for (final e in woolJudgingFields.entries)
                        input(
                          evaluation[e.key]!,
                          e.value,
                          lines: e.key == 'Comments' || e.key == 'WoolPerf'
                              ? 3
                              : 1,
                        ),
                      const SizedBox(height: 12),
                    ]),
                  ],
                  input(notes, 'Notes', lines: 3),
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
                          try {
                            void validateDate(
                              String v, {
                              bool optional = false,
                            }) {
                              if (v.trim().isEmpty && optional) return;
                              final d = DateTime.tryParse(v);
                              if (d == null ||
                                  d.toIso8601String().substring(0, 10) != v ||
                                  d.year < 1800 ||
                                  v.compareTo(
                                        DateTime.now()
                                            .toIso8601String()
                                            .substring(0, 10),
                                      ) >
                                      0) {
                                throw const FormatException(
                                  'Enter a valid past date in YYYY-MM-DD format.',
                                );
                              }
                            }

                            validateDate(date.text, optional: widget.wool);
                            double? number(
                              TextEditingController c, {
                              double? maximum,
                            }) {
                              if (c.text.trim().isEmpty) return null;
                              final n = double.tryParse(c.text);
                              if (n == null ||
                                  !n.isFinite ||
                                  n < 0 ||
                                  n >= 1000000 ||
                                  (maximum != null && n > maximum)) {
                                throw FormatException(
                                  maximum == null
                                      ? 'Measurements must be nonnegative numbers below 1,000,000.'
                                      : 'Percentage measurements must be between 0 and $maximum.',
                                );
                              }
                              return n;
                            }

                            double? woolNumber(TextEditingController c) {
                              final n = woolEntryGrams(c.text, entryUnit);
                              if (n != null && (n < 0 || n >= 1000000)) {
                                throw const FormatException(
                                  'Wool weights must be nonnegative and below 1,000,000 grams.',
                                );
                              }
                              return n;
                            }

                            final w = widget.wool
                                    ? (existing != null &&
                                              weight.text ==
                                                  woolEntryText(
                                                    existing['fleece_grams'],
                                                    entryUnit,
                                                  )
                                          ? measurementNumber(
                                              existing['fleece_grams'],
                                            )
                                          : woolNumber(weight))
                                    : number(weight),
                                f = number(feed);
                            final details = Map<String, dynamic>.from(
                              originalDetails,
                            );
                            for (final e in measurements.entries) {
                              if (e.value.text.trim().isEmpty) {
                                details.remove(e.key);
                              } else {
                                details[e.key] = woolWeightKeys.contains(e.key)
                                    ? (e.value.text ==
                                                  woolEntryText(
                                                    originalDetails[e.key],
                                                    entryUnit,
                                                  ) ||
                                              bodyLocked && e.key == 'BODYWT'
                                          ? measurementNumber(
                                              originalDetails[e.key],
                                            )
                                          : woolNumber(e.value))
                                    : number(
                                        e.value,
                                        maximum: woolFields[e.key]!.maximum,
                                      );
                              }
                            }
                            if (color.text.trim().isNotEmpty) {
                              details['COLOR'] = color.text.trim();
                            } else {
                              details.remove('COLOR');
                            }
                            final evalValues = {
                              for (final e in evaluation.entries)
                                e.key: e.value.text.trim(),
                            };
                            final oldEval = {
                              for (final k in woolJudgingFields.keys)
                                k: judging[k] ?? '',
                            };
                            if (evalValues.entries.any(
                              (e) => e.value != oldEval[e.key],
                            )) {
                              validateDate(
                                evalValues['EvalDate']!,
                                optional: true,
                              );
                              details['XMLDATA'] = updateWoolJudging(
                                evalValues,
                                originalDetails['XMLDATA']?.toString(),
                              );
                            }
                            if (!widget.wool &&
                                (w == null || w == 0) &&
                                f == null) {
                              throw const FormatException(
                                'Enter feed, a positive live weight, or both.',
                              );
                            }
                            if (!widget.wool && w != null && w >= 1000) {
                              throw const FormatException(
                                'Live weight must be below 1,000 lb.',
                              );
                            }
                            if (widget.wool &&
                                existing == null &&
                                (w == null || w == 0) &&
                                !details.entries.any(
                                  (e) =>
                                      ![
                                        'FLEECEWT',
                                        'SHEARDATE',
                                        'COMMENTS',
                                        'ID',
                                        'WID',
                                        'CID',
                                      ].contains(e.key) &&
                                      e.value.toString().isNotEmpty,
                                )) {
                              throw const FormatException(
                                'Enter a harvest measurement or evaluation.',
                              );
                            }
                            set(() {
                              saving = true;
                              error = null;
                            });
                            pending ??= {
                              'id': id,
                              field: widget.recordId,
                              'recorded_date': date.text.isEmpty
                                  ? null
                                  : date.text,
                              'notes': notes.text,
                              'voided': false,
                              if (widget.wool) ...{
                                'fleece_grams': w == 0 ? null : w,
                                'measurements': details,
                              } else ...{
                                'weight': w == 0 ? null : w,
                                'feed_weight': f,
                              },
                            };
                            await write(pending!, existing?['revision'] ?? 0);
                            if (ctx.mounted) Navigator.pop(ctx);
                            refresh();
                          } catch (e) {
                            if (ctx.mounted) {
                              set(() {
                                saving = false;
                                error = pending == null && e is FormatException
                                    ? e.message
                                    : pending == null
                                    ? 'Unable to save. Check measurements and retry.'
                                    : 'Unable to confirm the save. Retry this same record to finish.';
                              });
                            }
                          }
                        },
                  child: Text(saving ? 'Saving…' : 'Save'),
                ),
              ],
            ),
          );
        },
      ),
    );
    await Navigator.of(context).push(dialog);
    await dialog.completed;
    for (final c in [
      date,
      weight,
      feed,
      notes,
      color,
      ...measurements.values,
      ...evaluation.values,
    ]) {
      c.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => RingMasterPageShell(
    title: title,
    onRefresh: refresh,
    floatingActionButton: FloatingActionButton(
      onPressed: add,
      tooltip: widget.wool ? 'Record wool harvest' : 'Record feed & weight',
      child: const Icon(Icons.add),
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: records,
      builder: (context, s) {
        if (s.hasError) {
          return Center(
            child: TextButton(
              onPressed: refresh,
              child: const Text('Unable to load records. Reconnect and retry.'),
            ),
          );
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final visible = s.data!
            .where((r) => (r['voided'] == true) == removed)
            .toList();
        return ListView(
          padding: BreederLayout.pagePadding(context, normal: 24),
          children: [
            Text(
              widget.wool
                  ? 'Record wool harvests, grades, fiber quality and judging evaluations. Wool yields stay separate from animal body weights. Manage units, yield factors and optional body-weight links in Wool settings.'
                  : 'Record feed and live weights together or separately. Feed is a cumulative total; each row is a reading, not another quantity to add.',
            ),
            if (widget.wool)
              WoolProductionSummary(
                animalId: widget.recordId,
                records: s.data!,
                onSettings: (v) {
                  if (mounted) setState(() => woolSettings = v);
                },
                loader: widget.loader == null ? null : () async => {},
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Current'),
                  selected: !removed,
                  onSelected: (_) => setState(() => removed = false),
                ),
                ChoiceChip(
                  label: const Text('Removed'),
                  selected: removed,
                  onSelected: (_) => setState(() => removed = true),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (visible.isEmpty) const Text('No measurements recorded yet.'),
            for (final r in visible)
              Card(
                child: ExpansionTile(
                  title: Text(
                    '${r['recorded_date'] ?? 'Date unknown'} · ${widget.wool
                        ? (r['fleece_grams'] == null ? 'Total fleece weight unknown' : '${woolWeightText(r['fleece_grams'], woolSettings['unit'])} fleece')
                        : r['weight'] == null
                        ? 'Feed reading'
                        : '${measurementText(r['weight'])} lb ${widget.animalFeed ? 'animal' : 'litter'}'}',
                  ),
                  subtitle: Text(
                    [
                      if (r['import_source'] != null)
                        'Imported from Rabbit Register',
                      if (r['feed_weight'] != null)
                        '${measurementText(r['feed_weight'])} lb cumulative feed',
                    ].join(' · '),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!widget.wool &&
                              feedWeightRatio(r['feed_weight'], r['weight']) !=
                                  null)
                            Text(
                              'Feed / live weight: ${measurementText(feedWeightRatio(r['feed_weight'], r['weight']))}:1',
                            ),
                          if (widget.wool) ...woolDetails(r),
                          if (r['native_weight_id'] != null)
                            const Text(
                              'The linked body weight remains in Weight History if this measurement is removed.',
                            ),
                          if ((r['notes'] ?? '').toString().isNotEmpty)
                            Text(r['notes']),
                          Wrap(
                            spacing: 12,
                            children: [
                              if (!removed)
                                TextButton.icon(
                                  onPressed: () => add(r),
                                  icon: const Icon(Icons.edit_outlined),
                                  label: const Text('Edit measurement'),
                                ),
                              TextButton.icon(
                                onPressed: () => toggleRemoved(r),
                                icon: Icon(
                                  removed
                                      ? Icons.restore
                                      : Icons.remove_circle_outline,
                                ),
                                label: Text(
                                  removed
                                      ? 'Restore measurement'
                                      : 'Remove measurement',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );

  double? _previewGrams(String text, String unit) {
    try {
      return woolEntryGrams(text, unit);
    } on FormatException {
      return null;
    }
  }

  List<Widget> woolDetails(Map r) {
    final m = canonicalWool(r['measurements'] as Map? ?? {}),
        judging = woolJudging(canonicalWool(r['measurements'] as Map? ?? {}));
    return [
      if (m['COLOR'] != null) SelectableText('Wool color: ${m['COLOR']}'),
      for (final e in woolFields.entries)
        if (m[e.key] != null)
          SelectableText(
            woolWeightKeys.contains(e.key)
                ? '${e.value.label.replaceAll(' (g)', '')}: ${woolWeightText(m[e.key], woolSettings['unit'])}'
                : '${e.value.label}: ${m[e.key]}',
          ),
      if (gradedWoolTotal(m) != null)
        Text(
          'Total graded wool: ${woolWeightText(gradedWoolTotal(m), woolSettings['unit'])}',
        ),
      if (woolYield(r, 'adjusted', woolSettings['factors']) != null)
        Text(
          'Adjusted gross wool: ${woolWeightText(woolYield(r, 'adjusted', woolSettings['factors']), woolSettings['unit'])}',
        ),
      for (final e in judging.entries)
        if (e.value.isNotEmpty &&
            ![
              '0100-01-01',
              '0100-01-02',
              '0100-01-03',
              '2100-12-12',
            ].contains(e.value))
          SelectableText('${woolJudgingFields[e.key] ?? e.key}: ${e.value}'),
      for (final e in m.entries)
        if (!woolFields.containsKey(e.key) &&
            ![
              'ID',
              'WID',
              'CID',
              'FLEECEWT',
              'SHEARDATE',
              'COMMENTS',
              'COLOR',
              'XMLDATA',
              'FELTEDSTAINDED',
              'VEFGMATTERBASE',
            ].contains(e.key))
          SelectableText('${e.key}: ${e.value}'),
      if (m['XMLDATA'] != null)
        ExpansionTile(
          title: const Text('Original evaluation XML'),
          children: [SelectableText(m['XMLDATA'].toString())],
        ),
    ];
  }
}
