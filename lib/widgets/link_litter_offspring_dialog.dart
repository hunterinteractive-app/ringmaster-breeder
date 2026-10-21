import 'package:flutter/material.dart';
import 'adaptive_layout.dart';

class LinkLitterOffspringDialog extends StatefulWidget {
  final List<Map<String, dynamic>> animals;
  final Set<String> linked;
  final int? limit;
  final Future<void> Function(List<String>) writer;
  const LinkLitterOffspringDialog({
    super.key,
    required this.animals,
    required this.linked,
    this.limit,
    required this.writer,
  });
  @override
  State<LinkLitterOffspringDialog> createState() =>
      _LinkLitterOffspringDialogState();
}

class _LinkLitterOffspringDialogState extends State<LinkLitterOffspringDialog> {
  late final selected = {...widget.linked};
  bool saving = false;
  String? error;
  Future<void> save() async {
    if (selected.isEmpty ||
        widget.limit != null && selected.length > widget.limit!) {
      setState(
        () => error = 'Choose offspring within the recorded weaning total.',
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.writer(selected.toList());
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error =
              'Unable to confirm links. Refresh and retry; linked rabbits will be reused.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AdaptiveFormDialog(
    title: const Text('Link existing offspring'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Choose rabbits already in your herd. Only matching parents and compatible birth dates are listed. This adds litter links without creating another animal.',
        ),
        const SizedBox(height: 12),
        if (error != null) Text(error!),
        Text(
          '${selected.length} selected${widget.limit == null ? '' : ' of ${widget.limit} weaned'}',
        ),
        if (widget.animals.isEmpty)
          const Text(
            'No matching rabbits found. Check the recorded parents and birth dates.',
          ),
        for (final a in widget.animals)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${a['name'] ?? 'Unnamed'} · ${a['tattoo'] ?? ''}'),
            subtitle: Text(
              '${a['sex'] ?? ''} · Born ${a['dob'] ?? 'unknown'}${widget.linked.contains(a['id']) ? ' · Already linked' : ''}',
            ),
            value: selected.contains(a['id']),
            onChanged: saving || widget.linked.contains(a['id'])
                ? null
                : (v) => setState(() {
                    if (v == true) {
                      selected.add(a['id']);
                    } else {
                      selected.remove(a['id']);
                    }
                  }),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: saving ? null : save,
        child: Text(saving ? 'Linking…' : 'Link selected rabbits'),
      ),
    ],
  );
}
