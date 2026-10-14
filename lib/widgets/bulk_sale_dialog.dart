import 'package:flutter/material.dart';
import '../models/sale_record.dart';
import '../services/sales_service.dart';
import '../utils/animal_labels.dart';

typedef SaleLister = Future<void> Function(List<Map<String, dynamic>>, int?);

class BulkSaleDialog extends StatefulWidget {
  final List<Map<String, dynamic>> animals;
  final SaleLister? writer;
  const BulkSaleDialog({super.key, required this.animals, this.writer});
  @override
  State<BulkSaleDialog> createState() => _BulkSaleDialogState();
}

class _BulkSaleDialogState extends State<BulkSaleDialog> {
  final selected = <String>{};
  final asking = TextEditingController(), search = TextEditingController();
  bool saving = false;
  String? error;
  late final eligible = widget.animals
      .where(
        (a) =>
            a['status'] == 'active' &&
            a['pedigree_only'] != true &&
            !['for_sale', 'reserved'].contains(a['sale_status']),
      )
      .toList();
  @override
  void dispose() {
    asking.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    try {
      final amount = parseSaleMoney(asking.text);
      if (selected.isEmpty) throw StateError('Select at least one animal.');
      setState(() {
        saving = true;
        error = null;
      });
      await (widget.writer ?? SalesService.listAnimals)(
        eligible.where((a) => selected.contains(a['id'])).toList(),
        amount,
      );
      if (mounted) Navigator.pop(context, selected.length);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = e is FormatException
              ? e.message
              : e is StateError
              ? e.message
              : 'Unable to list these animals. Refresh to check for existing listings, then try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = eligible
        .where(
          (a) => '${a['name']} ${a['tattoo']} ${a['breed']}'
              .toLowerCase()
              .contains(search.text.toLowerCase()),
        )
        .toList();
    return PopScope(
      canPop: !saving,
      child: AlertDialog(
        title: const Text('Mark animals For Sale'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: AbsorbPointer(
              absorbing: saving,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Select active animals. Each gets its own sale record. Existing listings are excluded.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: asking,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Asking price per animal (USD)',
                      helperText:
                          'Optional. You can set individual prices later.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Find animals',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  CheckboxListTile(
                    title: const Text('Select all matching animals'),
                    value:
                        visible.isNotEmpty &&
                        visible.every((a) => selected.contains(a['id'])),
                    onChanged: (v) => setState(() {
                      for (final a in visible) {
                        if (v == true) {
                          selected.add(a['id']);
                        } else {
                          selected.remove(a['id']);
                        }
                      }
                    }),
                  ),
                  if (visible.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No eligible animals.'),
                    ),
                  for (final a in visible)
                    CheckboxListTile(
                      title: Text(animalTitle(a['name'], a['tattoo'])),
                      subtitle: Text(a['breed'] ?? ''),
                      value: selected.contains(a['id']),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          selected.add(a['id']);
                        } else {
                          selected.remove(a['id']);
                        }
                      }),
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
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: saving ? null : save,
            child: Text(saving ? 'Saving…' : 'List ${selected.length} animals'),
          ),
        ],
      ),
    );
  }
}
