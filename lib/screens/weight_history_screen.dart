
import '../widgets/weight_graph.dart';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  final supabase = Supabase.instance.client;

  bool isSaving = false;

  bool get isLocked =>
      widget.status == 'sold' || widget.status == 'deceased';

  Future<List> fetchWeights() async {
    return await supabase
        .from('animal_weights')
        .select()
        .eq('animal_id', widget.animalId)
        .order('recorded_at', ascending: false);
  }

  Future<void> addWeight() async {
    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add Weight'),
        content: TextField(
          controller: controller,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
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
                    setState(() => isSaving = true);

                    final value =
                        double.tryParse(controller.text.trim());

                    if (value == null || value <= 0) {
                      setState(() => isSaving = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'Weight must be a positive number'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    try {
                      await supabase.from('animal_weights').insert({
                        'animal_id': widget.animalId,
                        'weight': value,
                      });

                      Navigator.pop(context);
                      setState(() {});
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content:
                              Text('Failed to save weight: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    } finally {
                      setState(() => isSaving = false);
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Weight History')),
      floatingActionButton: isLocked
          ? null
          : FloatingActionButton(
              onPressed: addWeight,
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
                      'Weights cannot be added for sold or deceased animals.',
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
              future: fetchWeights(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox(
                    height: 220,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final weights = snapshot.data as List;

                return WeightGraph(
                  weights: weights.reversed.toList(),
                );
              },
            ),
          ),

          const Divider(),

          // 📋 WEIGHT LIST (SCROLLABLE)
          Expanded(
            child: FutureBuilder(
              future: fetchWeights(),
              builder: (context, snapshot) {
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

                    final weightValue =
                        (w['weight'] as num).toStringAsFixed(2);

                    final recordedAt =
                        DateTime.parse(w['recorded_at'])
                            .toLocal()
                            .toString()
                            .split('.')[0];

                    return ListTile(
                      leading: const Icon(Icons.monitor_weight),
                      title: Text('$weightValue lb'),
                      subtitle: Text(recordedAt),
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