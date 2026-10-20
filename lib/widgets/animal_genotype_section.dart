import 'package:flutter/material.dart';

import '../genetics/animal_genotype.dart';
import '../genetics/coat_rules.dart';
import '../genetics/genotype_choices.dart';
import '../services/animal_service.dart';

class AnimalGenotypeSection extends StatelessWidget {
  final Map<String, dynamic> animal;
  final VoidCallback? onChange;
  const AnimalGenotypeSection({super.key, required this.animal, this.onChange});

  @override
  Widget build(BuildContext context) {
    AnimalGenotype? saved;
    String? problem;
    try {
      saved = AnimalGenotype.read(animal['genotype']);
    } on FormatException {
      problem =
          'Saved genotype could not be read. Contact support@ringmasterone.com for help.';
    }
    final inferred = problem == null && saved == null
        ? AnimalGenotype.colorInference(animal)
        : null;
    final notes = <String>[
      if (problem != null) problem,
      if (saved != null) ...[
        AnimalGenotype.bases[saved.basis]!,
        if (saved.source.isNotEmpty) 'Source: ${saved.source}',
      ] else if (inferred != null)
        'Inferred from recorded color — partial. Other genes remain unknown. This estimate has not been saved to the animal.',
      if (problem == null)
        'A genotype may be incomplete or inferred. A dash or question mark means an allele is unknown. Compatible saved genes help narrow offspring predictions. Unknown genes remain unresolved; saved entries are not independently verified.',
    ].join('\n\n');
    final helpKey = GlobalKey<TooltipState>();
    const label = Text(
      'Genotype:',
      style: TextStyle(fontWeight: FontWeight.bold),
    );
    final help = Tooltip(
      key: helpKey,
      message: notes,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 15),
      constraints: BoxConstraints(
        maxWidth: (MediaQuery.sizeOf(context).width - 32).clamp(0, 420),
      ),
      child: IconButton(
        onPressed: () => helpKey.currentState?.ensureTooltipVisible(),
        icon: const Icon(Icons.info_outline, size: 18),
      ),
    );
    final edit = onChange != null && problem == null
        ? IconButton(
            tooltip: 'Change genotype',
            onPressed: onChange,
            icon: const Icon(Icons.edit_outlined, size: 20),
          )
        : null;
    final value = problem != null
        ? 'Unavailable'
        : saved?.notation ?? inferred ?? 'Not recorded';
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 480;
        final notation = Expanded(
          child: SelectableText(value, textAlign: TextAlign.right),
        );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Flexible(child: label),
                        help,
                      ],
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [notation, if (edit != null) edit],
                    ),
                  ],
                )
              : Row(
                  children: [
                    label,
                    help,
                    const SizedBox(width: 12),
                    notation,
                    if (edit != null) edit,
                  ],
                ),
        );
      },
    );
  }
}

class AnimalGenotypeDialog extends StatefulWidget {
  final AnimalGenotype? initial;
  final String? colorInference;
  final Future<void> Function(Map<String, dynamic>) onSave;
  final bool storageReady;
  const AnimalGenotypeDialog({
    super.key,
    this.initial,
    this.colorInference,
    required this.onSave,
    this.storageReady = true,
  });

  @override
  State<AnimalGenotypeDialog> createState() => _AnimalGenotypeDialogState();
}

class _AnimalGenotypeDialogState extends State<AnimalGenotypeDialog> {
  late final notation = TextEditingController(
    text: widget.initial?.notation ?? '',
  );
  late final source = TextEditingController(text: widget.initial?.source ?? '');
  late String basis = widget.initial?.basis ?? 'breeder_entered';
  bool saving = false, conflicted = false;
  String? error;

  late GenotypeChoices? choices = GenotypeChoices.read(notation.text);
  void _typedNotation() {
    setState(() {
      choices = GenotypeChoices.read(notation.text);
      basis = 'breeder_entered';
    });
  }

  void _replaceNotation(String text) {
    notation.text = text;
    choices = GenotypeChoices.read(text);
  }

  void _choose(String locus, int copy, String? value) {
    final current = choices?.pairs[locus];
    setState(() {
      _replaceNotation(
        GenotypeChoices.change(
          notation.text,
          locus,
          copy == 0 ? value : current?.first,
          copy == 1 ? value : current?.second,
        ),
      );
      basis = 'breeder_entered';
    });
  }

  static const geneNames = {
    'A': 'Color pattern (A)',
    'B': 'Black / chocolate (B)',
    'C': 'Full color / shaded / white (C)',
    'D': 'Dense / dilute (D)',
    'E': 'Color extension (E)',
    'En': 'Broken pattern (En)',
    'V': 'Vienna (V)',
  };

  static const alleleNames = {
    'A': 'Agouti pattern',
    'at': 'Tan pattern',
    'a': 'Self pattern',
    'B': 'Black base',
    'b': 'Chocolate base',
    'C': 'Full color',
    'cchd': 'Chinchilla dark',
    'cchl': 'Sable / shaded',
    'ch': 'Himalayan',
    'c': 'Albino',
    'D': 'Dense color',
    'd': 'Dilute color',
    'Es': 'Steel',
    'E': 'Normal extension',
    'ej': 'Harlequin',
    'e': 'Non-extension',
    'En': 'Broken factor',
    'en': 'Non-broken factor',
    'V': 'Non-Vienna',
    'v': 'Vienna factor',
  };

  Widget _guidedChoices() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Choose only genes you know; leave anything uncertain as Unknown. Each gene has two copies. These labels describe gene factors, not guaranteed appearance.',
      ),
      if (choices == null)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            'This notation includes information the guided choices cannot read. It is preserved under Advanced. Edit it there; nothing will be removed automatically.',
          ),
        ),
      if (choices != null)
        for (final entry in coatDomains.entries)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  geneNames[entry.key]!,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns =
                        constraints.maxWidth >= 300 &&
                            MediaQuery.textScalerOf(context).scale(14) <= 20
                        ? 2
                        : 1;
                    final width =
                        (constraints.maxWidth - (columns - 1) * 12) / columns;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (var copy = 0; copy < 2; copy++)
                          SizedBox(
                            width: width,
                            child: Builder(
                              builder: (context) {
                                final pair = choices?.pairs[entry.key];
                                final value = copy == 0
                                    ? pair?.first
                                    : pair?.second;
                                return DropdownButtonFormField<String>(
                                  key: ValueKey(
                                    'allele-${entry.key}-$copy-${value ?? 'unknown'}',
                                  ),
                                  initialValue: value ?? 'unknown',
                                  isExpanded: true,
                                  itemHeight: null,
                                  selectedItemBuilder: (_) => [
                                    const Text('Unknown'),
                                    for (final allele in entry.value)
                                      Text(allele),
                                  ],
                                  decoration: InputDecoration(
                                    labelText: '${entry.key} copy ${copy + 1}',
                                  ),
                                  items: [
                                    const DropdownMenuItem(
                                      value: 'unknown',
                                      child: Text('Unknown'),
                                    ),
                                    for (final allele in entry.value)
                                      DropdownMenuItem(
                                        value: allele,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                          child: Text(
                                            '$allele · ${alleleNames[allele]}',
                                          ),
                                        ),
                                      ),
                                  ],
                                  onChanged:
                                      saving || conflicted || choices == null
                                      ? null
                                      : (v) => _choose(
                                          entry.key,
                                          copy,
                                          v == 'unknown' ? null : v,
                                        ),
                                );
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
    ],
  );

  @override
  void dispose() {
    notation.dispose();
    source.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || conflicted || !widget.storageReady) return;
    final validation = AnimalGenotype.validate(notation.text, source.text);
    if (validation != null) {
      setState(() => error = validation);
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onSave(
        AnimalGenotype(
          notation: notation.text,
          basis: basis,
          source: source.text,
        ).toJson(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        conflicted = e is AnimalEditConflict;
        error = conflicted
            ? 'This animal changed while you were editing. Close this window and reopen the animal before saving.'
            : 'Unable to save the genotype. Your entry is still here. Check your connection or contact support@ringmasterone.com for help.';
      });
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      title: const Text('Change genotype'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.storageReady) ...[
                const SizedBox(height: 12),
                const Text(
                  'Genotype saving is not available in this preview yet. Contact support@ringmasterone.com for help.',
                ),
              ],
              const SizedBox(height: 16),
              ExpansionTile(
                key: const ValueKey('genotype-advanced'),
                initiallyExpanded: choices == null,
                tilePadding: EdgeInsets.zero,
                title: const Text('Advanced: type or paste genotype'),
                children: [
                  const Text(
                    'Keep the original notation, including unknown _, - or ? symbols. Advanced entries are saved as references without biological verification. Editing marks the entry as Breeder entered; review its source below.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('genotype-notation'),
                    onChanged: (_) => _typedNotation(),
                    controller: notation,
                    enabled: !saving && !conflicted,
                    maxLength: 500,
                    minLines: 2,
                    maxLines: 5,
                    autocorrect: false,
                    enableSuggestions: false,
                    textCapitalization: TextCapitalization.none,
                    decoration: const InputDecoration(
                      labelText: 'Genotype',
                      hintText: 'Example: aa bb C- D- E-',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _guidedChoices(),
              const SizedBox(height: 16),
              const Text(
                'Genotype preview',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SelectableText(
                notation.text.trim().isEmpty
                    ? 'No genes recorded — all unknown'
                    : notation.text,
                key: const ValueKey('genotype-preview'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: basis,
                key: ValueKey(basis),
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'How was it obtained?',
                ),
                items: [
                  for (final e in AnimalGenotype.bases.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: saving || conflicted
                    ? null
                    : (v) => setState(() => basis = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('genotype-source'),
                controller: source,
                enabled: !saving && !conflicted,
                maxLength: 300,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(
                  labelText: 'Source or explanation (optional)',
                  hintText: 'Example: Rabbit Register or breeding records',
                ),
              ),
              if (widget.colorInference != null)
                TextButton(
                  onPressed: saving || conflicted
                      ? null
                      : () => setState(() {
                          _replaceNotation(widget.colorInference!);
                          source.text =
                              'Recorded color only; partial interpretation';
                          basis = 'inferred';
                        }),
                  child: const Text('Use color-based estimate'),
                ),
              const Text(
                'Compatible saved genes help narrow offspring predictions. Unknown genes remain unresolved; saved entries are not independently verified.',
              ),
              TextButton(
                onPressed: saving || conflicted
                    ? null
                    : () => setState(() {
                        _replaceNotation('');
                        source.clear();
                        basis = 'breeder_entered';
                      }),
                child: const Text('Clear genotype'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(liveRegion: true, child: Text(error!)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving || conflicted || !widget.storageReady ? null : save,
          child: Text(saving ? 'Saving…' : 'Save genotype'),
        ),
      ],
    ),
  );
}
