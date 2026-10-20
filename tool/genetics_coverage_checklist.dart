import 'dart:convert';
import 'package:ringmaster_breeder/genetics/color_prediction.dart';
import 'package:ringmaster_breeder/genetics/color_labels.dart';
import 'package:ringmaster_breeder/genetics/coat_groups.dart';
import 'package:ringmaster_breeder/genetics/spotted_breeds.dart';
import 'package:ringmaster_breeder/genetics/hotot_colors.dart';
import 'package:ringmaster_breeder/genetics/silvered_breeds.dart';
import 'package:ringmaster_breeder/genetics/breed_color_contexts.dart';

/// Mirrors the live picker identity policy. A regression test compares this
/// pure tooling implementation with CatalogService on the captured catalog.
String checklistIdentity(String value) {
  var key = value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  const accents = 'àáâãäåèéêëìíîïòóôõöùúûüýÿçñ';
  const plain = 'aaaaaaeeeeiiiiooooouuuuyycn';
  for (var i = 0; i < accents.length; i++) {
    key = key.replaceAll(accents[i], plain[i]);
  }
  key = key
      .replaceAll(RegExp(r'[\u0300-\u036f]'), '')
      .replaceAll(RegExp('[’‘]'), "'")
      .replaceAll(RegExp('[‐‑–—]'), '-')
      .replaceFirst(RegExp(r'\s*\(\s*cod\s*\)\s*$'), '')
      .trim();
  return switch (key) {
    "champagne d'argente" => "champagne d'argent",
    'peruvian stain' => 'peruvian satin',
    _ => key,
  };
}

const checklistStatusLabels = {
  'base_color_only': 'Limited base-color model',
  'silver_family_only': 'Underlying color only; silvering excluded',
  'shared_estimate': 'Shared estimate with limits',
  'spotted_estimate': 'Spotted-breed estimate with limits',
  'eyeband_pigment_only': 'Hotot pigment only; markings excluded',
  'needs_details': 'Needs color details / group handling',
  'needs_name_mapping': 'Needs name / Standard mapping',
  'needs_rules': 'Needs breed or color rules',
  'needs_identity_review': 'Needs catalog identity review',
};

List<Map<String, dynamic>> _maps(dynamic rows) =>
    List<Map<String, dynamic>>.from(rows as List? ?? const []);

String _breedLetters(String breed) =>
    checklistIdentity(breed).replaceAll(RegExp('[^a-z]'), '');

bool _specialBreed(String breed) => const {
  'dwarfhotot',
  'blancdehotot',
  'hotot',
  'englishspot',
  'checkeredgiant',
  'rhinelander',
  'dwarfpapillon',
  'silver',
  'silverfox',
  'argentbrun',
  'argentebrun',
  'argentesthubert',
  'champagnedargent',
  'cremedargent',
  'cremedargente',
}.contains(_breedLetters(breed));

bool _group(String variety, String? kind) =>
    kind == 'color_group' ||
    CoatGroup.fromLabel(checklistIdentity(variety)) != null;

Map<String, dynamic> classifyChecklistEntry(
  String breed,
  String variety, {
  String? kind,
  bool activeShowBreed = true,
}) {
  final animal = <String, dynamic>{
    'species': 'rabbit',
    'breed': breed,
    'variety': variety,
  };
  final issue = RabbitColorPredictions.inputIssue(animal, animal);
  final profile = RabbitColorPredictions.profileFor(animal);
  final scope = issue != null
      ? null
      : profile?.dutchColorOnly == true
      ? 'dutch_underlying_color'
      : SilveredBreedRules.appliesTo(animal)
      ? 'silver_underlying_color'
      : profile?.eyebandOnly == true && profile!.inputIssue(animal) == null
      ? 'eyeband_pigment'
      : profile != null && !profile.shared && profile.inputIssue(animal) == null
      ? 'limited_base_color'
      : SpottedBreedRules.handles(breed)
      ? 'spotted_coat'
      : 'shared_coat';
  String status, next;
  final name = checklistIdentity(variety);
  String? proposedLabel;
  if (!activeShowBreed) {
    status = 'needs_identity_review';
    next =
        'Reconcile this saved breed label with the active Show catalog; do not silently merge or delete it.';
  } else if (_specialBreed(breed) &&
      !SpottedBreedRules.handles(breed) &&
      !HototColorRules.handles(breed) &&
      !SilveredBreedRules.handles(breed)) {
    status = 'needs_rules';
    next =
        'Review and implement this breed’s coat/marking context before counting a generic estimate as breed coverage.';
  } else if (const {
        'lutino',
        'pearl',
        'silver/silver fox',
        'champagne',
        'brindle',
        'tan',
      }.contains(name) &&
      !SilveredBreedRules.appliesTo(animal) &&
      BreedColorContexts.kind(animal) == null) {
    status = 'needs_rules';
    next =
        'Review this named color or modifier against breed references, implement its interpretation and interactions, and add verified crosses.';
  } else if (checklistIdentity(breed) == 'palomino' &&
      name == 'lynx' &&
      BreedColorContexts.kind(animal) == null) {
    status = 'needs_rules';
    next =
        'Review the Palomino-specific Lynx interpretation; do not substitute generic genetic lynx.';
  } else if (issue == null) {
    status = scope == 'silver_underlying_color'
        ? 'silver_family_only'
        : scope == 'eyeband_pigment'
        ? 'eyeband_pigment_only'
        : scope == 'limited_base_color'
        ? 'base_color_only'
        : scope == 'spotted_coat'
        ? 'spotted_estimate'
        : 'shared_estimate';
    next = scope == 'dutch_underlying_color'
        ? 'Validate underlying-color family crosses. Dutch white markings, other spotting, exact shade and show quality remain excluded.'
        : status == 'silver_family_only'
        ? 'Underlying color-family estimates are available. Silvering inheritance/expression, age of onset, amount, placement, shade and show quality still need dedicated rules and validation.'
        : status == 'eyeband_pigment_only'
        ? 'Only B/D pigment inheritance is available. Eye-band formation, Dutch/spotting interactions, white masking, eye color and marking quality still need dedicated rules.'
        : status == 'base_color_only'
        ? 'Expand beyond the stated base-color/background assumptions, then validate same- and cross-variety pairings.'
        : 'Validate the breed-specific interpretation and pairings. Shade, exact markings and eye-color distinctions are not complete.';
  } else if (_group(variety, kind) ||
      name == 'white' ||
      SpottedBreedRules.detailExample(animal) != null ||
      HototColorRules.needsDetails(animal) ||
      BreedColorContexts.needsDetails(animal) ||
      SilveredBreedRules.needsDetails(animal)) {
    status = 'needs_details';
    next = name == 'white'
        ? 'Use reliable eye-color/white-type information; validate the breed interpretation. Do not guess from White alone.'
        : 'Require an actual underlying color or pattern detail; map the group label to those details and validate the result.';
  } else {
    var candidate = variety
        .replaceFirst(RegExp(r'\s*\(\s*cod\s*\)\s*$', caseSensitive: false), '')
        .trim();
    final suffix = RegExp(
      r'^(.*?)\s*\((broken|charlie)\)$',
      caseSensitive: false,
    ).firstMatch(candidate);
    if (suffix != null) candidate = '${suffix[2]} ${suffix[1]}';
    final candidateAnimal = {...animal, 'variety': candidate};
    final aliasCandidate =
        candidate != variety &&
        RabbitColorPredictions.inputIssue(candidateAnimal, candidateAnimal) ==
            null;
    if (name == 'standard' || aliasCandidate) {
      status = 'needs_name_mapping';
      next = name == 'standard'
          ? 'Document what Standard means for this breed, confirm the color interpretation, then add the breed-specific mapping and tests.'
          : 'Review this formatting/COD alias and preserve all explicit traits when mapping it; no production data is changed by this audit.';
      if (aliasCandidate) proposedLabel = candidate;
    } else {
      status = 'needs_rules';
      next =
          'Review this breed-specific color name or rule, document the interpretation, and add regression crosses.';
    }
  }
  final familyLimit =
      BreedColorContexts.limitationFor(animal, animal) ??
      SpottedBreedRules.familyLimitationFor(animal, animal);
  final interpretation =
      BreedColorContexts.interpretationNote(animal) ??
      SilveredBreedRules.interpretationNote(animal) ??
      HototColorRules.interpretationNote(animal) ??
      SpottedBreedRules.interpretationNote(animal) ??
      RabbitColorLabels.interpretationNote(animal);
  final group = CoatGroup.fromLabel(checklistIdentity(variety));
  final example = HototColorRules.needsDetails(animal)
      ? {'color': 'Black'}
      : SilveredBreedRules.detailExample(animal) ??
            BreedColorContexts.detailExample(animal) ??
            SpottedBreedRules.detailExample(animal) ??
            group?.exampleDetails;
  final acceptsExample =
      example != null &&
      RabbitColorPredictions.inputIssue(
            {...animal, 'color_details': example},
            {...animal, 'color_details': example},
          ) ==
          null;
  return {
    'status': status,
    'status_label': checklistStatusLabels[status],
    'calculator_accepts_recorded_label': issue == null,
    'calculator_scope': scope,
    if (scope == 'dutch_underlying_color') ...{
      'marking_predictions_available': false,
      'limitation': RabbitColorProfile.dutchModelLimits,
    },
    if (scope == 'silver_underlying_color') ...{
      'interpreted_underlying_color': SilveredBreedRules.colorOf(animal),
      'silvering_predictions_available': false,
      'limitation': SilveredBreedRules.limitation,
    },
    if (scope == 'eyeband_pigment') ...{
      'interpreted_pigment_label': HototColorRules.baseColorOf(animal),
      'marking_predictions_available': false,
      'limitation': HototColorRules.limitation,
    },
    if (status == 'spotted_estimate')
      'spotting_information':
          'Unknown unless explicitly recorded on the rabbit; the breed name alone does not fix it.',
    'interpreted_color_label': RabbitColorLabels.canonicalVariety(animal),
    if (interpretation != null) 'interpretation_note': interpretation,
    if (familyLimit != null) 'limitation': familyLimit,
    if (issue != null) 'calculator_issue': issue,
    if (proposedLabel != null) 'alias_candidate_for_review': proposedLabel,
    'next_action': status == 'needs_details' && acceptsExample
        ? 'Saved details can identify a supported color. Confirm the actual rabbit’s color; the tested example is not a default. Missing, conflicting or unsupported details still block prediction.'
        : next,
    'breed_validation_complete': false,
    if (BreedColorContexts.kind(animal) == 'dwarf lutino')
      'experimental_details_only': true,
    if (status == 'needs_details') ...{
      'details_handling_available': acceptsExample,
      if (acceptsExample) 'tested_details_example': example,
    },
  };
}

Map<String, dynamic> buildGeneticsChecklist(
  Map<String, dynamic> snapshot, {
  bool checkPairs = false,
}) {
  final sources = Map<String, dynamic>.from(snapshot['sources']);
  final breederRows = _maps(sources['breeder']['breeds']);
  final showRows = _maps(
    sources['show']['breeds'],
  ).where((b) => b['is_active'] == true).toList();
  final groups = <String, Map<String, dynamic>>{};
  final hidden = <Map<String, dynamic>>[];
  final showNames = <String, String>{};
  for (final breed in breederRows) {
    for (final v in _maps(breed['varieties'])) {
      if (v['show_id'] != null) {
        showNames[v['show_id'].toString()] = (v['standard_name'] ?? v['name'])
            .toString();
      }
    }
  }
  for (final source in ['breeder', 'show']) {
    for (final breed in source == 'breeder' ? breederRows : showRows) {
      if (breed['species'] != 'rabbit') continue;
      final name = breed['name'].toString();
      final key = checklistIdentity(name);
      final group = groups.putIfAbsent(
        key,
        () => {
          'breed': name,
          'identity': key,
          'source_breed_rows': <Map<String, dynamic>>[],
          'active_show_breed': false,
          'entries': <String, Map<String, dynamic>>{},
        },
      );
      (group['source_breed_rows'] as List).add({
        'source': source,
        'id': breed['id'],
        'name': name,
      });
      if (source == 'show') group['active_show_breed'] = true;
      for (final v in _maps(breed['varieties'])) {
        if (source == 'show' && v['is_active'] != true) continue;
        if (source == 'breeder' && v['catalog_kind'] == 'legacy_ambiguous') {
          hidden.add({
            'breed': name,
            'variety': v['name'],
            'source': source,
            'id': v['id'],
            'status': 'hidden_legacy_ambiguous',
            'next_action':
                'Retain for import/history reconciliation. This label is already excluded by CatalogService.sortedChoices; do not infer a phenotype from it.',
          });
          continue;
        }
        final canonical =
            (source == 'breeder'
                    ? v['standard_name'] ?? v['name']
                    : showNames[v['id'].toString()] ?? v['name'])
                .toString();
        final entryKey = checklistIdentity(canonical);
        final entries = group['entries'] as Map<String, Map<String, dynamic>>;
        final entry = entries.putIfAbsent(
          entryKey,
          () => {
            'breed': group['breed'],
            'variety': canonical,
            'identity': '$key|$entryKey',
            'origins': <Map<String, dynamic>>[],
            'catalog_kind': v['catalog_kind'] ?? 'variety',
          },
        );
        (entry['origins'] as List).add({
          'source': source,
          'id': v['id'],
          'raw_breed': name,
          'raw_variety': v['name'],
          if (source == 'breeder') 'is_recognized': v['is_recognized'],
          if (v['standard_name'] != null) 'standard_name': v['standard_name'],
          if (v['standard_reference'] != null)
            'standard_reference': v['standard_reference'],
        });
      }
    }
  }
  final breeds = groups.values.toList()
    ..sort(
      (a, b) => a['identity'].toString().compareTo(b['identity'].toString()),
    );
  final statusCounts = {for (final key in checklistStatusLabels.keys) key: 0};
  final findings = <Map<String, dynamic>>[];
  var accepted = 0, pairCount = 0;
  final pairFailures = <Map<String, dynamic>>[];
  final outputEntries = <Map<String, dynamic>>[];
  for (final group in breeds) {
    final entries =
        (group['entries'] as Map<String, Map<String, dynamic>>).values.toList()
          ..sort(
            (a, b) => checklistIdentity(
              a['variety'],
            ).compareTo(checklistIdentity(b['variety'])),
          );
    final counts = {for (final key in checklistStatusLabels.keys) key: 0};
    final eligible = <Map<String, dynamic>>[];
    for (final entry in entries) {
      entry.addAll(
        classifyChecklistEntry(
          group['breed'],
          entry['variety'],
          kind: entry['catalog_kind'],
          activeShowBreed: group['active_show_breed'],
        ),
      );
      final status = entry['status'] as String;
      counts[status] = counts[status]! + 1;
      statusCounts[status] = statusCounts[status]! + 1;
      if (entry['calculator_accepts_recorded_label'] == true) {
        accepted++;
        eligible.add({
          'species': 'rabbit',
          'breed': group['breed'],
          'variety': entry['variety'],
        });
        if (status == 'needs_rules') {
          findings.add({
            'kind': 'generic_acceptance_requires_breed_review',
            'breed': group['breed'],
            'variety': entry['variety'],
            'note':
                'The prototype accepts this label, but the checklist does not count it as completed breed coverage.',
          });
        }
      }
      final rawIssues = <Map<String, dynamic>>[];
      for (final origin in _maps(entry['origins'])) {
        final raw = {
          'species': 'rabbit',
          'breed': origin['raw_breed'],
          'variety': origin['raw_variety'],
        };
        final rawIssue = RabbitColorPredictions.inputIssue(raw, raw);
        if (entry['calculator_accepts_recorded_label'] == true &&
            rawIssue != null) {
          rawIssues.add({
            'breed': raw['breed'],
            'variety': raw['variety'],
            'issue': rawIssue,
          });
        }
      }
      if (rawIssues.isNotEmpty) entry['raw_aliases_still_blocked'] = rawIssues;
      outputEntries.add(entry);
    }
    if (checkPairs) {
      for (var i = 0; i < eligible.length; i++) {
        for (var j = i; j < eligible.length; j++) {
          pairCount++;
          final sire = eligible[i], dam = eligible[j];
          try {
            final p = RabbitColorPredictions.predict(sire: sire, dam: dam);
            if (p.colors.isEmpty ||
                p.colors.any(
                  (c) =>
                      !c.minimum.isFinite ||
                      !c.maximum.isFinite ||
                      c.minimum < 0 ||
                      c.maximum > 1 ||
                      c.minimum > c.maximum,
                )) {
              throw StateError('Empty result or invalid probability bounds');
            }
          } catch (e) {
            pairFailures.add({
              'breed': group['breed'],
              'sire_variety': sire['variety'],
              'dam_variety': dam['variety'],
              'error': e.toString(),
            });
          }
        }
      }
    }
    group['status_counts'] = counts;
    group['variety_count'] = entries.length;
    group['breed_validation_complete'] = false;
    group.remove('entries');
  }
  final sourceCounts = <String, Map<String, int>>{};
  for (final name in ['breeder', 'show']) {
    final rows = name == 'breeder' ? breederRows : showRows;
    sourceCounts[name] = {
      'breed_rows': rows.length,
      'variety_rows': rows.fold(
        0,
        (sum, b) => sum + _maps(b['varieties']).length,
      ),
    };
  }
  bool hasSource(Map<String, dynamic> e, String source) =>
      _maps(e['origins']).any((o) => o['source'] == source);
  final showOnly = outputEntries
      .where((e) => hasSource(e, 'show') && !hasSource(e, 'breeder'))
      .toList();
  final breederOnly = outputEntries
      .where((e) => hasSource(e, 'breeder') && !hasSource(e, 'show'))
      .toList();
  final common = outputEntries
      .where((e) => hasSource(e, 'breeder') && hasSource(e, 'show'))
      .length;
  final aliasRows =
      sourceCounts['breeder']!['variety_rows']! -
      hidden.length -
      outputEntries.where((e) => hasSource(e, 'breeder')).length;
  return {
    'schema_version': 1,
    'scope':
        'Complete inventory of captured Breeder rabbit choices plus active global Show rabbit choices. This is a catalog checklist, not a claim of validated biology or worldwide breed coverage. Recognition flags are provenance only. No account or animal records were queried.',
    'source_captured_at': {
      for (final source in ['breeder', 'show'])
        source: sources[source]['captured_at'],
    },
    'source_counts': sourceCounts,
    'source_reconciliation': {
      'choices_in_both_catalogs': common,
      'active_show_choices_missing_from_breeder': [
        for (final e in showOnly)
          {'breed': e['breed'], 'variety': e['variety']},
      ],
      'breeder_choices_not_in_active_show_list': [
        for (final e in breederOnly)
          {'breed': e['breed'], 'variety': e['variety']},
      ],
      'canonical_alias_rows_collapsed': aliasRows,
      'note':
          'Breeder-only entries include photographed standard additions and saved/custom/legacy names. Absence from active Show choices is not a finding that they are biologically invalid or should be removed.',
    },
    'summary': {
      'breed_labels': breeds.length,
      'active_show_breeds': breeds
          .where((b) => b['active_show_breed'] == true)
          .length,
      'saved_breed_labels_needing_identity_review': breeds
          .where((b) => b['active_show_breed'] != true)
          .length,
      'effective_breed_variety_choices': outputEntries.length,
      'hidden_legacy_rows': hidden.length,
      'calculator_accepted_choices': accepted,
      'status_counts': statusCounts,
      'detail_dependent_choices_with_tested_examples': outputEntries
          .where((e) => e['details_handling_available'] == true)
          .length,
      'experimental_detail_choices': outputEntries
          .where((e) => e['experimental_details_only'] == true)
          .length,
      'breed_validation_complete': 0,
    },
    'breeds': breeds,
    'entries': outputEntries,
    'hidden_legacy_rows': hidden,
    'review_findings': findings,
    'pair_checks': {
      'performed': checkPairs,
      'same_breed_unordered_pairs_including_self': pairCount,
      'failures': pairFailures,
      'scope':
          'Software smoke check of accepted recorded labels using default unknown carriers; valid bounds do not establish biological correctness, breed-standard eligibility or coverage of all evidence combinations.',
    },
  };
}

String checklistMarkdown(Map<String, dynamic> audit) {
  String cell(dynamic v) =>
      v.toString().replaceAll('|', r'\|').replaceAll('\n', ' ');
  final summary = Map<String, dynamic>.from(audit['summary']);
  final counts = Map<String, dynamic>.from(summary['status_counts']);
  final entries = _maps(audit['entries']);
  final breeds = _maps(audit['breeds']);
  final out = StringBuffer('''# RingMaster genetics: breed and variety checklist

This checklist uses read-only snapshots of the live catalogs, captured ${audit['source_captured_at']['breeder']}.
It covers the app’s rabbit choices, including saved custom/legacy labels. It does not add dropdowns or change production catalog data or prediction rules.

## What this tells us

- Active global Show breed entries: **${summary['active_show_breeds']}**.
- Saved breed labels outside that active list: **${summary['saved_breed_labels_needing_identity_review']}**.
- Effective breed/variety choices after the picker’s canonical aliases and hidden ambiguous labels: **${summary['effective_breed_variety_choices']}**.
- Hidden ambiguous historical rows retained for reconciliation: **${summary['hidden_legacy_rows']}**.
- Active Show variety choices already represented in Breeder: **${audit['source_reconciliation']['choices_in_both_catalogs']}**.
- Active Show variety choices missing from Breeder: **${(audit['source_reconciliation']['active_show_choices_missing_from_breeder'] as List).length}**.
- Existing alias rows collapsed by the picker: **${audit['source_reconciliation']['canonical_alias_rows_collapsed']}**.
- Detail-dependent choices with tested explicit-color examples: **${summary['detail_dependent_choices_with_tested_examples']}**. These still need the actual rabbit’s saved details; examples are not defaults.
- Experimental detail-dependent choices: **${summary['experimental_detail_choices']}** (Lutino). A calculation path is not a validated breed model.
- Breed-wide completion sign-offs: **0**. Existing model availability and software checks are tracked separately from complete breed validation.

| Checklist status | Choices |
| --- | ---: |
''');
  for (final s in checklistStatusLabels.entries) {
    out.writeln('| ${s.value} | ${counts[s.key]} |');
  }
  out.writeln();
  out.write('''
“Shared estimate”, “Spotted-breed estimate”, “Hotot pigment only”, “Underlying color only; silvering excluded” and “Limited base-color model” mean software availability under stated assumptions, not completed breed genetics. The calculator currently accepts ${summary['calculator_accepted_choices']} recorded choices; some accepted generic interpretations are conservatively flagged for breed review below. These totals must not become a percentage of complete biological coverage.

## Work in order

1. **${counts['needs_name_mapping'] == 0 ? 'The known Standard/COD/format mappings in this snapshot are implemented.' : 'Resolve the remaining catalog name mappings.'}** Group handling now uses explicit saved colors for the detail-dependent labels. Missing descriptions remain blocked; the audit stores a tested example for each handled group, not a claim that every possible description works. Preserve original imported labels. Documented conditional mappings are in `name-mappings.md`.
2. **Finish special-breed rules.** The spotted preview keeps missing pattern information unknown; English Spot Gray/Gold have conditional family estimates (`english-spot-families.md`); exact ticking, shade and markings still need work. Hotot has pigment-only estimates (`hotot-pigment.md`); eye-band formation/Dutch interactions remain guarded. Silver/argent families have underlying-color estimates (`silvered-breeds.md`); silvering inheritance and expression remain unmodeled. See `spotted-breeds.md`.
3. **Finish the limited base-color previews.** Tan, Havana, Polish, Lilac and Beveren now use the shared coat engine with supported hidden carriers retained (`tan-shared-model.md` and `self-shared-models.md`). Dutch now uses underlying shared color families with spotting excluded (`dutch-shared-model.md`). Hotot remains a separate limited pigment model; exact markings and breed validation are still incomplete.
4. **Validate the conditional special-color paths.** All 12 formerly guarded labels have limited paths: Sandy/Steel Gray from conditional breed families, ten others from verified saved details. Lutino is explicitly experimental. See `remaining-special-models.md`; zero catalog rule gaps does not mean complete biological coverage. White eye-color distinctions, precise shade and marking quality remain separate limitations.
5. **Validate each breed and pair of varieties.** Confirm expected results against reliable references and documented breedings. Keep unknown genes as ranges and the estimate disclaimer visible.

The catalog itself cannot establish a rabbit’s complete genes. No genetic conclusions are inferred from recognition, a breed name, a COD label or an imported string alone.

## Breed overview

| Breed | Choices | Base only | Shared estimate | Spotted estimate | Hotot pigment only | Silver underlying color | Details | Name mapping | Rules | Identity review |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
''');
  for (final b in breeds) {
    final c = b['status_counts'];
    out.writeln(
      '| ${cell(b['breed'])} | ${b['variety_count']} | ${c['base_color_only']} | ${c['shared_estimate']} | ${c['spotted_estimate']} | ${c['eyeband_pigment_only']} | ${c['silver_family_only']} | ${c['needs_details']} | ${c['needs_name_mapping']} | ${c['needs_rules']} | ${c['needs_identity_review']} |',
    );
  }
  final standard = entries
      .where(
        (e) =>
            checklistIdentity(e['variety']) == 'standard' &&
            e['status'] == 'needs_name_mapping',
      )
      .map((e) => e['breed'])
      .toList();
  out.writeln('\n## Standard labels needing explicit breed interpretation\n');
  out.writeln(
    standard.isEmpty
        ? 'No remaining Standard name-mapping gaps in this captured catalog. Special-breed rule gaps are tracked separately.'
        : standard.map(cell).join(', '),
  );
  out.writeln('\n## Generic acceptance requiring review\n');
  final findings = _maps(audit['review_findings']);
  if (findings.isEmpty) {
    out.writeln('No additional accepted special-breed labels were identified.');
  }
  for (final f in findings) {
    out.writeln(
      '- [ ] ${cell(f['breed'])} — ${cell(f['variety'])}: ${cell(f['note'])}',
    );
  }
  out.writeln('\n## Every selectable breed / variety\n');
  for (final b in breeds) {
    out.writeln('### ${cell(b['breed'])}\n');
    out.writeln('| Variety | Status | Next work |\n| --- | --- | --- |');
    for (final e in entries.where((e) => e['breed'] == b['breed'])) {
      out.writeln(
        '| ${cell(e['variety'])} | ${cell(e['status_label'])} | ${cell(e['next_action'])} |',
      );
    }
    out.writeln();
  }
  out.writeln(
    '## Hidden historical labels\n\nThese rows are already hidden by the app’s picker. Keep them available for record/import reconciliation.\n',
  );
  for (final e in _maps(audit['hidden_legacy_rows'])) {
    out.writeln('- [ ] ${cell(e['breed'])} — ${cell(e['variety'])}');
  }
  final pairs = audit['pair_checks'];
  out.writeln();
  out.writeln('''
## Reproducing this checklist

Run `dart run tool/audit_genetics_coverage.dart --write --check-pairs` from the Flutter project.
The input is `docs/genetics/live-catalog-snapshot.json`; the machine-readable output is `docs/genetics/breed-variety-checklist.json`.
Use `--retained` for the older photographed subset only. Refresh the live snapshot with read-only catalog queries before treating this inventory as current after catalog changes.

Pair smoke checks performed: ${pairs['performed']}. Pairs calculated: ${pairs['same_breed_unordered_pairs_including_self']}. Failures: ${(pairs['failures'] as List).length}.
These checks exercise the software; they do not validate every biological interpretation. The app’s private email gate and support errors remain in place.
''');
  return out.toString();
}

String checklistJson(Map<String, dynamic> audit) =>
    '${const JsonEncoder.withIndent('  ').convert(audit)}\n';
