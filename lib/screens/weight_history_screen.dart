import '../widgets/adaptive_layout.dart';
import '../services/sales_service.dart';
import '../utils/weight_date.dart';
import '../widgets/ringmaster_page_shell.dart';
import '../widgets/weight_graph.dart';
import '../offline/offline_runtime.dart';

import 'package:flutter/material.dart';
import '../services/animal_service.dart';

class WeightHistoryScreen extends StatefulWidget {
  final String animalId;
  final String status;

  const WeightHistoryScreen({
    super.key,
    required this.animalId,
    required this.status,
  });

  @override
  State<WeightHistoryScreen> createState() => _WeightHistoryScreenState();
}

class _WeightHistoryScreenState extends State<WeightHistoryScreen> {
  bool isSaving = false;

  bool get isLocked => widget.status == 'sold' || widget.status == 'deceased';

  late Future<List<Map<String, dynamic>>> _weights;
  @override
  void initState() {
    super.initState();
    _weights = AnimalService.weights(widget.animalId);
  }

  Future<void> addWeight([Map<String, dynamic>? record]) async {
    final controller = TextEditingController(
      text: record?['weight']?.toString() ?? '',
    );

    final recordId = SalesService.newId();
    final recordedAt = DateTime.now();
    double? pendingWeight;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => PopScope(
          canPop: !isSaving,
          child: AdaptiveFormDialog(
            title: Text(record == null ? 'Add Weight' : 'Edit Latest Weight'),
            content: TextField(
              controller: controller,
              enabled: !isSaving && pendingWeight == null,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Weight (lb)',
                hintText: 'Example: 4.25',
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        setDialogState(() => isSaving = true);

                        final value = double.tryParse(controller.text.trim());

                        if (value == null || !value.isFinite || value <= 0) {
                          if (dialogContext.mounted) {
                            setDialogState(() => isSaving = false);
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Weight must be a positive number'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        try {
                          if (record == null) {
                            pendingWeight ??= value;
                            await AnimalService.addWeight(
                              widget.animalId,
                              pendingWeight!,
                              recordId: recordId,
                              recordedAt: recordedAt,
                            );
                          } else {
                            await AnimalService.editLatestWeight(
                              widget.animalId,
                              record['id'],
                              value,
                            );
                          }
                          if (!mounted) return;
                          if (record == null && OfflineRuntime.engine != null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Saved on this device. Open Sync to check upload status.',
                                ),
                              ),
                            );
                          }
                          Navigator.pop(context);
                          if (mounted) {
                            setState(
                              () => _weights = AnimalService.weights(
                                widget.animalId,
                              ),
                            );
                          }
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                record == null
                                    ? 'Unable to confirm the save. Retry to check and finish this same weight.'
                                    : 'Failed to save weight: $e',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        } finally {
                          if (dialogContext.mounted) {
                            setDialogState(() => isSaving = false);
                          }
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
    isSaving = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  }

  @override
  Widget build(BuildContext context) {
    return RingMasterPageShell(
      onRefresh: () =>
          setState(() => _weights = AnimalService.weights(widget.animalId)),
      title: 'Weight History',
      floatingActionButton: isLocked
          ? null
          : FloatingActionButton(
              tooltip: 'Add weight',
              onPressed: () => addWeight(),
              child: const Icon(Icons.add),
            ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _weights,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Unable to load records. Please go back and try again.',
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return WeightHistoryView(
            weights: snapshot.data!,
            locked: isLocked,
            onEdit: addWeight,
          );
        },
      ),
    );
  }
}

class WeightHistoryView extends StatelessWidget {
  final List<Map<String, dynamic>> weights;
  final bool locked;
  final ValueChanged<Map<String, dynamic>> onEdit;
  const WeightHistoryView({
    super.key,
    required this.weights,
    required this.locked,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final compact = BreederLayout.compact(context);
    return CustomScrollView(
      slivers: [
        if (locked)
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Weights cannot be added or edited for sold or deceased animals.',
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: compact
              ? ExpansionTile(
                  key: const PageStorageKey('weight-chart'),
                  title: const Text('Growth chart'),
                  children: [
                    WeightGraph(
                      weights: weights.reversed.toList(),
                      height: 180,
                    ),
                  ],
                )
              : WeightGraph(weights: weights.reversed.toList()),
        ),
        if (weights.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No weight records yet'),
            ),
          )
        else
          SliverPadding(
            // Leave the final row clear of the add button and phone safe area.
            padding: EdgeInsets.only(
              bottom: 88 + MediaQuery.paddingOf(context).bottom,
            ),
            sliver: SliverList.builder(
              itemCount: weights.length,
              itemBuilder: (context, index) {
                final w = weights[index];
                final recordedAt = weightDate(w['recorded_at']);
                final editable = index == 0 && !locked;
                return ListTile(
                  leading: const Icon(Icons.monitor_weight),
                  title: Text('${(w['weight'] as num).toStringAsFixed(2)} lb'),
                  subtitle: Text(
                    editable
                        ? '$recordedAt • Tap to edit latest weight'
                        : recordedAt,
                  ),
                  trailing: editable ? const Icon(Icons.edit_outlined) : null,
                  onTap: editable ? () => onEdit(w) : null,
                );
              },
            ),
          ),
      ],
    );
  }
}
