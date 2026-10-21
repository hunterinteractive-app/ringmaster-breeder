import 'package:flutter/material.dart';
import '../offline/offline_runtime.dart';
import '../models/sale_record.dart';
import 'adaptive_layout.dart';

/// Housing, custom values and dated purchase/status information shared by manual
/// records and imports. Kept apart from the locked pedigree of historical animals.
class AnimalManagementSection extends StatefulWidget {
  final String animalId;
  final Future<Map<String, dynamic>> Function()? loader;
  final Future<void> Function(Map<String, dynamic>, int)? writer;
  const AnimalManagementSection({
    super.key,
    required this.animalId,
    this.loader,
    this.writer,
  });
  @override
  State<AnimalManagementSection> createState() =>
      _AnimalManagementSectionState();
}

class _AnimalManagementSectionState extends State<AnimalManagementSection> {
  Map<String, dynamic>? data;
  List<Map<String, dynamic>> contacts = [];
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      if (widget.loader != null) {
        final loaded = await widget.loader!();
        if (mounted) {
          setState(() {
            data = Map<String, dynamic>.from(loaded['data'] ?? {});
            contacts = List<Map<String, dynamic>>.from(
              loaded['contacts'] ?? [],
            );
            error = null;
          });
        }
        return;
      }
      final db = OfflineRuntime.client;
      final animal = await db
          .from('animals')
          .select('ring_id')
          .eq('id', widget.animalId)
          .single();
      final row = await db
          .from('animal_management')
          .select()
          .eq('animal_id', widget.animalId)
          .maybeSingle();
      final people = <Map<String, dynamic>>[];
      for (var from = 0; ; from += 500) {
        final page = await db
            .from('herd_contacts')
            .select()
            .eq('ring_id', animal['ring_id'])
            .order('name')
            .order('id')
            .range(from, from + 499);
        people.addAll(List<Map<String, dynamic>>.from(page));
        if (page.length < 500) break;
      }
      if (mounted) {
        setState(() {
          data = row ?? {};
          contacts = List<Map<String, dynamic>>.from(people);
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Management details are unavailable. Reconnect and retry.',
        );
      }
    }
  }

  String contact(dynamic id) {
    for (final c in contacts) {
      if (c['id'] == id) {
        return [
          c['name'],
          c['rabbitry'],
        ].where((v) => v != null && v != '').join(' · ');
      }
    }
    return 'Not recorded';
  }

  Future<void> edit() async {
    final row = data!;
    final cage = TextEditingController(text: row['cage'] ?? '');
    final purchase = TextEditingController(
      text: row['purchase_cents'] == null
          ? ''
          : ((row['purchase_cents'] as num) / 100).toStringAsFixed(2),
    );
    final dates = {
      for (final k in ['death_date', 'sale_date', 'purchase_date'])
        k: TextEditingController(text: row[k] ?? ''),
    };
    final custom =
        <({TextEditingController label, TextEditingController value})>[
          for (final e in (row['custom_fields'] as Map? ?? {}).entries)
            (
              label: TextEditingController(text: e.key.toString()),
              value: TextEditingController(text: e.value.toString()),
            ),
        ];
    String? buyer = row['buyer_contact_id'],
        seller = row['seller_contact_id'],
        problem;
    bool saving = false;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AdaptiveFormDialog(
          title: const Text('Housing & custom details'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (problem != null)
                Text(
                  problem!,
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
              TextField(
                controller: cage,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Cage / housing'),
              ),
              for (final e in dates.entries)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: TextField(
                    controller: e.value,
                    decoration: InputDecoration(
                      labelText: switch (e.key) {
                        'death_date' => 'Death date',
                        'sale_date' => 'Sale date',
                        _ => 'Purchase date',
                      },
                      hintText: 'YYYY-MM-DD · leave blank if unknown',
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: purchase,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Purchase price (USD)',
                ),
              ),
              for (final isBuyer in [true, false])
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: DropdownButtonFormField<String>(
                    initialValue: isBuyer ? buyer : seller,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: isBuyer ? 'Buyer' : 'Seller',
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Not recorded'),
                      ),
                      for (final c in contacts)
                        DropdownMenuItem(
                          value: c['id'] as String,
                          child: Text(contact(c['id'])),
                        ),
                    ],
                    onChanged: (v) => set(() {
                      if (isBuyer) {
                        buyer = v;
                      } else {
                        seller = v;
                      }
                    }),
                  ),
                ),
              const SizedBox(height: 20),
              for (final field in custom)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    children: [
                      TextField(
                        controller: field.label,
                        decoration: const InputDecoration(
                          labelText: 'Custom field name',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: field.value,
                        maxLines: 2,
                        decoration: const InputDecoration(labelText: 'Value'),
                      ),
                    ],
                  ),
                ),
              TextButton.icon(
                onPressed: saving
                    ? null
                    : () => set(
                        () => custom.add((
                          label: TextEditingController(),
                          value: TextEditingController(),
                        )),
                      ),
                icon: const Icon(Icons.add),
                label: const Text('Add custom field'),
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
                      try {
                        for (final d in dates.values) {
                          final s = d.text.trim();
                          if (s.isNotEmpty) {
                            final v = DateTime.tryParse(s);
                            if (v == null ||
                                v.toIso8601String().substring(0, 10) != s ||
                                v.year < 1800 ||
                                s.compareTo(
                                      DateTime.now()
                                          .toIso8601String()
                                          .substring(0, 10),
                                    ) >
                                    0) {
                              throw const FormatException(
                                'Use a valid past date in YYYY-MM-DD format.',
                              );
                            }
                          }
                        }
                        final values = <String, String>{};
                        for (final f in custom) {
                          final label = f.label.text.trim();
                          if (label.isEmpty && f.value.text.isEmpty) continue;
                          if (label.isEmpty || values.containsKey(label)) {
                            throw const FormatException(
                              'Give each custom field a different name.',
                            );
                          }
                          values[label] = f.value.text;
                        }
                        final amount = parseSaleMoney(purchase.text);
                        set(() {
                          saving = true;
                          problem = null;
                        });
                        final params = {
                          'p_animal': widget.animalId,
                          'p_revision': row['revision'] ?? 0,
                          'p_data': {
                            'cage': cage.text.trim(),
                            'custom_fields': values,
                            for (final e in dates.entries)
                              e.key: e.value.text.trim().isEmpty
                                  ? null
                                  : e.value.text.trim(),
                            'purchase_cents': amount,
                            'buyer_contact_id': buyer,
                            'seller_contact_id': seller,
                          },
                        };
                        if (widget.writer != null) {
                          await widget.writer!(
                            params['p_data'] as Map<String, dynamic>,
                            params['p_revision'] as int,
                          );
                        } else {
                          await OfflineRuntime.client.rpc(
                            'save_animal_management',
                            params: params,
                          );
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        await load();
                      } catch (e) {
                        if (ctx.mounted) {
                          set(() {
                            saving = false;
                            problem = e is FormatException
                                ? e.message
                                : 'Unable to save. Refresh details and retry.';
                          });
                        }
                      }
                    },
              child: Text(saving ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      cage.dispose();
      purchase.dispose();
      for (final c in dates.values) {
        c.dispose();
      }
      for (final c in custom) {
        c.label.dispose();
        c.value.dispose();
      }
    });
  }

  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      title: const Text('Housing, contacts & custom details'),
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error != null)
                Text(error!)
              else if (data == null)
                const LinearProgressIndicator()
              else ...[
                Text('Cage / housing: ${data!['cage'] ?? ''}'),
                for (final e in const {
                  'death_date': 'Death date',
                  'sale_date': 'Sale date',
                  'purchase_date': 'Purchase date',
                }.entries)
                  if (data![e.key] != null) Text('${e.value}: ${data![e.key]}'),
                if (data!['purchase_cents'] != null)
                  Text(
                    'Purchase price: ${saleMoney((data!['purchase_cents'] as num).toInt())}',
                  ),
                if (data!['asking_cents'] != null)
                  Text(
                    'Asking price: ${saleMoney((data!['asking_cents'] as num).toInt())}',
                  ),
                Text('Buyer: ${contact(data!['buyer_contact_id'])}'),
                Text('Seller: ${contact(data!['seller_contact_id'])}'),
                for (final e in (data!['custom_fields'] as Map? ?? {}).entries)
                  SelectableText('${e.key}: ${e.value}'),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: edit,
                  child: const Text('Edit management details'),
                ),
              ],
              if (error != null)
                TextButton(onPressed: load, child: const Text('Retry')),
            ],
          ),
        ),
      ],
    ),
  );
}
