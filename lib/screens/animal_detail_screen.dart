import '../widgets/animal_management_section.dart';
import 'production_measurements_screen.dart';
import '../widgets/animal_import_history.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/pedigree_email_dialog.dart';
import '../utils/color_details.dart';
import '../widgets/ringmaster_page_shell.dart';
import 'package:flutter/material.dart';

import 'pedigree_tree_screen.dart';
import '../services/pedigree_service.dart';
import '../services/pedigree_pdf_service.dart';
import 'package:printing/printing.dart';
import '../utils/animal_labels.dart';
import 'dart:typed_data';
import 'health_records_screen.dart';
import 'show_reports_screen.dart';
import '../services/animal_service.dart';
import '../widgets/animal_avatar.dart';
import '../offline/offline_runtime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/genetics_preview.dart';
import '../genetics/animal_genotype.dart';
import '../widgets/animal_genotype_section.dart';

class _AnimalDetails {
  final Map<String, dynamic> animal;
  final double? weight;
  final bool weightDownloaded;
  const _AnimalDetails(this.animal, this.weight, this.weightDownloaded);
}

class AnimalDetailScreen extends StatefulWidget {
  final String animalId;
  final Future<Map<String, dynamic>> Function(String)? loader;
  final Future<double?> Function(String)? weightLoader;
  final Future<void> Function(String, Map<String, dynamic>, int)?
  genotypeWriter;

  const AnimalDetailScreen({
    super.key,
    required this.animalId,
    this.loader,
    this.weightLoader,
    this.genotypeWriter,
  });

  @override
  State<AnimalDetailScreen> createState() => _AnimalDetailScreenState();
}

class _AnimalDetailScreenState extends State<AnimalDetailScreen> {
  final supabase = OfflineRuntime.client;
  bool _uploadingPhoto = false;
  late Future<_AnimalDetails> _details = _load();

  Future<_AnimalDetails> _load() async {
    final animal = await fetchAnimal();
    try {
      return _AnimalDetails(animal, await fetchWeight(), true);
    } on OfflineDataUnavailable {
      // Missing optional history must not hide an animal already downloaded
      // with the herd list. Permission and other server errors still surface.
      return _AnimalDetails(animal, null, false);
    }
  }

  void _reload() => setState(() {
    _details = _load();
  });
  Future<void> _changeGenotype(Map<String, dynamic> animal) async {
    if (!GeneticsPreview.allowsEmail(supabase.auth.currentUser?.email) ||
        isLocked(animal['status'])) {
      return;
    }
    // The deployed schema supplies an empty genotype on preexisting rows.
    // Older downloaded rows may omit the new column until the next sync.
    final baseline = <String, dynamic>{
      'genotype': <String, dynamic>{},
      ...animal,
    };
    final updated = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StreamBuilder<AuthState>(
        stream: supabase.auth.onAuthStateChange,
        builder: (context, _) =>
            !GeneticsPreview.allowsEmail(supabase.auth.currentUser?.email)
            ? AlertDialog(
                content: const Text(
                  'This preview is not available for this account.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              )
            : AnimalGenotypeDialog(
                initial: AnimalGenotype.read(baseline['genotype']),
                colorInference: AnimalGenotype.colorInference(baseline),
                onSave: (value) async {
                  if (!GeneticsPreview.allowsEmail(
                    supabase.auth.currentUser?.email,
                  )) {
                    throw StateError(
                      'This preview is not available for this account.',
                    );
                  }
                  final changes = <String, dynamic>{'genotype': value};
                  final revision = (baseline['revision'] as num).toInt();
                  if (widget.genotypeWriter != null) {
                    await widget.genotypeWriter!(
                      widget.animalId,
                      changes,
                      revision,
                    );
                  } else {
                    await AnimalService.update(
                      widget.animalId,
                      changes,
                      expectedRevision: revision,
                      expectedBase: baseline,
                    );
                  }
                },
              ),
      ),
    );
    if (updated == true && mounted) {
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            OfflineRuntime.engine == null
                ? 'Genotype saved.'
                : 'Saved on this device. Open Sync to check upload status.',
          ),
        ),
      );
    }
  }

  Future<void> _uploadPhoto() async {
    setState(() => _uploadingPhoto = true);
    try {
      await AnimalService.uploadPhoto(widget.animalId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to upload photo. Choose a JPG, PNG or WebP under 5 MB and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploadingPhoto = false;
          _details = _load();
        });
      }
    }
  }

  /// --- Helpers ---
  bool isLocked(String status) => animalIsLocked(status);

  String statusLockMessage(String status) {
    if (status == "sold") return "This animal has been sold.";
    if (status == "deceased") return "This animal is marked deceased.";
    return "";
  }

  /// --- Queries ---
  Future<Map<String, dynamic>> fetchAnimal() =>
      (widget.loader ?? AnimalService.get)(widget.animalId);
  Future<Map<String, dynamic>?> fetchParent(String? id) =>
      AnimalService.parent(id);

  Future<double?> fetchWeight() =>
      (widget.weightLoader ?? AnimalService.latestWeight)(widget.animalId);

  // ------------------------------------------------------------
  // SAVE + SHARE PDF UTILITY
  // ------------------------------------------------------------
  Future<void> saveAndSharePdf({
    required Uint8List pdfBytes,
    required String fileName,
  }) async {
    try {
      await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Sharing failed: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
    stream: supabase.auth.onAuthStateChange,
    builder: (context, _) => _buildDetails(context),
  );

  Widget _buildDetails(BuildContext context) {
    return RingMasterPageShell(
      onRefresh: _reload,
      title: "Animal Details",
      body: FutureBuilder<_AnimalDetails>(
        future: _details,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                snapshot.error is OfflineDataUnavailable
                    ? snapshot.error.toString()
                    : "Unable to load records. Please go back and try again.",
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final animal = snapshot.data!.animal;
          final weight = snapshot.data!.weight;
          final locked = isLocked(animal["status"]);

          return AnimalDetailContent(
            animal: animal,
            weightText: !snapshot.data!.weightDownloaded
                ? 'Not downloaded'
                : weight == null
                ? '-'
                : '${weight.toStringAsFixed(2)} lb',
            lockMessage: locked ? statusLockMessage(animal['status']) : null,
            uploadingPhoto: _uploadingPhoto,
            onPhoto: locked ? null : _uploadPhoto,
            genotypeSection:
                GeneticsPreview.allowsEmail(supabase.auth.currentUser?.email) &&
                    animal['species']?.toString().toLowerCase() == 'rabbit'
                ? AnimalGenotypeSection(
                    animal: animal,
                    onChange: locked ? null : () => _changeGenotype(animal),
                  )
                : null,
            parents: [
              FutureBuilder(
                future: fetchParent(animal["sire_id"]),
                builder: (context, snap) {
                  final sire = snap.data;
                  return _row(
                    "Sire",
                    sire == null
                        ? "-"
                        : "${sire['name']} (${sire['tattoo'] ?? ''})",
                  );
                },
              ),

              FutureBuilder(
                future: fetchParent(animal["dam_id"]),
                builder: (context, snap) {
                  final dam = snap.data;
                  return _row(
                    "Dam",
                    dam == null
                        ? "-"
                        : "${dam['name']} (${dam['tattoo'] ?? ''})",
                  );
                },
              ),
            ],
            actions: [
              /// Edit Animal
              ElevatedButton(
                onPressed: locked
                    ? null
                    : () async {
                        final updated = await Navigator.pushNamed(
                          context,
                          "/edit-animal",
                          arguments: widget.animalId,
                        );

                        if (updated == true && mounted) _reload();
                      },
                child: const Text("Edit Animal"),
              ),

              AnimalManagementSection(animalId: widget.animalId),
              if (animal['species']?.toString().toLowerCase() == 'rabbit')
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProductionMeasurementsScreen(
                        recordId: widget.animalId,
                        wool: true,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.grass),
                  label: const Text('Wool harvest history'),
                ),
              AnimalImportHistory(
                key: ObjectKey(snapshot.data),
                animalId: widget.animalId,
              ),

              if (animal['status'] == 'sold') ...[
                ElevatedButton.icon(
                  onPressed: () =>
                      offerBuyerPedigree(context, animalId: widget.animalId),
                  icon: const Icon(Icons.email_outlined),
                  label: const Text('Email pedigree to buyer'),
                ),
              ],

              /// Weight History
              ElevatedButton(
                onPressed: () {
                  Navigator.pushNamed(
                    context,
                    "/weight-history",
                    arguments: {
                      'animalId': widget.animalId,
                      'status': animal["status"],
                    },
                  );
                },
                child: const Text("View Weight History"),
              ),

              ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProductionMeasurementsScreen(
                      recordId: widget.animalId,
                      animalFeed: true,
                    ),
                  ),
                ),
                icon: const Icon(Icons.restaurant_outlined),
                label: const Text('Feed & weight history'),
              ),

              /// Health & Vaccine Records
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          HealthRecordsScreen(animalId: widget.animalId),
                    ),
                  );
                },
                child: const Text("Health & Vaccine Records"),
              ),

              ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ShowReportsScreen(animalId: widget.animalId),
                  ),
                ),
                child: const Text('Show history & reports'),
              ),

              /// View Pedigree Tree
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          PedigreeTreeScreen(animalId: widget.animalId),
                    ),
                  );
                },
                child: const Text("View Pedigree Tree"),
              ),

              /// PDF EXPORT
              OutlinedButton(
                onPressed: () async {
                  try {
                    final pedigree = await PedigreeService.build(
                      widget.animalId,
                    );
                    final seller = await PedigreeService.seller();

                    final pdfBytes = await PedigreePdfService.generate(
                      pedigree: pedigree,
                      seller: seller,
                    );

                    await saveAndSharePdf(
                      pdfBytes: pdfBytes,
                      fileName: "pedigree-${widget.animalId}.pdf",
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text("PDF failed: $e")));
                  }
                },
                child: const Text("Export Pedigree PDF"),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(String title, Object? value) =>
      AnimalDetailRow(title: title, value: value);
}

class AnimalDetailRow extends StatelessWidget {
  final String title;
  final Object? value;
  const AnimalDetailRow({super.key, required this.title, this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            '$title:',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(value?.toString() ?? '-', textAlign: TextAlign.right),
        ),
      ],
    ),
  );
}

/// Presentation only: service calls and action permissions stay in the screen.
class AnimalDetailContent extends StatelessWidget {
  final Map<String, dynamic> animal;
  final String weightText;
  final String? lockMessage;
  final bool uploadingPhoto;
  final VoidCallback? onPhoto;
  final List<Widget> parents;
  final List<Widget> actions;
  final Widget? genotypeSection;

  const AnimalDetailContent({
    super.key,
    required this.animal,
    required this.weightText,
    this.lockMessage,
    this.uploadingPhoto = false,
    this.onPhoto,
    this.parents = const [],
    this.actions = const [],
    this.genotypeSection,
  });

  @override
  Widget build(BuildContext context) {
    final compact = BreederLayout.compact(context);
    final title = animalTitle(animal['name'], animal['tattoo']);
    final photoLabel = uploadingPhoto
        ? 'Uploading…'
        : animal['photo_path'] == null
        ? 'Upload photo'
        : 'Change photo';
    final basic = <(String, Object?)>[
      ('Tattoo', animal['tattoo']),
      ('Species', animal['species']),
      ('Breed', animal['breed']),
      ('Variety', varietyLabel(animal)),
      ('Sex', sexLabel(animal['species'], animal['sex'])),
      ('Current Weight', weightText),
    ];
    final registration = <Widget>[
      AnimalDetailRow(
        title: 'Registration #',
        value: animal['registration_number'],
      ),
      AnimalDetailRow(title: 'GC #', value: animal['grand_champion_number']),
      AnimalDetailRow(title: 'Legs', value: animal['legs']),
      if ((animal['leg_details'] ?? '').toString().isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SelectableText(
            'Legs / show details\n${animal['leg_details']}',
            key: const PageStorageKey('animal-leg-text'),
          ),
        ),
    ];
    return ListView(
      padding: BreederLayout.pagePadding(context, normal: 16),
      children: [
        if (compact)
          Row(
            children: [
              AnimalAvatar(
                species: animal['species'],
                photoUrl: animal['photo_url'],
                size: 48,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              if (onPhoto != null)
                IconButton(
                  tooltip: photoLabel,
                  onPressed: uploadingPhoto ? null : onPhoto,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                ),
            ],
          )
        else ...[
          Center(
            child: AnimalAvatar(
              species: animal['species'],
              photoUrl: animal['photo_url'],
              size: 112,
            ),
          ),
          if (onPhoto != null)
            Center(
              child: TextButton.icon(
                onPressed: uploadingPhoto ? null : onPhoto,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(photoLabel),
              ),
            ),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
        ],
        const AdaptiveGap(height: 16),
        if (lockMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              lockMessage!,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (compact && actions.isNotEmpty) ...[
          actions.first,
          const SizedBox(height: 12),
        ],
        if (compact)
          LayoutBuilder(
            builder: (context, constraints) {
              // Large accessibility text gets a single column rather than clipping.
              final columns =
                  constraints.maxWidth >= 280 &&
                      MediaQuery.textScalerOf(context).scale(14) <= 20
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  for (final (label, value) in basic)
                    SizedBox(
                      width: width,
                      child: Semantics(
                        label: '$label: ${value ?? '-'}',
                        excludeSemantics: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(
                              '${value ?? '-'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          )
        else
          for (final (label, value) in basic)
            AnimalDetailRow(title: label, value: value),
        if (genotypeSection != null) genotypeSection!,
        const AdaptiveGap(height: 16),
        if (compact) ...[
          ExpansionTile(
            key: const PageStorageKey('animal-registration'),
            title: const Text('Registration & show details'),
            children: registration,
          ),
          ExpansionTile(
            key: const PageStorageKey('animal-parents'),
            title: const Text('Parents'),
            children: parents,
          ),
        ] else ...[
          ...registration,
          const SizedBox(height: 24),
          ...parents,
        ],
        const AdaptiveGap(height: 24),
        // One column lets action labels grow with system text settings. It also
        // keeps every action discoverable without another menu on this page.
        for (final action in compact ? actions.skip(1) : actions) ...[
          action,
          const AdaptiveGap(height: 12),
        ],
      ],
    );
  }
}
