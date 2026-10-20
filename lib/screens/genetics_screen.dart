import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/genetics_preview.dart';
import '../genetics/color_prediction.dart';
import '../offline/offline_runtime.dart';
import '../utils/animal_labels.dart';
import '../utils/color_details.dart';
import '../widgets/ringmaster_page_shell.dart';
import '../widgets/genetics_prediction_results.dart';

class GeneticsScreen extends StatelessWidget {
  final List<Map<String, dynamic>> animals;
  const GeneticsScreen({super.key, required this.animals});

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
    stream: OfflineRuntime.client.auth.onAuthStateChange,
    builder: (context, _) => RingMasterPageShell(
      title: 'Genetics',
      useScrollView: true,
      bodyPadding: const EdgeInsets.all(16),
      bodyMaxWidth: 760,
      body:
          GeneticsPreview.allowsEmail(
            OfflineRuntime.client.auth.currentUser?.email,
          )
          ? GeneticsPreviewForm(animals: animals)
          : const Text('This preview is not available for this account.'),
    ),
  );
}

/// Private calculator. Selections and carrier inputs never change rabbit records.
class GeneticsPreviewForm extends StatefulWidget {
  final List<Map<String, dynamic>> animals;
  const GeneticsPreviewForm({super.key, required this.animals});

  @override
  State<GeneticsPreviewForm> createState() => _GeneticsPreviewFormState();
}

class _GeneticsPreviewFormState extends State<GeneticsPreviewForm> {
  String? _buckId, _doeId;
  ColorCarrierDetails _buckCarriers = const ColorCarrierDetails();
  ColorCarrierDetails _doeCarriers = const ColorCarrierDetails();
  ColorPrediction? _prediction;
  String? _buckInput, _doeInput;
  final _predictionKey = GlobalKey();

  // Retain value snapshots: sync can update the existing maps in place. A
  // calculated result and temporary facts must not outlive changed inputs.
  String? _inputSnapshot(Map<String, dynamic>? animal) => animal == null
      ? null
      : jsonEncode({
          for (final key in const [
            'species',
            'breed',
            'variety',
            'sex',
            'status',
            'pedigree_only',
            'color_details',
            'genotype',
          ])
            key: animal[key],
        }, toEncodable: (value) => value.toString());

  void _rememberInputs() {
    _buckInput = _inputSnapshot(_selected(true));
    _doeInput = _inputSnapshot(_selected(false));
  }

  @override
  void didUpdateWidget(covariant GeneticsPreviewForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    for (final male in [true, false]) {
      final id = male ? _buckId : _doeId;
      final eligible = _parents(male).any((a) => a['id'] == id);
      final current = eligible ? _inputSnapshot(_selected(male)) : null;
      if ((male ? _buckInput : _doeInput) != current ||
          (id != null && !eligible)) {
        if (male) {
          if (!eligible) _buckId = null;
          _buckCarriers = const ColorCarrierDetails();
        } else {
          if (!eligible) _doeId = null;
          _doeCarriers = const ColorCarrierDetails();
        }
        _prediction = null;
      }
    }
    _rememberInputs();
  }

  @override
  void reassemble() {
    super.reassemble();
    // Recalculate derived estimates after rules change during local testing.
    _prediction = null;
  }

  Map<String, dynamic>? _selected(bool male) => widget.animals
      .where((a) => a['id'] == (male ? _buckId : _doeId))
      .firstOrNull;

  List<Map<String, dynamic>> _parents(bool male) {
    String normalized(dynamic value) =>
        value?.toString().trim().toLowerCase() ?? '';
    final otherId = male ? _doeId : _buckId;
    final other = widget.animals.where((a) => a['id'] == otherId).firstOrNull;
    final preferredBreed = normalized(other?['breed']);
    return widget.animals.where((a) {
      final sex = a['sex']?.toString().trim().toLowerCase();
      return a['species']?.toString().toLowerCase() == 'rabbit' &&
          a['status'] == 'active' &&
          a['pedigree_only'] != true &&
          (male
              ? ['m', 'male', 'buck'].contains(sex)
              : ['f', 'female', 'doe'].contains(sex));
    }).toList()..sort((a, b) {
      final aBreed = normalized(a['breed']);
      final bBreed = normalized(b['breed']);
      if (preferredBreed.isNotEmpty) {
        final aPreferred = aBreed == preferredBreed;
        final bPreferred = bBreed == preferredBreed;
        if (aPreferred != bPreferred) return aPreferred ? -1 : 1;
      }
      // Put missing breeds after named breeds rather than above the A's.
      if (aBreed.isEmpty != bBreed.isEmpty) return aBreed.isEmpty ? 1 : -1;
      final breedOrder = aBreed.compareTo(bBreed);
      if (breedOrder != 0) return breedOrder;
      final varietyOrder = normalized(
        varietyLabel(a),
      ).compareTo(normalized(varietyLabel(b)));
      if (varietyOrder != 0) return varietyOrder;
      final nameOrder = normalized(
        animalTitle(a['name'], a['tattoo']),
      ).compareTo(normalized(animalTitle(b['name'], b['tattoo'])));
      return nameOrder != 0
          ? nameOrder
          : normalized(a['id']).compareTo(normalized(b['id']));
    });
  }

  Widget _rabbitLabel(Map<String, dynamic> animal) {
    final breed = animal['breed']?.toString().trim() ?? '';
    final variety = varietyLabel(animal);
    final dob = DateTime.tryParse(animal['dob']?.toString() ?? '');
    final detailsStyle = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            animalTitle(animal['name'], animal['tattoo']),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Breed: ${breed.isEmpty ? 'Not recorded' : breed}'
            '${animal['breed_unrecognized'] == true ? ' (Unrecognized)' : ''}'
            ' • Variety: ${variety.isEmpty ? 'Not recorded' : variety}'
            '${animal['variety_unrecognized'] == true ? ' (Unrecognized)' : ''}',
            style: detailsStyle,
          ),
          Text(
            'Rabbit • ${sexLabel('rabbit', animal['sex'] ?? '')} • Active',
            style: detailsStyle,
          ),
          Text(
            'DOB: ${dob == null ? 'Not recorded' : DateFormat('MM/dd/yyyy').format(dob)}',
            style: detailsStyle,
          ),
        ],
      ),
    );
  }

  Widget _selector(bool male) {
    final parents = _parents(male);
    final selectedId = male ? _buckId : _doeId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('parent-$male-$selectedId'),
          initialValue: selectedId,
          itemHeight: null,
          isDense: false,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: male ? '1. Choose a buck' : '2. Choose a doe',
          ),
          hint: Text(
            parents.isEmpty ? 'No active rabbits available' : 'Select rabbit',
          ),
          items: parents
              .map(
                (a) => DropdownMenuItem<String>(
                  value: a['id'] as String,
                  child: _rabbitLabel(a),
                ),
              )
              .toList(),
          onChanged: parents.isEmpty
              ? null
              : (value) => setState(() {
                  if (male) {
                    if (_buckId != value) {
                      _buckCarriers = const ColorCarrierDetails();
                    }
                    _buckId = value;
                  } else {
                    if (_doeId != value) {
                      _doeCarriers = const ColorCarrierDetails();
                    }
                    _doeId = value;
                  }
                  _rememberInputs();
                  _prediction = null;
                }),
        ),
        KeyedSubtree(
          key: ValueKey('carrier-$male-${_inputSnapshot(_selected(male))}'),
          child: _carrierControls(male),
        ),
      ],
    );
  }

  Widget _carrierControls(bool male) {
    final animal = _selected(male);
    if (animal == null) return const SizedBox.shrink();
    final loci = RabbitColorPredictions.carrierLoci(animal);
    if (loci.isEmpty) return const SizedBox.shrink();
    final carriers = male ? _buckCarriers : _doeCarriers;
    void save(ColorCarrierDetails updated) => setState(() {
      if (male) {
        _buckCarriers = updated;
      } else {
        _doeCarriers = updated;
      }
      _prediction = null;
    });
    Widget field(
      String locus,
      String label,
      CarrierKnowledge current,
      ValueChanged<CarrierKnowledge> update,
    ) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: DropdownButtonFormField<CarrierKnowledge>(
        key: ValueKey('${animal['id']}-$male-$locus'),
        initialValue: current,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: const [
          DropdownMenuItem(
            value: CarrierKnowledge.unknown,
            child: Text('Unknown'),
          ),
          DropdownMenuItem(
            value: CarrierKnowledge.yes,
            child: Text('Yes — known carrier'),
          ),
          DropdownMenuItem(
            value: CarrierKnowledge.no,
            child: Text('No — known non-carrier'),
          ),
        ],
        onChanged: (value) {
          if (value != null) update(value);
        },
      ),
    );
    return ExpansionTile(
      key: ValueKey('carriers-$male-${animal['id']}'),
      tilePadding: EdgeInsets.zero,
      title: const Text('Optional: known carrier information'),
      children: [
        const Text(
          'Leave Unknown unless you have reliable genetic or breeding evidence. These choices apply only to this preview and are not saved to the rabbit record.',
        ),
        if (loci.contains('B'))
          field(
            'B',
            'Carries chocolate?',
            carriers.chocolate,
            (v) => save(carriers.copyWith(chocolate: v)),
          ),
        if (loci.contains('D'))
          field(
            'D',
            'Carries dilute (blue / lilac)?',
            carriers.dilute,
            (v) => save(carriers.copyWith(dilute: v)),
          ),
        if (loci.contains('E'))
          const Text(
            'Non-extension (e) is a hidden gene that can affect tortoise, orange and related color families.',
          ),
        if (loci.contains('E'))
          field(
            'E',
            'Carries non-extension (e)?',
            carriers.tortoise,
            (v) => save(carriers.copyWith(tortoise: v)),
          ),
        if (loci.contains('c'))
          field(
            'c',
            'Carries albino white (c)?',
            carriers.albino,
            (v) => save(carriers.copyWith(albino: v)),
          ),
        if (loci.contains('v'))
          field(
            'v',
            'Carries Vienna white (v)?',
            carriers.vienna,
            (v) => save(carriers.copyWith(vienna: v)),
          ),
        if (loci.contains('c') || loci.contains('v'))
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Albino white and Vienna white are different factors. A rabbit’s visible color alone does not establish that it carries either one.',
            ),
          ),
        if (loci.contains('a'))
          field(
            'a',
            'Carries self pattern (a)?',
            carriers.selfPattern,
            (v) => save(carriers.copyWith(selfPattern: v)),
          ),
        if (loci.contains('ej'))
          field(
            'ej',
            'Carries Harlequin (ej)?',
            carriers.harlequin,
            (v) => save(carriers.copyWith(harlequin: v)),
          ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _results() {
    final buck = _selected(true), doe = _selected(false);
    final hasParents = buck != null && doe != null;
    final issue = hasParents
        ? RabbitColorPredictions.inputIssue(buck, doe) ??
              RabbitColorPredictions.carrierIssue(
                buck,
                doe,
                sireCarriers: _buckCarriers,
                damCarriers: _doeCarriers,
              )
        : null;
    final prediction = hasParents && issue == null ? _prediction : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '3. See possible colors',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (!hasParents)
          const Text('Choose a buck and a doe to see possible colors.'),
        if (issue != null) _PredictionUnavailable(reason: issue),
        const SizedBox(height: 12),
        if (hasParents && issue == null)
          Text(RabbitColorPredictions.scopeFor(buck, doe)),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: !hasParents || issue != null
              ? null
              : () => setState(() {
                  _prediction = RabbitColorPredictions.predict(
                    sire: buck,
                    dam: doe,
                    sireCarriers: _buckCarriers,
                    damCarriers: _doeCarriers,
                  );
                  // Results can start below the fold, especially with large
                  // text. Reveal the new result after it has been laid out.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    final resultContext = _predictionKey.currentContext;
                    if (mounted &&
                        _prediction != null &&
                        resultContext != null) {
                      Scrollable.ensureVisible(
                        resultContext,
                        alignment: 0,
                        duration: const Duration(milliseconds: 200),
                      );
                    }
                  });
                }),
          icon: const Icon(Icons.science_outlined),
          label: const Text('See Possible Colors'),
        ),
        if (prediction != null) ...[
          const SizedBox(height: 20),
          GeneticsPredictionResults(
            key: _predictionKey,
            prediction: prediction,
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Possible offspring colors',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      const Text('Private preview • In development'),
      const SizedBox(height: 16),
      const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(GeneticsPreview.disclaimer),
        ),
      ),
      const SizedBox(height: 20),
      const Text(
        'Choose two active rabbits from this Ring. Selecting rabbits here does not record a breeding.',
      ),
      const SizedBox(height: 20),
      _selector(true),
      const SizedBox(height: 20),
      _selector(false),
      const SizedBox(height: 24),
      _results(),
    ],
  );
}

/// Explain unsupported or incompatible selections where the result would appear.
class _PredictionUnavailable extends StatelessWidget {
  final String reason;
  const _PredictionUnavailable({required this.reason});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Card(
        margin: EdgeInsets.zero,
        color: colors.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: colors.onErrorContainer),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.error_outline, color: colors.onErrorContainer),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Prediction unavailable',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(reason),
                const SizedBox(height: 12),
                const SelectableText(
                  'For help, reach out to support@ringmasterone.com. Include both rabbits’ breeds and varieties so we can help with this pairing.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
