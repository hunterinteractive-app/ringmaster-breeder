import '../widgets/ringmaster_page_shell.dart';
import '../widgets/weight_graph.dart';

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

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(record == null ? 'Add Weight' : 'Edit Latest Weight'),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Weight (lb)',
              hintText: 'Example: 4.25',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
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
                          await AnimalService.addWeight(widget.animalId, value);
                        } else {
                          await AnimalService.editLatestWeight(
                            widget.animalId,
                            record['id'],
                            value,
                          );
                        }
                        if (!mounted) return;
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
                            content: Text('Failed to save weight: $e'),
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
    );
    isSaving = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  }

  @override
  Widget build(BuildContext context) {
    return RingMasterPageShell(
      title: 'Weight History',
      floatingActionButton: isLocked
          ? null
          : FloatingActionButton(
              onPressed: () => addWeight(),
              child: const Icon(Icons.add),
            ),
      body: Column(
        children: [
          if (isLocked)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Weights cannot be added or edited for sold or deceased animals.',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),

          // 📈 GRAPH ALWAYS VISIBLE
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: FutureBuilder(
              future: _weights,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text(
                      "Unable to load records. Please go back and try again.",
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const SizedBox(
                    height: 220,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final weights = snapshot.data as List;

                return WeightGraph(weights: weights.reversed.toList());
              },
            ),
          ),

          const Divider(),

          // 📋 WEIGHT LIST (SCROLLABLE)
          Expanded(
            child: FutureBuilder(
              future: _weights,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text(
                      "Unable to load records. Please go back and try again.",
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final weights = snapshot.data as List;

                if (weights.isEmpty) {
                  return const Center(child: Text('No weight records yet'));
                }

                return ListView.builder(
                  itemCount: weights.length,
                  itemBuilder: (context, index) {
                    final w = weights[index];

                    final weightValue = (w['weight'] as num).toStringAsFixed(2);

                    final recordedAt = DateTime.parse(
                      w['recorded_at'],
                    ).toLocal().toString().split('.')[0];

                    return ListTile(
                      leading: const Icon(Icons.monitor_weight),
                      title: Text('$weightValue lb'),
                      subtitle: Text(
                        index == 0 && !isLocked
                            ? '$recordedAt • Tap to edit latest weight'
                            : recordedAt,
                      ),
                      trailing: index == 0 && !isLocked
                          ? const Icon(Icons.edit_outlined)
                          : null,
                      onTap: index == 0 && !isLocked
                          ? () => addWeight(Map<String, dynamic>.from(w))
                          : null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
