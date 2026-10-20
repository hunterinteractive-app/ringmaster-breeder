import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/genetics_preview.dart';
import '../genetics/animal_genotype.dart';
import '../genetics/color_prediction.dart';
import '../genetics/what_if_prediction.dart';
import '../offline/offline_runtime.dart';
import '../services/what_if_catalog.dart';
import '../widgets/animal_genotype_section.dart';
import '../widgets/color_details_fields.dart';
import '../widgets/genetics_prediction_results.dart';
import '../widgets/ringmaster_page_shell.dart';

bool _allowed() =>
    GeneticsPreview.allowsEmail(OfflineRuntime.client.auth.currentUser?.email);

class WhatIfScreen extends StatelessWidget {
  final Future<WhatIfCatalog> Function()? catalogLoader;
  const WhatIfScreen({super.key, this.catalogLoader});

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
    stream: OfflineRuntime.client.auth.onAuthStateChange,
    builder: (context, _) => RingMasterPageShell(
      title: 'What Ifs',
      useScrollView: true,
      bodyPadding: const EdgeInsets.all(16),
      bodyMaxWidth: 760,
      body: _allowed()
          ? WhatIfForm(catalogLoader: catalogLoader)
          : const Text('This preview is not available for this account.'),
    ),
  );
}

class WhatIfForm extends StatefulWidget {
  final Future<WhatIfCatalog> Function()? catalogLoader;
  const WhatIfForm({super.key, this.catalogLoader});
  @override
  State<WhatIfForm> createState() => _WhatIfFormState();
}

class _WhatIfFormState extends State<WhatIfForm> {
  final _breeds = [TextEditingController(), TextEditingController()];
  final _varieties = [TextEditingController(), TextEditingController()];
  var _details = <Map<String, String>>[{}, {}];
  var _genes = <Map<String, dynamic>>[{}, {}];
  WhatIfCatalog _catalog = const WhatIfCatalog();
  bool _loading = true, _catalogError = false;
  ColorPrediction? _prediction;
  String? _error;
  final _generation = [0, 0];
  final _resultsKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _loading = true;
      _catalogError = false;
    });
    try {
      final result = await (widget.catalogLoader ?? WhatIfCatalog.load)();
      if (mounted) setState(() => _catalog = result);
    } catch (_) {
      if (mounted) setState(() => _catalogError = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    for (final c in [..._breeds, ..._varieties]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void reassemble() {
    super.reassemble();
    _prediction = null;
  }

  Map<String, dynamic> _parent(int i) => {
    'species': 'rabbit',
    'breed': _breeds[i].text.trim(),
    'variety': _varieties[i].text.trim(),
    'color_details': _details[i],
    'genotype': _genes[i],
  };

  void _changed(int i) => setState(() {
    _details[i] = {};
    _genes[i] = {};
    _generation[i]++;
    _prediction = null;
    _error = null;
  });

  Future<void> _editGenes(int i) async {
    await showDialog<void>(
      context: context,
      builder: (_) => StreamBuilder<AuthState>(
        stream: OfflineRuntime.client.auth.onAuthStateChange,
        builder: (context, _) => mounted && _allowed()
            ? AnimalGenotypeDialog(
                hypothetical: true,
                initial: AnimalGenotype.read(_genes[i]),
                colorInference: AnimalGenotype.colorInference(_parent(i)),
                onSave: (value) async {
                  if (!mounted || !_allowed()) return;
                  setState(() {
                    _genes[i] = value;
                    _prediction = null;
                    _error = null;
                  });
                },
              )
            : AlertDialog(
                title: const Text(
                  'This preview is not available for this account.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _browse(int i, bool breed) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => _ChoiceDialog(
        title: breed ? 'Choose breed' : 'All rabbit varieties',
        choices: breed ? _catalog.breeds : _catalog.varieties,
      ),
    );
    if (choice == null || !mounted) return;
    (breed ? _breeds[i] : _varieties[i]).text = choice;
    _changed(i);
  }

  Widget _field(int i, bool breed) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      key: ValueKey('${breed ? 'breed' : 'variety'}-$i'),
      controller: breed ? _breeds[i] : _varieties[i],
      maxLength: 100,
      decoration: InputDecoration(
        labelText: breed ? 'Breed' : 'Variety',
        helperText: breed
            ? 'Choose or type a breed'
            : 'All varieties, regardless of breed',
        suffixIcon: IconButton(
          tooltip:
              '${breed ? 'Browse breeds' : 'Browse all varieties'} ${i == 0 ? 'buck' : 'doe'}',
          onPressed: _loading ? null : () => _browse(i, breed),
          icon: const Icon(Icons.arrow_drop_down),
        ),
      ),
      onChanged: (_) => _changed(i),
    ),
  );

  Widget _panel(int i) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            i == 0 ? '1. Hypothetical buck' : '2. Hypothetical doe',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          _field(i, true),
          _field(i, false),
          ColorDetailsFields(
            key: ValueKey('details-$i-${_generation[i]}'),
            breed: _breeds[i].text,
            variety: _varieties[i].text,
            value: _details[i],
            onChanged: (v) => setState(() {
              _details[i] = v;
              _prediction = null;
              _error = null;
            }),
          ),
          const SizedBox(height: 8),
          Text(
            AnimalGenotype.read(_genes[i])?.notation ??
                'Genotype: color-based estimate; other genes Unknown',
          ),
          TextButton.icon(
            onPressed: () => _editGenes(i),
            icon: const Icon(Icons.tune),
            label: const Text('Hypothetical genotype'),
          ),
        ],
      ),
    ),
  );

  void _calculate() {
    FocusManager.instance.primaryFocus?.unfocus();
    final s = _parent(0), d = _parent(1);
    final issue = WhatIfPredictions.inputIssue(s, d);
    setState(() {
      _prediction = null;
      _error = issue;
      if (issue == null) {
        _prediction = WhatIfPredictions.predict(sire: s, dam: d);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _resultsKey.currentContext;
      if (mounted && target != null) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 250),
          alignment: .05,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Try a pairing without adding rabbits',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      const Text(
        'Mix breeds and varieties freely. These parents and gene choices are temporary and never change your herd records. Some combinations need additional color details or are not supported yet.',
      ),
      const SizedBox(height: 12),
      const Text(GeneticsPreview.disclaimer),
      if (_loading) const LinearProgressIndicator(),
      if (_catalogError) ...[
        const Text(
          'The catalog could not be loaded. You can still type breeds and varieties.',
        ),
        TextButton(onPressed: _loadCatalog, child: const Text('Retry catalog')),
      ],
      const SizedBox(height: 16),
      LayoutBuilder(
        builder: (context, constraints) =>
            constraints.maxWidth >= 650 &&
                MediaQuery.textScalerOf(context).scale(14) <= 20
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _panel(0)),
                  const SizedBox(width: 12),
                  Expanded(child: _panel(1)),
                ],
              )
            : Column(children: [_panel(0), _panel(1)]),
      ),
      Wrap(
        spacing: 12,
        children: [
          TextButton.icon(
            icon: const Icon(Icons.swap_horiz),
            label: const Text('Swap parents'),
            onPressed: () => setState(() {
              final b = _breeds[0].text, v = _varieties[0].text;
              _breeds[0].text = _breeds[1].text;
              _varieties[0].text = _varieties[1].text;
              _breeds[1].text = b;
              _varieties[1].text = v;
              _genes = _genes.reversed.toList();
              _details = _details.reversed.toList();
              _generation[0]++;
              _generation[1]++;
              _prediction = null;
              _error = null;
            }),
          ),
          TextButton(
            onPressed: () => setState(() {
              for (final c in [..._breeds, ..._varieties]) {
                c.clear();
              }
              _genes = [{}, {}];
              _details = [{}, {}];
              _generation[0]++;
              _generation[1]++;
              _prediction = null;
              _error = null;
            }),
            child: const Text('Start over'),
          ),
        ],
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _calculate,
        icon: const Icon(Icons.science_outlined),
        label: const Text('See possible colors'),
      ),
      const SizedBox(height: 16),
      Container(
        key: _resultsKey,
        child: _error != null
            ? Semantics(liveRegion: true, child: Text(_error!))
            : _prediction != null
            ? GeneticsPredictionResults(prediction: _prediction!)
            : const SizedBox.shrink(),
      ),
    ],
  );
}

class _ChoiceDialog extends StatefulWidget {
  final String title;
  final List<String> choices;
  const _ChoiceDialog({required this.title, required this.choices});
  @override
  State<_ChoiceDialog> createState() => _ChoiceDialogState();
}

class _ChoiceDialogState extends State<_ChoiceDialog> {
  String _search = '';
  @override
  Widget build(BuildContext context) {
    final choices = widget.choices
        .where((c) => c.toLowerCase().contains(_search))
        .toList();
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 500,
        height: MediaQuery.sizeOf(context).height * .55,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Search'),
              onChanged: (s) =>
                  setState(() => _search = s.trim().toLowerCase()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: choices.isEmpty
                  ? const Text(
                      'No matches. Close this list to type your own value.',
                    )
                  : ListView.builder(
                      itemCount: choices.length,
                      itemBuilder: (context, i) => ListTile(
                        title: Text(choices[i]),
                        onTap: () => Navigator.pop(context, choices[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
